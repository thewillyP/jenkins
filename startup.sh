#!/bin/bash
#SBATCH --job-name=jenkins
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=06:00:00
#SBATCH --output="/vast/wlp9800/logs/%x-%j.out"
#SBATCH --error="/vast/wlp9800/logs/%x-%j.err"

set -euo pipefail

export JENKINS_DATA_DIR=/scratch/wlp9800/jenkins
export JENKINS_PORT=8333
export LOCAL_PORT=9999

mkdir -p "$JENKINS_DATA_DIR"

SCRIPT_TMPDIR=$(mktemp -d)
gpgconf --launch gpg-agent

# Function to fetch and verify script with GPG
verify_script() {
    local script_url=$1
    local signature_url=$2
    local output_file=$3

    echo "Fetching public key from AWS SSM..."
    singularity run --cleanenv \
        --env AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID},AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY},AWS_DEFAULT_REGION=us-east-1 \
        docker://amazon/aws-cli \
        ssm get-parameter --name "/gpg/public-key" --with-decryption --query Parameter.Value --output text > $SCRIPT_TMPDIR/public.key

    echo "Importing public key..."
    gpg --no-default-keyring --keyring $SCRIPT_TMPDIR/pubring.gpg --import $SCRIPT_TMPDIR/public.key

    echo "Downloading script and signature..."
    curl -fsSL "$script_url" -o "$output_file"
    curl -fsSL "$signature_url" -o "$output_file.sig"

    echo "Verifying script signature..."
    gpg --no-default-keyring --keyring $SCRIPT_TMPDIR/pubring.gpg --verify "$output_file.sig" "$output_file"
}

# Submit register_service.sh with GPG verification and dependency
REGISTER_SCRIPT_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/register_service.sh"
REGISTER_SIGNATURE_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/register_service.sh.sig"
verify_script "$REGISTER_SCRIPT_URL" "$REGISTER_SIGNATURE_URL" "$SCRIPT_TMPDIR/register_service.sh"
echo "Submitting verified register_service.sh with dependency..."
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
    bash "$SCRIPT_TMPDIR/register_service.sh" \
    "$SLURM_JOB_ID" \
    jenkins \
    /vast/wlp9800/logs \
    1G \
    00:05:00 \
    1 \
    greene \
    $JENKINS_PORT \
    "${LOCAL_PORT}:localhost:${JENKINS_PORT}" \
    --skip-dep \
    --dont-use-ssh

# Submit startup.sh with GPG verification and dependency
#STARTUP_SCRIPT_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/startup.sh"
#STARTUP_SIGNATURE_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/startup.sh.sig"
#verify_script "$STARTUP_SCRIPT_URL" "$STARTUP_SIGNATURE_URL" "$SCRIPT_TMPDIR/startup.sh"
#echo "Submitting verified startup.sh with dependency..."
#AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} sbatch --dependency=afterany:$SLURM_JOB_ID "$SCRIPT_TMPDIR/startup.sh"

rm -rf "$SCRIPT_TMPDIR"

# Run Jenkins container
singularity run --containall --cleanenv --no-home \
    --env JENKINS_OPTS="--httpPort=$JENKINS_PORT" \
    --bind $JENKINS_DATA_DIR:/var/jenkins_home \
    --bind $SLURM_TMPDIR:/tmp \
    --bind /home/${USER}/.ssh \
    docker://jenkins/jenkins:lts-jdk21
