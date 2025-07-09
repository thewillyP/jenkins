#!/bin/bash
#SBATCH --job-name=devbox
#SBATCH --output="/vast/wlp9800/logs/%x-%j.out"
#SBATCH --error="/vast/wlp9800/logs/%x-%j.err"
#SBATCH --time=7-00:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1GB

set -euo pipefail

TMPDIR=$(mktemp -d)

# Function to fetch and verify script with GPG
verify_script() {
  local script_url=$1
  local signature_url=$2
  local output_file=$3

  echo "Fetching public key from AWS SSM..."
  singularity run --cleanenv \
    --env AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID},AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY},AWS_DEFAULT_REGION=us-east-1 \
    docker://amazon/aws-cli \
    ssm get-parameter --name "/gpg/public-key" --with-decryption --query Parameter.Value --output text > $TMPDIR/public.key

  echo "Importing public key..."
  gpg --no-default-keyring --keyring $TMPDIR/pubring.gpg --import $TMPDIR/public.key

  echo "Downloading script and signature..."
  curl -fsSL "$script_url" -o "$output_file"
  curl -fsSL "$signature_url" -o "$output_file.sig"

  echo "Verifying script signature..."
  gpg --no-default-keyring --keyring $TMPDIR/pubring.gpg --verify "$output_file.sig" "$output_file"
}

# Run update_dns.sh with GPG verification
DNS_SCRIPT_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/update_dns.sh"
DNS_SIGNATURE_URL="https://raw.githubusercontent.com/thewillyP/jenkins/main/update_dns.sh.sig"
verify_script "$DNS_SCRIPT_URL" "$DNS_SIGNATURE_URL" "$TMPDIR/update_dns.sh"
echo "Executing verified update_dns.sh..."
bash "$TMPDIR/update_dns.sh" devbox

DNS_IP=$(< "$DNS_IP_FILE")

rm -rf "$TMPDIR"

singularity run --dns "$DNS_IP" --bind ~/.ssh docker://thewillyp/devbox-ssh:latest