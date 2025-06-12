#!/bin/bash
#SBATCH --job-name=jenkins
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=06:00:00
#SBATCH --output="/vast/wlp9800/logs/%x-%j.out"
#SBATCH --error="/vast/wlp9800/logs/%x-%j.err"


source ~/.secrets/env.sh

# Ensure the postgres directory exists
mkdir -p "$JENKINS_DATA_DIR"



# Set or replace DB_HOST in env.sh with the current hostname
sed -i '/^export DB_HOST_OHO=/d' ~/.secrets/env.sh
echo "export DB_HOST_OHO=$(hostname)" >> ~/.secrets/env.sh

singularity run --containall --cleanenv \
  --env JENKINS_OPTS="--httpPort=$JENKINS_PORT" \
  --bind $JENKINS_DATA_DIR:/var/jenkins_home \
  docker://jenkins/jenkins:lts-jdk17@sha256:3cc41bac7bdeba7fef4c5421f72d0143b08b288362e539143aed454a6c7dade5


