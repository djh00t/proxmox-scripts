#!/bin/bash
###
### Proxmox K8S VM Build Script
###
PRIVATE=172.18.100
PUBLIC=103.197.233
MASTER=2
MASTER2=193
SLAVES=(6 10 14 18 22)
SLAVES2=(195 197 201 203 205)
STORAGE=nfs-ordnance
COUNT=$1
HOSTID=1
# Build Master VM
echo "Building k8s01.gsw2-dev.mgmt.mx.."
echo
# echo -e "./proxmox_vm_from_template.sh -b vmbr1 -C $PRIVATE.$MASTER/30 -g $PRIVATE.`expr $MASTER - 1` -b2 vmbr1 -C2 $PUBLIC.$MASTER2/31 -g2 $PUBLIC.`expr $MASTER2 - 1` -c 4 -d 4 -i 16$COUNT -n k8s$COUNT.gsw2-dev.mgmt.mx -r 16 -S 32 -s $STORAGE -t 10006 -v 1000"
./proxmox_vm_from_template.sh -f -b vmbr1 -C $PRIVATE.$MASTER/30 -g $PRIVATE.`expr $MASTER - 1` -b2 vmbr1 -C2 $PUBLIC.$MASTER2/31 -g2 $PUBLIC.`expr $MASTER2 - 1` -c 4 -d 4 -i 161 -n k8s01.gsw2-dev.mgmt.mx -r 16 -S 32 -s $STORAGE -t 10006 -v 1000
./add_disk.sh -v 161 -s 100
# EXPORT1="/etc/bash.bashrc:export IP_MASTER=$PRIVATE.$MASTER"
echo virt-customize -a /mnt/pve/$STORAGE/images/16$COUNT/vm-16$COUNT-disk-0.raw --append-line "/etc/bash.bashrc:export IP_MASTER=$PRIVATE.$MASTER" --append-line '/etc/bash.bashrc:# EOF'
virt-customize -a /mnt/pve/$STORAGE/images/16$COUNT/vm-16$COUNT-disk-0.raw --append-line "/etc/bash.bashrc:export IP_MASTER=$PRIVATE.$MASTER" --append-line '/etc/bash.bashrc:# EOF'
#qm start 161
COUNT=$(($COUNT-1))
HOSTID=$(($HOSTID+1))
echo
echo
echo
echo
echo "QTY: $QTY"
echo "COUNT: $COUNT"

INDEX=0
# Build Slave VMs
while [ $COUNT -ne 0 ]; do
    # Iterate over $SLAVES array
    #for SLAVE in "${SLAVES[@]}"; do
        echo
        echo "Building k8s0$HOSTID.gsw2-dev.mgmt.mx.."
        echo
        echo IP=$PRIVATE.$SLAVE
        echo GW=$PRIVATE.`expr $SLAVE - 1`
        echo IP2=$PUBLIC."${SLAVES2[$INDEX]}"
        echo GW2=$PUBLIC.`expr ${SLAVES2[$INDEX]} - 1`

        IP=$PRIVATE.$SLAVE
        GW=$PRIVATE.`expr $SLAVE - 1`
        IP2=$PUBLIC."${SLAVES2[$INDEX]}"
        GW2=$PUBLIC.`expr ${SLAVES2[$INDEX]} - 1`

        # Build VM
        echo -e "./proxmox_vm_from_template.sh -b vmbr1 -C $IP/30 -g $GW -b2 vmbr1 -C2 $IP2/31 -g2 $GW2 -i 16$COUNT -n k8s0$COUNT.gsw2-dev.mgmt.mx -c 4 -d 4 -r 16 -S 32 -s $STORAGE -t 10005 -v 1000"
        ./proxmox_vm_from_template.sh -b vmbr1 -C $IP/30 -g $GW -b2 vmbr1 -C2 $IP2/31 -g2 $GW2 -i 16$COUNT -n k8s0$COUNT.gsw2-dev.mgmt.mx -c 4 -d 4 -r 16 -S 32 -s $STORAGE -t 10005 -v 1000
        ./add_disk.sh -v 16$COUNT -s 100
        virt-customize -a /mnt/pve/$STORAGE/images/16$COUNT/vm-16$COUNT-disk-0.raw --append-line "/etc/bash.bashrc:export IP_MASTER=$PRIVATE.$MASTER" --append-line "/etc/bash.bashrc:export IP_SLAVE=$IP"

        # Decrement counter
        COUNT=$(($COUNT-1))
        # Increment host ID
        HOSTID=$(($HOSTID+1))
        # Increment index
        INDEX=$(($INDEX+1))
    # done
done
