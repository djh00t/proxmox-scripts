#!/bin/bash
###
### Cloudinit Template Builder
###

function do_convert_mb_to_bytes {
    # Convert MB to Bytes
    echo $(( $1 * 1024 * 1024 ))
}

function do_create_template {
    # Create VM Template
    qm create $VMTID \
    --name $VMNAME --numa 0 --ostype l26 \
    --cpu cputype=host --cores $CORES --sockets $SOCKETS \
    --memory $RAM  \
    --net0 virtio,bridge=$BRIDGE
}

function do_create_template_disk {
    # Create Disk for Template
    qm importdisk $VMTID $IMG $STORAGE

    # Attach Disk to Template
    qm set $VMTID --scsihw virtio-scsi-pci --virtio0 $STORAGE:vm-$VMTID-disk-0

}

function do_create_template_settings {
    # Set Template to use CloudInit
    qm set $VMTID --ide2 CEPH-GSW2-1:cloudinit

    # Set Template boot order so virtio0 is first
    qm set $VMTID --boot c --bootdisk virtio0

    # Set Template to use serial console
    qm set $VMTID --serial0 socket --vga serial0

    # Set Template to use qemu guest agent
    qm set $VMTID --agent enabled=1

    # Set Template to use DHCP by default
    qm set $VMTID --ipconfig0 ip=dhcp

    # Assign ordadmin ssh key to the template
    qm set $VMTID --sshkey /root/.ssh/ordadmin.id_rsa.pub

    # Make into a Template
    qm template $VMTID
}


# Set default values if not provided
if [ -z "$VMTID" ]; then
    VMTID=100
fi
if [ -z "$VMNAME" ]; then
    NAME="$VMTID-template"
fi
# Convert RAM to bytes if provided
if [ -z "$RAM" ]; then
    RAM=2048
else
    RAM=$(do_convert_mb_to_bytes $RAM)
fi
if [ -z "$CORES" ]; then
    CORES=1
fi
if [ -z "$SOCKETS" ]; then
    SOCKETS=1
fi
if [ -z "$BRIDGE" ]; then
    BRIDGE="vmbr0"
fi
if [ -z "$STORAGE" ]; then
    STORAGE="CEPH-GSW2-1"
fi
if [ -z "$IMG" ]; then
    IMG="/mnt/pve/nfs-ordnance/images/10003/jammy-server-cloudimg-amd64.img"
fi

function show_help {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -b, --bridge              Network bridge to use"
    echo "  -c, --cores               Number of CPU cores"
    echo "  -h, --help                Display this help and exit"
    echo "  -i, --image               CloudInit Disk Image to use"
    echo "  -n, --name                VM Template Name"
    echo "  -r, --ram                 RAM amount in MB"
    echo "  -s, --sockets             Number of CPU sockets"
    echo "  -S, --storage             Storage name to use"
    echo "  -v, --vmtid               VM Template ID Number"
    echo
    echo "Example Image Build:"
    echo "  $0 -b vmbr1000 -c 2 -i /mnt/pve/nfs-ordnance/images/10003/jammy-server-cloudimg-amd64.img -n jammy-server -r 8096 -s 1 -S CEPH-GSW2-1 -v 100"
    echo
}


# Make sure arguments are provided
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

# Collect arguments and set variables
while [ "$1" != "" ]; do
    case $1 in
    -b | --bridge)
        shift
        BRIDGE=$1
        ;;
    -c | --cores)
        shift
        CORES=$1
        ;;
    -h | --help)
        shift
        show_help
        ;;
    -i | --image)
        IMG=$1
        ;;
    -n | --name)
        shift
        NAME=$1
        ;;
    -r | --ram)
        shift
        RAM=$1
        ;;
    -s | --sockets)
        shift
        SOCKETS=$1
        ;;
    -S | --storage)
        shift
        STORAGE=$1
        ;;
    -v | --vmtid)
        shift
        VMTID=$1
        ;;
    *)
        show_help
        exit 1
        ;;
    esac
    shift
done
      
do_create_template
do_create_template_disk
do_create_template_settings

