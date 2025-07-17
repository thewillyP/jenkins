#!/bin/bash
set -euo pipefail

RUN_JOB_ID="$1"
IMAGE="$2"
LOG_DIR="$3"
MEMORY="${4:-1G}"
TIME="${5:-00:05:00}"
CPUS="${6:-1}"
PROXYJUMP="${7:-greene}"
PORT="$8"

sbatch <<EOF
#!/bin/bash
#SBATCH --job-name=consul-register
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem=${MEMORY}
#SBATCH --time=${TIME}
#SBATCH --cpus-per-task=${CPUS}
#SBATCH --output=${LOG_DIR}/consul-register-%j.log
#SBATCH --error=${LOG_DIR}/consul-register-%j.err
#SBATCH --dependency=after:${RUN_JOB_ID}

set -euo pipefail

echo "[CONSUL-REGISTER] Checking job ${RUN_JOB_ID} state..."
JOB_STATE=\$(sacct -j ${RUN_JOB_ID} --format=State --noheader | head -n1 | awk '{print \$1}')
if [[ "\$JOB_STATE" != "RUNNING" ]]; then
    echo "[CONSUL-REGISTER] Job \${RUN_JOB_ID} is in state '\$JOB_STATE' — not running, exiting cleanly."
    exit 0
fi

echo "[CONSUL-REGISTER] Resolving host for job ${RUN_JOB_ID}..."
HOSTNAME=\$(sacct -j ${RUN_JOB_ID} --format=NodeList --noheader | awk '{print \$1}' | head -n 1)
if [[ -z "\$HOSTNAME" ]]; then
    echo "Error: Could not determine host for job ${RUN_JOB_ID}"
    exit 1
fi

echo "[CONSUL-REGISTER] Getting full hostname..."
# Try to get the full hostname using DNS lookup
FULL_HOSTNAME=\$(dig +short -x "\$(dig +short \$HOSTNAME)" | head -n1 | sed 's/\.$//') 
if [[ -z "\$FULL_HOSTNAME" ]]; then
    echo "[CONSUL-REGISTER] Could not resolve full hostname, using short hostname: \$HOSTNAME"
    FULL_HOSTNAME=\$HOSTNAME
else
    echo "[CONSUL-REGISTER] Resolved full hostname: \$FULL_HOSTNAME"
fi

echo "[CONSUL-REGISTER] Getting Consul endpoint from AWS..."
CONSUL_ENDPOINT=\$(singularity run --cleanenv \\
    --env AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID},AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY},AWS_DEFAULT_REGION=us-east-1 \\
    docker://amazon/aws-cli \\
    ssm get-parameter --name "/dev/general/consul_endpoint" --with-decryption --query Parameter.Value --output text)

if [[ -z "\$CONSUL_ENDPOINT" ]]; then
    echo "Error: Could not retrieve Consul endpoint from AWS"
    exit 1
fi

echo "[CONSUL-REGISTER] Registering service with Consul at \$CONSUL_ENDPOINT..."

# Register the service with Consul
curl --request PUT --data @- \$CONSUL_ENDPOINT/v1/agent/service/register <<CONSUL_EOF
{
    "Name": "${IMAGE}",
    "Tags": ["user:${USER}", "proxyjump:${PROXYJUMP}", "ssh"],
    "Address": "\$FULL_HOSTNAME",
    "Port": ${PORT},
    "Check": {
        "TCP": "\$FULL_HOSTNAME:${PORT}",
        "Interval": "10s",
        "Timeout": "1s"
    }
}
CONSUL_EOF

echo "[CONSUL-REGISTER] Service registration completed successfully"
EOF