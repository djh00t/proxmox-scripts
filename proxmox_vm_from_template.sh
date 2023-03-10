#!/bin/bash
###
### Build VM from Proxmox Template
###

POOL=K8S

function do_clone_linked_vm {
    # Check to make sure required variables exist
    if [ "$VMTID" == "" ] || [ "$VMID" == "" ] || [ "$NAME" == "" ]; then
        echo "ERROR: Missing required variables"
        echo "VMTID: $VMTID"
        echo "VMID: $VMID"
        echo "NAME: $NAME"
        exit 1
    fi
    # Clone VM from Template
    qm clone $VMTID $VMID --name $NAME --pool $POOL
}

function do_clone_full_vm {
    # Check to make sure required variables exist
    if [ "$VMTID" == "" ] || [ "$VMID" == "" ] || [ "$NAME" == "" ] || [ "$STORAGE" == "" ]; then
        echo "ERROR: Missing required variables"
        echo "VMTID: $VMTID"
        echo "VMID: $VMID"
        echo "NAME: $NAME"
        echo "STORAGE: $STORAGE"
        exit 1
    fi
    # Clone VM from Template
    qm clone $VMTID $VMID --name $NAME --full --storage $STORAGE --pool $POOL
}

function do_assign_ip {
    # Check to make sure required variables exist
    if [ "$VMID" == "" ] || [ "$CIDR" == "" ] || [ "$GW" == "" ]; then
        echo "ERROR: Missing required variables"
        echo "VMID: $VMID"
        echo "CIDR: $CIDR"
        echo "GW: $GW"
        exit 1
    fi

    # Assign IP to VM
    qm set $VMID --ipconfig0 ip=$CIDR,gw=$GW
}

function do_assign_ip2 {
    # Check to make sure required variables exist
    if [ "$VMID" == "" ] || [ "$CIDR2" == "" ] || [ "$GW2" == "" ]; then
        echo "ERROR: Missing required variables"
        echo "VMID: $VMID"
        echo "CIDR2: $CIDR2"
        echo "GW2: $GW2"
        exit 1
    fi

    # Assign IP to VM
    qm set $VMID --ipconfig1 ip=$CIDR2,gw=$GW2
}


function show_help {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -b, --bridge              Network bridge to use"
    echo "  -C, --cidr                IP Address in CIDR format to assign to VM"
    echo "  -c, --cores               Number of CPU cores to provision"
    echo "  -d --sockets              Number of CPU sockets to provision"
    echo "  -f, --full-clone          Perform a full clone (Default: is a linked clone)"
    echo "  -g, --gateway             Gateway IP Address to assign to VM"
    echo "  -h, --help                Display this help and exit"
    echo "  -i, --id                  ID number to assign to VM"
    echo "  -n, --name                VM Name"
    echo "  -r, --ram                 RAM amount in GB"
    echo "  -S, --storage-size        Storage size in GB"
    echo "  -s, --storage-name        Storage name to use"
    echo "  -t, --template            Template ID to clone from"
    echo "  -v, --vlan                VLAN ID to assign to VM"
    echo
    echo "Example Image Build:"
    echo "  $0 -b vmbr1000 -C 172.10.10.10/24 -c 4 -d 4 -f -g 172.10.10.1 -i 100 -n jammy-server -r 8 -S 32 -s $STORAGE -t 100"
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
    -b2 | --bridge2)
        shift
        BRIDGE2=$1
        ;;
    -C | --cidr)
        shift
        CIDR=$1
        ;;
    -C2 | --cidr2)
        shift
        CIDR2=$1
        ;;
    -c | --cores)
        shift
        CORES=$1
        ;;
    -d | --sockets)
        shift
        SOCKETS=$1
        ;;
    -f | --full-clone)
        CLONE=full
        ;;
    -g | --gateway)
        shift
        GW=$1
        ;;
    -g2 | --gateway2)
        shift
        GW2=$1
        ;;
    -h | --help)
        shift
        show_help
        ;;
    -i | --id)
        shift
        VMID=$1
        ;;
    -n | --name)
        shift
        NAME=$1
        ;;
    -r | --ram)
        shift
        RAM=$1
        ;;
    -S | --storage-size)
        shift
        STORAGE_SIZE=$1
        ;;
    -s | --storage-name)
        shift
        STORAGE=$1
        ;;
    -t | --template)
        shift
        VMTID=$1
        ;;
    -v | --vlan)
        shift
        VLAN=$1
        ;;
    -v2 | --vlan2)
        shift
        VLAN2=$1
        ;;
    *)
        show_help
        exit 1
        ;;
    esac
    shift
done

# If full clone is selected, perform a full clone otherwise do a linked clone
if [ "$CLONE" == "full" ]; then
    do_clone_full_vm
else
    do_clone_linked_vm
fi

# If IP and Gateway are provided, assign IP to VM
if [ "$CIDR" != "" ] && [ "$GW" != "" ]; then
    do_assign_ip
fi

# If IP and Gateway are provided, assign IP to VM
if [ "$CIDR" != "" ] && [ "$GW" != "" ] && [ "$CIDR2" != "" ] && [ "$GW2" != "" ]; then
    do_assign_ip2
fi

# If CPU cores are provided, assign CPU cores to VM
if [ "$CORES" != "" ]; then
    qm set $VMID --cores $CORES
fi

# If CPU sockets are provided, assign CPU sockets to VM
if [ "$SOCKETS" != "" ]; then
    qm set $VMID --sockets $SOCKETS
fi

# If RAM is provided, assign RAM to VM
if [ "$RAM" != "" ]; then
    # Convert GB to MB
    RAM=$((RAM * 1024 ))
    qm set $VMID --memory $RAM
fi

# If Storage is provided, assign Storage to VM
if [ "$CLONE" == "full" ] && [ "$STORAGE" != "" ]; then
    qm set $VMID --scsihw virtio-scsi-pci --virtio0 $STORAGE:vm-$VMID-disk-0
fi

# If Storage size is provided, assign Storage size to VM
if [ "$STORAGE_SIZE" != "" ]; then
    # Set Base Size
    BASESIZE=2252
    # Convert GB to MB
    STORAGE_SIZE=$((STORAGE_SIZE * 1024))
    # Deduct Base Size from Storage Size
    STORAGE_SIZE=$((STORAGE_SIZE - BASESIZE))
    # Resize Storage
    qm resize $VMID virtio0 +$STORAGE_SIZE"M"
fi

# If Bridge and no VLAN is provided, assign Bridge to VM
if [ "$BRIDGE" != "" ] && [ "$VLAN" == "" ]; then
    qm set $VMID --net0 virtio,bridge=$BRIDGE
fi

# If no Bridge and VLAN is provided, assign VLAN to VM
if [ "$BRIDGE" == "" ] && [ "$VLAN" != "" ]; then
    qm set $VMID --net0 virtio,tag=$VLAN
fi

# If Bridge and VLAN is provided, assign Bridge and VLAN to VM
if [ "$BRIDGE" != "" ] && [ "$VLAN" != "" ]; then
    qm set $VMID --net0 virtio,bridge=$BRIDGE,tag=$VLAN
fi

# If Bridge2 and no VLAN2 is provided, assign Bridge2 to VM
if [ "$BRIDGE2" != "" ] && [ "$VLAN2" == "" ]; then
    qm set $VMID --net1 virtio,bridge=$BRIDGE2
fi

# If no Bridge2 and VLAN2 is provided, assign VLAN2 to VM
if [ "$BRIDGE2" == "" ] && [ "$VLAN2" != "" ]; then
    qm set $VMID --net1 virtio,tag=$VLAN2
fi

# If Bridge2 and VLAN2 is provided, assign Bridge2 and VLAN2 to VM
if [ "$BRIDGE2" != "" ] && [ "$VLAN2" != "" ]; then
    qm set $VMID --net1 virtio,bridge=$BRIDGE2,tag=$VLAN2
fi

# Set notes on VM
qm set $VMID --description "=======================================================
 AUTOBUILT VM USING TEMPLATE $VMTID
=======================================================
VMID: $VMID
NAME: $NAME 
Created/Updated by $0 on $(date)"


