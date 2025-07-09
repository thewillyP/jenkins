#!/bin/bash
LOG_DIR=$1
SIF_PATH=$2
OVERLAY_PATH=$3
SSH_USER=$4
BUILD_JOB_ID=$5
MEMORY=$6
CPUS=$7
TIME=$8
IMAGE=$9
TMP_DIR=${10}
USER_BINDS=${11}
SCRIPT_URL=${12}
USE_GPU=${13}
EXCLUSIVE=${14}

if [ "$USE_GPU" = "true" ]; then
    GPU_SLURM="#SBATCH --gres=gpu:1"
    GPU_SINGULARITY="--nv"
else
    GPU_SLURM=""
    GPU_SINGULARITY=""
fi

if [ -n "$BUILD_JOB_ID" ]; then
    SLURM_DEPENDENCY="#SBATCH --dependency=afterok:$BUILD_JOB_ID"
else
    SLURM_DEPENDENCY=""
fi

if [ "$EXCLUSIVE" = "true" ]; then
    SBATCH_EXCLUSIVE="#SBATCH --exclusive"
else
    SBATCH_EXCLUSIVE=""
fi

MANDATORY_BINDS="/home/${SSH_USER}/.ssh,${TMP_DIR}:/tmp"
if [ -n "$USER_BINDS" ]; then
    FULL_BINDS="${MANDATORY_BINDS},${USER_BINDS}"
else
    FULL_BINDS="${MANDATORY_BINDS}"
fi

sbatch <<EOF
#!/bin/bash
${SBATCH_EXCLUSIVE}
#SBATCH --job-name=run_${IMAGE}
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem=${MEMORY}
#SBATCH --time=${TIME}
#SBATCH --cpus-per-task=${CPUS}
#SBATCH --output=${LOG_DIR}/run-${IMAGE}-%j.log
#SBATCH --error=${LOG_DIR}/run-${IMAGE}-%j.err
${GPU_SLURM}
${SLURM_DEPENDENCY}

set -euo pipefail

ENTRYPOINT_FILE=\$(mktemp)
TMPDIR=\$(mktemp -d)

curl -fsSL ${SCRIPT_URL} -o \$ENTRYPOINT_FILE
curl -fsSL ${SCRIPT_URL}.sig -o \$TMPDIR/entrypoint.sh.sig

singularity run --cleanenv \\
    --env AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID},AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY},AWS_DEFAULT_REGION=us-east-1 \\
    docker://amazon/aws-cli \\
    ssm get-parameter --name "/gpg/public-key" --with-decryption --query Parameter.Value --output text > \$TMPDIR/public.key

gpg --no-default-keyring --keyring \$TMPDIR/pubring.gpg --import \$TMPDIR/public.key
gpg --no-default-keyring --keyring \$TMPDIR/pubring.gpg --verify \$TMPDIR/entrypoint.sh.sig \$ENTRYPOINT_FILE

# Open entrypoint on FD 3 and unlink it
exec 3<"\$ENTRYPOINT_FILE"
rm "\$ENTRYPOINT_FILE"

# Clean up everything else before running singularity
rm -rf "\$TMPDIR"

# Run entrypoint via FD
singularity exec ${GPU_SINGULARITY} \\
  --containall --no-home --cleanenv \\
  --env AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID},AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY},AWS_DEFAULT_REGION=us-east-1 \\
  --overlay ${OVERLAY_PATH}:rw \\
  --bind ${FULL_BINDS} \\
  ${SIF_PATH} \\
  bash <&3

# Close FD
exec 3<&-
EOF
