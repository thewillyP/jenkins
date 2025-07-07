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

echo "[DNS-JOB] Resolving host for job ${RUN_JOB_ID}..."
HOSTNAME=\$(sacct -j ${RUN_JOB_ID} --format=NodeList --noheader | awk '{print \$1}' | head -n 1)

if [[ -z "\$HOSTNAME" ]]; then
    echo "Error: Could not determine host for job ${RUN_JOB_ID}"
    exit 1
fi

echo "[DNS-JOB] SSH into host: \$HOSTNAME"

ssh -o StrictHostKeyChecking=no ${SSH_USER}@\$HOSTNAME \\
  'curl -fsSL ${SCRIPT_URL} | bash -s ${IMAGE}'
EOF
