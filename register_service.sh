#!/bin/bash
set -euo pipefail

if [[ $# -lt 8 ]]; then
    echo "Usage: $0 <job_id> <image> <log_dir> [memory] [time] [cpus] [proxyjump] <port> [localforwards] [--skip-dep] [--use-ssh]"
    exit 1
fi

RUN_JOB_ID="$1"
IMAGE="$2"
LOG_DIR="$3"
MEMORY="${4:-1G}"
TIME="${5:-00:05:00}"
CPUS="${6:-1}"
PROXYJUMP="${7:-greene}"
PORT="$8"
LOCALFORWARDS="${9:-}"
SKIP_DEP="${10:-false}"
USE_SSH="${11:-false}"

SBATCH_DEPENDENCY=""
if [[ "$SKIP_DEP" == "false" ]]; then
    SBATCH_DEPENDENCY="#SBATCH --dependency=after:${RUN_JOB_ID}"
fi

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
${SBATCH_DEPENDENCY}

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
FULL_HOSTNAME=\$(dig +short -x "\$(getent hosts "\$HOSTNAME" | awk '{print \$1}')" | head -n1)
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

echo "[CONSUL-REGISTER] Attempting to deregister existing service '${IMAGE}' (if present)..."
curl --silent --output /dev/null --write-out "%{http_code}" --request PUT \$CONSUL_ENDPOINT/v1/agent/service/deregister/${IMAGE}
echo "[CONSUL-REGISTER] Deregistration attempt completed."

# Build tags array
TAGS='"user:${USER}", "proxyjump:${PROXYJUMP}"'
if [[ "${USE_SSH}" != "false" ]]; then
    TAGS="\${TAGS}, \"ssh\""
fi

# Add LocalForward tags if provided
if [[ -n "${LOCALFORWARDS}" ]]; then
    echo "[CONSUL-REGISTER] Processing LocalForwards: ${LOCALFORWARDS}"
    IFS=',' read -ra FORWARDS <<< "${LOCALFORWARDS}"
    for forward in "\${FORWARDS[@]}"; do
        forward=\$(echo "\$forward" | xargs)
        if [[ -n "\$forward" ]]; then
            TAGS="\$TAGS, \"localforward:\$forward\""
        fi
    done
fi

echo "[CONSUL-REGISTER] Registering service with Consul at \$CONSUL_ENDPOINT..."
curl --request PUT --data @- \$CONSUL_ENDPOINT/v1/agent/service/register <<CONSUL_EOF
{
 "Name": "${IMAGE}",
 "Tags": [\$TAGS],
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
