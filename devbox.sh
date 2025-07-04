#!/bin/bash
#SBATCH --job-name=devbox
#SBATCH --output="/vast/wlp9800/logs/%x-%j.out"
#SBATCH --error="/vast/wlp9800/logs/%x-%j.err"
#SBATCH --time=7-00:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M

curl -sL https://raw.githubusercontent.com/thewillyP/jenkins/main/update_dns.sh | bash -s devbox

DNS_IP=$(< ~/willyp_ip.txt)

singularity run --dns "$DNS_IP" --bind ~/.ssh docker://thewillyp/devbox-ssh:latest
