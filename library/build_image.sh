#!/bin/bash

SCRATCH_DIR=$1
OVERLAY_PATH=$2
SIF_PATH=$3
DOCKER_URL=$4
LOG_DIR=$5
IMAGE=$6
MEMORY=$7
CPUS=$8
OVERLAY_SRC=$9
TIME=${10}
ACCOUNT=${11:-}

ACCOUNT_DIRECTIVE=""
if [[ -n "$ACCOUNT" ]]; then
    ACCOUNT_DIRECTIVE="#SBATCH --account=${ACCOUNT}"
fi

sbatch <<EOF
#!/bin/bash
#SBATCH --job-name=build_${IMAGE}
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${CPUS}
#SBATCH --mem=${MEMORY}
#SBATCH --time=${TIME}
#SBATCH --output=${LOG_DIR}/build-${IMAGE}-%j.log
#SBATCH --error=${LOG_DIR}/build-${IMAGE}-%j.err
${ACCOUNT_DIRECTIVE}

mkdir -p ${SCRATCH_DIR}/images
cp -rp ${OVERLAY_SRC} ${OVERLAY_PATH}.gz
gunzip -f ${OVERLAY_PATH}.gz
singularity build --force ${SIF_PATH} ${DOCKER_URL}
EOF