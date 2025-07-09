#!/bin/bash
#SBATCH --job-name=startup
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=7-00:00:00
#SBATCH --output="/vast/wlp9800/logs/%x-%j.out"
#SBATCH --error="/vast/wlp9800/logs/%x-%j.err"

set -euo pipefail

export JENKINS_DATA_DIR=/scratch/wlp9800/jenkins
export JENKINS_TMP_DIR=/scratch/wlp9800/jenkins_tmp
export JENKINS_PORT=8245

mkdir -p "$JENKINS_DATA_DIR" "$JENKINS_TMP_DIR"

# Check DNS IP file
DNS_IP_FILE=~/willyp_ip.txt
if [ ! -f "$DNS_IP_FILE" ]; then
  echo "DNS IP file ($DNS_IP_FILE) not found. Exiting."
  exit 1
fi

SCRIPT_TMPDIR=$(mktemp -d)

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

# Run update_dns.sh with GPG verification
DNS_SCRIPT_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/update_dns.sh"
DNS_SIGNATURE_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/update_dns.sh.sig"
verify_script "$DNS_SCRIPT_URL" "$DNS_SIGNATURE_URL" "$SCRIPT_TMPDIR/update_dns.sh"
echo "Executing verified update_dns.sh..."
bash "$SCRIPT_TMPDIR/update_dns.sh" jenkins

# Submit devbox job with GPG verification
DEVBOX_SCRIPT_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/devbox.sh"
DEVBOX_SIGNATURE_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/devbox.sh.sig"
verify_script "$DEVBOX_SCRIPT_URL" "$DEVBOX_SIGNATURE_URL" "$SCRIPT_TMPDIR/devbox.sh"
echo "Submitting verified devbox.sh..."
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} sbatch "$SCRIPT_TMPDIR/devbox.sh"

# Submit startup.sh with GPG verification and dependency
STARTUP_SCRIPT_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/startup.sh"
STARTUP_SIGNATURE_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/startup.sh.sig"
verify_script "$STARTUP_SCRIPT_URL" "$STARTUP_SIGNATURE_URL" "$SCRIPT_TMPDIR/startup.sh"
echo "Submitting verified startup.sh with dependency..."
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} sbatch --dependency=afterok:$SLURM_JOB_ID "$SCRIPT_TMPDIR/startup.sh"

rm -rf "$SCRIPT_TMPDIR"

# Run Jenkins container
singularity run --containall --cleanenv --no-home \
  --env JENKINS_OPTS="--httpPort=$JENKINS_PORT" \
  --bind $JENKINS_DATA_DIR:/var/jenkins_home \
  --bind $JENKINS_TMP_DIR:/tmp \
  --bind /home/${USER}/.ssh \
  --dns "$(cat ~/willyp_ip.txt)" \
  docker://jenkins/jenkins:lts-jdk17@sha256:3cc41bac7bdeba7fef4c5421f72d0143b08b288362e539143aed454a6c7dade5