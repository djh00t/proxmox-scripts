#!/bin/bash
###
### Disable systemd-resolved and replace /etc/resolv.conf with a static configuration
###
# Create /etc/cloud/scripts/per-boot/03-resolvconf.sh

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
debug "#                        DNS BOOT SCRIPT                               #"
debug "########################################################################"

# Check if systemd-resolved is running if it is then stop and disable it
if [ $(systemctl is-active systemd-resolved) == "active" ]; then
    echo " --------------------------------------------------------------------------------------------"
    echo "| RESOLVCONF\tINFO\t\tsystemd-resolved is running, stopping and disabling it"
    echo " --------------------------------------------------------------------------------------------"
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved
fi

# Pull NetworkManager.conf from gist
echo -e " --------------------------------------------------------------------------------------------"
echo -e "| RESOLVCONF\tINFO\t\tPulling GIST:\t\tNetworkManager.conf"

# Download NetworkManager.conf from gist
curl --connect-timeout 3 -s -o /etc/NetworkManager/NetworkManager.conf https://gist.githubusercontent.com/fsg-gitbot/e1067620c0f45e3c082aa70255075afa/raw/k8s-NetworkManager.conf
# If $? is 0 then announce the change was successful
if [ $? -eq 0 ]; then
    echo -e "| RESOLVCONF\tOK\t\tPulled OK:\t\tNetworkManager.conf"
    echo -e " --------------------------------------------------------------------------------------------"
else
    echo -e "| RESOLVCONF\tFAIL\t\tPull Failed:\t\tNetworkManager.conf"
    echo -e " --------------------------------------------------------------------------------------------"
fi


# Check if /etc/resolv.conf is a symlink, if it is delete it and replace it with a static configuration
if [ -L /etc/resolv.conf ]; then

    echo -e "| RESOLVCONF\tINFO\t\tRemoving symlink:\t/etc/resolv.conf"

    rm /etc/resolv.conf
    echo -e "| RESOLVCONF\tOK\t\tRemoved symlink:\t/etc/resolv.conf"
    echo "nameserver 172.16.0.10" > /etc/resolv.conf
    echo "nameserver 172.16.0.11" >> /etc/resolv.conf
    echo -e "| RESOLVCONF\tOK\t\tCreated static:\t\t/etc/resolv.conf"
    echo " --------------------------------------------------------------------------------------------"
fi

exit 0

#EOF