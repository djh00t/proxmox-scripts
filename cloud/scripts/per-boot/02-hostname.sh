#!/bin/bash
###
### Set hostname to match reverse DNS of mgmt interface
###
# Create /etc/cloud/scripts/per-boot/02-hostname.sh

function debug() {
    # echo $1 to screen if $DEBUG is set to 1
    if [ "$DEBUG" == "1" ]; then
        echo -e "| CORE\t\tDEBUG\t\t$1"
    fi
}

function help() {
    # Script arguments
    echo -e "Usage: $0 [OPTION]..."
    echo
    echo -e "  -d, --debug     Display debug information while executing"
    echo -e "  -h, --help      Display this help and exit"
}

# Script arguments
while [ "$1" != "" ]; do
    case $1 in
    -d | --debug)
        set DEBUG=1
        shift
        ;;
    -h | --help)
        help
        exit
        ;;
    *)
        set DEBUG=0
        shift
        ;;
    esac
done

debug "########################################################################"
debug "#                     HOSTNAME BOOT SCRIPT                             #"
debug "########################################################################"

# Find network interface with lowest interface number
NIC0=$(ip route | grep default | awk '{print $5}' | sort | head -n 1)

# Find next highest numbered interface
NIC1=$(ip route | grep default | awk '{print $5}' | sort | head -n 2 | tail -n 1)

# Echo network names and roles
echo -e " --------------------------------------------------------------------------------------------"
echo -e "| HOSTNAME\tOK\t\tManagement Interface:\t$NIC0"
echo -e "| HOSTNAME\tOK\t\tInternet Interface:\t$NIC1"

# Get primary IP address of $NIC0
IP0=$(ip addr show $NIC0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)

# Get the reverse DNS entry for the IP address
RDNS=$(dig +short -x $IP0)

# Remove the last . from the value
RDNS=${RDNS%?}

# Set the hostname
echo -e "| HOSTNAME\tOK\t\tSetting hostname to:\t$RDNS"
hostnamectl set-hostname $RDNS
echo -e " --------------------------------------------------------------------------------------------"

exit 0

#EOF