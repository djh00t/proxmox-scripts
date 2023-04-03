#!/bin/bash
###
### Cloudinit Template Builder
###

function do_convert_gb_to_mb {
    # Convert GB to MB
    echo $(( $1 * 1024 ))
}

function do_create_template {
    # Create VM Template
    echo qm create $VMTID --name $NAME --onboot 1 --numa 0 --ostype l26 --cpu cputype=host --cores $CORES --sockets $SOCKETS --memory $RAM --net0 virtio,tag=1000,bridge=$BRIDGE --net1 virtio,tag=666,firewall=1,bridge=$BRIDGE
    qm create $VMTID --name $NAME --onboot 1 --numa 0 --ostype l26 --cpu cputype=host --cores $CORES --sockets $SOCKETS --memory $RAM --net0 virtio,tag=1000,bridge=$BRIDGE --net1 virtio,tag=666,firewall=1,bridge=$BRIDGE

    echo do_create_template finished
    sleep 5
}

function do_create_template_disk {
    # Create Disk for Template
    qm importdisk $VMTID $IMG $STORAGE

    # Attach Disk to Template
    qm set $VMTID --scsihw virtio-scsi-pci --virtio0 $STORAGE:$VMTID/vm-$VMTID-disk-0.raw

    echo do_create_template_disk finished
    sleep 5
}

function do_create_template_settings {
    # Set Template to use custom cloudinit user file
    # qm set $VMTID --cicustom user=nfs-ordnance:snippets/k8s-user-config.yaml --citype nocloud

    # Set Template to use CloudInit
    qm set $VMTID --sata0 nfs-ordnance:cloudinit

    # Set Template boot order so virtio0 is first
    qm set $VMTID --boot c --bootdisk virtio0

    # Set Template to use serial console
    qm set $VMTID --serial0 socket --vga serial0

    # Set Template to use qemu guest agent
    qm set $VMTID --agent enabled=1

    # Set Template to use DHCP by default
    qm set $VMTID --ipconfig0 ip=dhcp

    # Set Template to autostart
    qm set $VMTID --autostart=1

    # Set DNS nameservers
    qm set $VMTID --nameserver="172.16.0.10 172.16.0.11"

    # Set dns serachdomain
    qm set $VMTID --searchdomain="mgmt.mx"

    # Add ssh keys
    curl -s -o /tmp/keys https://gist.githubusercontent.com/djh00t/a44820a5ffd626a8fb679b9144c9e2e5/raw/c87333652708d5dad027c1821c91b030ebb032fc/authorized_keys.pub

    # Assign keys to root user
    qm set $VMTID --ciuser root --sshkey /tmp/keys

    # Assign keys to ord user
    qm set $VMTID --ciuser ord --sshkey /tmp/keys



    # Assign ordadmin ssh key to the template
    # qm set $VMTID --sshkey /root/.ssh/ordadmin.id_rsa.pub

    # Make into a Template
    sudo qm template $VMTID
}



function show_help {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -b, --bridge              Network bridge to use [$BRIDGE]"
    echo "  -c, --cores               Number of CPU cores [$CORES]"
    echo "  -h, --help                Display this help and exit"
    echo "  -i, --image               CloudInit Disk Image to use [$IMG]"
    echo "  -n, --name                VM Template Name [$NAME]"
    echo "  -r, --ram                 RAM amount in GB [$RAM]"
    echo "  -s, --sockets             Number of CPU sockets [$SOCKETS]"
    echo "  -S, --storage             Storage name to use [$STORAGE]"
    echo "  -v, --vmtid               VM Template ID Number [$VMTID]"
    echo
    echo "Example Image Build:"
    echo "  $0 -b vmbr1000 -c 2 -i /mnt/pve/nfs-ordnance/images/10003/jammy-server-cloudimg-amd64.img -n jammy-server -r 8 -s 1 -S $STORAGE -v 100"
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
        shift
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

# Set default values if not provided
if [ -z "$VMTID" ]; then
    VMTID=100
fi
if [ -z "$NAME" ]; then
    NAME="$VMTID-template"
fi
# Convert RAM to bytes if provided
if [ -z "$RAM" ]; then
    RAM=2048
else
    RAM=$(do_convert_gb_to_mb $RAM)
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
    STORAGE="nfs-ordnance"
fi
if [ -z "$IMG" ]; then
    IMG="/mnt/pve/nfs-ordnance/images/10003/jammy-server-cloudimg-amd64.img"
fi


do_create_template
do_create_template_disk
do_create_template_settings

