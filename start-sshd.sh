#!/bin/bash
mkdir -p ~/hostkeys
ssh-keygen -q -N "" -t rsa -b 4096 -f ~/hostkeys/ssh_host_rsa_key <<< y
exec /usr/sbin/sshd -D -p 2222 \
  -o PermitUserEnvironment=yes \
  -o PermitTTY=yes \
  -o X11Forwarding=yes \
  -o AllowTcpForwarding=yes \
  -o GatewayPorts=yes \
  -o ForceCommand=/bin/bash \
  -o UsePAM=no \
  -h ~/hostkeys/ssh_host_rsa_key