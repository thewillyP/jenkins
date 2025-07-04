#!/bin/bash
set -e

# Get hostname
HOSTNAME=$(hostname -f)

# Get DNS IP from file
DNS_IP=$(cat ~/willyp_ip.txt)

# Set TSIG key location
KEYFILE=~/jenkins_tsig.key

# Set DNS info
DNS_ZONE="internal."
RECORD="jenkins.internal."
CNAME_TARGET="${HOSTNAME}."

# Run nsupdate via heredoc
nsupdate -k "$KEYFILE" <<EOF
server $DNS_IP
zone $DNS_ZONE
update delete $RECORD CNAME
update add $RECORD 60 CNAME $CNAME_TARGET
send
EOF

echo "CNAME $RECORD -> $CNAME_TARGET updated on $DNS_IP"
