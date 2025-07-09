#!/bin/bash
set -e

# Check usage
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <record-subdomain> (e.g. jenkins, devbox)"
  exit 1
fi

SUBDOMAIN="$1"

# Validate subdomain (basic check: no dots or spaces)
if [[ "$SUBDOMAIN" =~ [^a-zA-Z0-9-] ]]; then
  echo "Invalid subdomain: $SUBDOMAIN. Only alphanumerics and dashes are allowed."
  exit 1
fi

# Compose full record
RECORD="${SUBDOMAIN}.internal."
DNS_ZONE="internal."

# Get hostname
CNAME_TARGET=$(dig +short -x "$(hostname -i)" | head -n1)
# Can't use hostname -f because doesn't give FQDN for some reason...

# Get DNS IP from file
DNS_IP=$(cat ~/willyp_ip.txt)

# TSIG key
KEYFILE=~/dns_tsig.key

# Run nsupdate
nsupdate -k "$KEYFILE" <<EOF
server $DNS_IP
zone $DNS_ZONE
update delete $RECORD CNAME
update add $RECORD 60 CNAME $CNAME_TARGET
send
EOF

echo "CNAME $RECORD -> $CNAME_TARGET updated on $DNS_IP"
