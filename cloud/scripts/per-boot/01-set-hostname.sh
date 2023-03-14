#!/bin/bash
###
### Set hostname to match reverse DNS of mgmt interface
###
# Create /etc/cloud/scripts/per-boot/01-set-hostname.sh

# Figure out which NIC the default route is on
NIC=$(ip route | grep default | awk '{print $5}')

# Get primary IP address of $NIC
IP=$(ip addr show $NIC | grep "inet " | awk '{print $2}' | cut -d/ -f1)

# Get the reverse DNS entry for the IP address
RDNS=$(dig +short -x $IP)

# Remove the last . from the value
RDNS=${RDNS%?}

# Set the hostname
hostnamectl set-hostname $RDNS

exit 0

# EOF