#!/bin/bash
###
### Proxmox Add Disk Script
###


function show_help {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -s, --size                Disk size in GB"
    echo "  -v, --vmid                VM ID Number"
    echo
    echo "Example Image Build:"
    echo "  $0 -s 10 -v 100"
    echo
}



# Make sure arguments are provided
#if [ $# -eq 0 ]; then
#    show_help
#    exit 1
#fi

# Collect arguments and set variables
while [ "$1" != "" ]; do
    case $1 in
        -s | --size )           shift
                                SIZE=$1
                                ;;
        -v | --vmid )           shift
                                VMID=$1
                                ;;
        * )                     show_help
                                exit 1
    esac
    shift
done

# Set Variables
STORAGE="nfs-ordnance"

# Get all disk devices currently attached to $VMID
DISKS=$(qm config $VMID | grep -E '^virtio[0-9]' | awk -F: '{print $1}')

# Get the last disk device number
LASTDISK=$(echo $DISKS | awk '{print $NF}' | sed 's/virtio//')

# Increment the last disk device number by 1
NEWDISK=$((LASTDISK + 1))

# Create the new disk device name
NEWDEV=virtio$NEWDISK




# Create the new disk device
echo qm set $VMID --$NEWDEV $STORAGE:$SIZE,backup=0,iothread=1,cache=none,discard=on
qm set $VMID --$NEWDEV $STORAGE:$SIZE,backup=0,iothread=1,cache=none,discard=on

