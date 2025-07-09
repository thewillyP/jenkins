#!/bin/bash

set -euo pipefail

RUN_JOB_ID="$1"
IMAGE="$2"
LOG_DIR="$3"
JOB_NAME="$4"
MEMORY="${5:-1G}"
TIME="${6:-00:05:00}"
CPUS="${7:-1}"
SSH_USER="${8:-$USER}"

SCRIPT_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/update_dns.sh"
SIGNATURE_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/update_dns.sh.sig"

sbatch <<EOF
#!/bin/bash
#SBATCH --job-name=${JOB_NAME}
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem=${MEMORY}
#SBATCH --time=${TIME}
#SBATCH --cpus-per-task=${CPUS}
#SBATCH --output=${LOG_DIR}/${JOB_NAME}-%j.log
#SBATCH --error=${LOG_DIR}/${JOB_NAME}-%j.err
#SBATCH --dependency=after:${RUN_JOB_ID}

set -euo pipefail

echo "[DNS-JOB] Checking job ${RUN_JOB_ID} state..."

JOB_STATE=\$(sacct -j ${RUN_JOB_ID} --format=State --noheader | head -n1 | awk '{print \$1}')

if [[ "\$JOB_STATE" != "RUNNING" ]]; then
    echo "[DNS-JOB] Job \${RUN_JOB_ID} is in state '\$JOB_STATE' — not running, exiting cleanly."
    exit 0
fi

echo "[DNS-JOB] Resolving host for job ${RUN_JOB_ID}..."
HOSTNAME=\$(sacct -j ${RUN_JOB_ID} --format=NodeList --noheader | awk '{print \$1}' | head -n 1)

if [[ -z "\$HOSTNAME" ]]; then
    echo "Error: Could not determine host for job ${RUN_JOB_ID}"
    exit 1
fi

echo "[DNS-JOB] SSH into host: \$HOSTNAME"

ssh -o StrictHostKeyChecking=no ${SSH_USER}@\$HOSTNAME /bin/bash <<'SSH_EOF'
  set -euo pipefail
  TMPDIR=\$(mktemp -d)

  echo "[DNS-JOB] Fetching public key from AWS SSM..."
  singularity run --cleanenv \\
    --env AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID},AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY},AWS_DEFAULT_REGION=us-east-1 \\
    docker://amazon/aws-cli \\
    ssm get-parameter --name "/gpg/public-key" --with-decryption --query Parameter.Value --output text > \$TMPDIR/public.key

  echo "[DNS-JOB] Importing public key..."
  gpg --no-default-keyring --keyring \$TMPDIR/pubring.gpg --import \$TMPDIR/public.key

  echo "[DNS-JOB] Downloading script and signature..."
  curl -fsSL ${SCRIPT_URL} -o \$TMPDIR/update_dns.sh
  curl -fsSL ${SIGNATURE_URL} -o \$TMPDIR/update_dns.sh.sig

  echo "[DNS-JOB] Verifying script signature..."
  gpg --no-default-keyring --keyring \$TMPDIR/pubring.gpg --verify \$TMPDIR/update_dns.sh.sig \$TMPDIR/update_dns.sh

  echo "[DNS-JOB] Executing verified script..."
  bash \$TMPDIR/update_dns.sh ${IMAGE}

  rm -rf \$TMPDIR
SSH_EOF
EOF