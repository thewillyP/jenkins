#!/bin/bash
#SBATCH --job-name=devbox
#SBATCH --output="/vast/wlp9800/logs/%x-%j.out"
#SBATCH --error="/vast/wlp9800/logs/%x-%j.err"
#SBATCH --time=06:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M


# Get DNS IP from file
DNS_IP=$(< ~/willyp_ip.txt)

# Get public key from current user
PUBKEY=$(cat ~/.ssh/id_rsa.pub)

# Username = whoever submitted this script
USERNAME="$USER"

# Run container via singularity with all proper envs
singularity exec \
  --env PUBLIC_KEY="$PUBKEY" \
  --env USER_NAME="$USERNAME" \
  --env TZ=UTC \
  --env PUID=$(id -u) \
  --env PGID=$(id -g) \
  --dns "$DNS_IP" \
  --bind ~/.ssh:/config/.ssh \
  docker://lscr.io/linuxserver/openssh-server \
  /init
