#!/bin/bash
#SBATCH --job-name=devbox-ssh
#SBATCH --output="/vast/wlp9800/logs/%x-%j.out"
#SBATCH --error="/vast/wlp9800/logs/%x-%j.err"
#SBATCH --time=06:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M

# Create hostkeys dir and generate RSA host key
mkdir -p ~/hostkeys
ssh-keygen -q -N "" -t rsa -b 4096 -f ~/hostkeys/ssh_host_rsa_key <<< y

# Read DNS from your file
DNS_IP=$(< ~/willyp_ip.txt)

# Run the container using singularity
singularity exec \
  --bind ~/.ssh \
  --dns "$DNS_IP" \
  docker://linuxserver/openssh-server \
  /usr/sbin/sshd -D -p 2222 \
    -o PermitUserEnvironment=yes \
    -o PermitTTY=yes \
    -o X11Forwarding=yes \
    -o AllowTcpForwarding=yes \
    -o GatewayPorts=yes \
    -o ForceCommand=/bin/bash \
    -o UsePAM=no \
    -h ~/hostkeys/ssh_host_rsa_key
