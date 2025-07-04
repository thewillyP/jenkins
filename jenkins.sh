#!/bin/bash
#SBATCH --job-name=jenkins
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=7-00:00:00
#SBATCH --output="/vast/wlp9800/logs/%x-%j.out"
#SBATCH --error="/vast/wlp9800/logs/%x-%j.err"

export JENKINS_DATA_DIR=/scratch/wlp9800/jenkins
export JENKINS_TMP_DIR=/scratch/wlp9800/jenkins_tmp
export JENKINS_PORT=8245

mkdir -p "$JENKINS_DATA_DIR" "$JENKINS_TMP_DIR"

# Check for DNS IP file
DNS_IP_FILE=~/willyp_ip.txt
if [ ! -f "$DNS_IP_FILE" ]; then
  echo "DNS IP file ($DNS_IP_FILE) not found. Exiting."
  exit 1
fi

# Run update_dns.sh directly by streaming from GitHub to bash
curl -sL https://raw.githubusercontent.com/thewillyP/jenkins/main/update_dns.sh | bash

# Run Jenkins container with singularity
singularity run --containall --cleanenv --no-home \
  --env JENKINS_OPTS="--httpPort=$JENKINS_PORT" \
  --bind $JENKINS_DATA_DIR:/var/jenkins_home \
  --bind $JENKINS_TMP_DIR:/tmp \
  --bind /home/${USER}/.ssh \
  --dns "$(cat ~/willyp_ip.txt)" \
  docker://jenkins/jenkins:lts-jdk17@sha256:3cc41bac7bdeba7fef4c5421f72d0143b08b288362e539143aed454a6c7dade5
