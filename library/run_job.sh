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

MANDATORY_BINDS="/home/${SSH_USER}/.ssh,${TMP_DIR}:/tmp"
if [ -n "$USER_BINDS" ]; then
    FULL_BINDS="${MANDATORY_BINDS},${USER_BINDS}"
else
    FULL_BINDS="${MANDATORY_BINDS}"
fi

sbatch <<EOF
#!/bin/bash
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

curl -fsSL ${SCRIPT_URL} | singularity exec ${GPU_SINGULARITY} \\
  --containall --no-home --cleanenv \\
  --overlay ${OVERLAY_PATH}:rw \\
  --bind ${FULL_BINDS} \\
  ${SIF_PATH} \\
  bash
EOF
