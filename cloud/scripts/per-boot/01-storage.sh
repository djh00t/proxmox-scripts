#!/bin/bash
###
### Script to find all disks that are not already formatted or mounted
###
# Create /etc/cloud/scripts/per-boot/01-storage.sh

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
debug "#                     STORAGE BOOT SCRIPT                              #"
debug "########################################################################"
# Make sure that /etc/cloud/scipts/per-boot exists
mkdir -p /etc/cloud/scripts/per-boot

# Create array of disks to ignore
IGNORE=(sda sdb vda vdb xvda floppy loop sr cdrom dvdrom fd)

# Find all disks except those in the ignore array
DISKS=$(lsblk -d -n -o NAME | grep -v -E "$(
    IFS="|"
    echo "${IGNORE[*]}"
)")

function do_get_disk_size() {
    #Set DISK variable
    DISK=$1
    # Get size of $1 disk
    SIZE=$(lsblk -d -n -o SIZE /dev/$DISK)

    # Convert size to GB if it is not already
    if [[ $SIZE == *G ]]; then
        SIZE=${SIZE%?}
    else
        SIZE=$(echo "$SIZE/1024/1024/1024" | bc -l)
    fi

    # Return the size of the disk in Gigabytes
    echo $SIZE
}

function do_get_disk_label() {
    #Set DISK variable
    DISK=$1
    # Get label of $1 disk
    LABEL=$(lsblk -d -n -o LABEL /dev/$DISK)

    # Return the label of the disk
    echo $LABEL
}

function do_get_disk_format() {
    #Set DISK variable
    DISK=$1
    # Get format of $1 disk
    FORMAT=$(lsblk -d -n -o FSTYPE /dev/$DISK)

    # Return the format of the disk
    echo $FORMAT
}

function next_mountid(){
    # Look at lsblk disk labels and add any labels that start with mount into the LABELS array
    LABELS=()
    MOUNTID=()
    while read -r line; do
        LABELS+=("$line")
    done < <(lsblk -d -n -o LABEL | grep -E "^mount[1-9]")

    # If LABELS is empty set ID to 1
    if [ ${#LABELS[@]} -eq 0 ]; then
        ID=1
    fi

    # If LABELS is not empty remove the mount prefix from the labels
    if [ ${#LABELS[@]} -gt 0 ]; then
        for i in "${!LABELS[@]}"; do
            LABELS[$i]="${LABELS[$i]#mount}"
        done
    fi

    # Find the highest number in the LABELS array and set it as $HIGHEST
    HIGHEST=0
    for i in "${LABELS[@]}"; do
        if [ "$i" -gt "$HIGHEST" ]; then
            HIGHEST=$i
        fi
    done

    # Add 1 to $HIGHEST and set it as $ID
    export MOUNTID=$(($HIGHEST + 1))
    echo $MOUNTID
}

function do_format_disk() {
    # Set the disk to format
    DISK=$1
    MOUNTID=$2
    # Format the disk
    echo -e "| STORAGE\tINFO\t\tFormatting:\t\t$DISK\t$(do_get_disk_size $DISK)G\t$(do_get_disk_format $DISK)\t$(do_get_disk_label $DISK)"
    ERR=$(mkfs.xfs -q -L mount$MOUNTID /dev/$DISK;echo $?)
    if [ $ERR -eq 0 ]; then
        echo -e "| STORAGE\tOK\t\tFormatted:\t\t$DISK\t$(do_get_disk_size $DISK)G\t$(do_get_disk_format $DISK)\t$(do_get_disk_label $DISK)"
    else
        echo -e "| STORAGE\tFAIL\t\tDisk had a format error:\t$DISK"
        echo -e " --------------------------------------------------------------------------------------------"
        # exit 1
    fi
    
}

function do_wipe_disk() {
    # Set the disk to wipe
    DISK=$1
    # Wipe the disk
    echo -e "| STORAGE\tINFO\t\tWiping disk:\t$DISK\t\t$(do_get_disk_size $DISK)G\t$(do_get_disk_format $DISK)"
    # Unmount /dev/$DISK if it is mounted
    if mount | grep -q /dev/$DISK; then
        umount /dev/$DISK
    fi
    # ERR - Wipe Filesytem
    ERR=$(sgdisk -Z /dev/$DISK > /dev/null 2>&1;echo $?)
    if [ $ERR -eq 0 ]; then
        echo -e "| STORAGE\tOK\t\tDisk wiped:\t$DISK\t\t$(do_get_disk_size $DISK)G\t$(do_get_disk_format $DISK)"
    else
        echo -e "| STORAGE\tFAIL\tDisk had a wipe error:\t$DISK\t\t$(do_get_disk_size $DISK)G\t$(do_get_disk_format $DISK)"
        echo -e " --------------------------------------------------------------------------------------------"
        # exit 1
    fi
}



function do_create_mountpoint(){
            # Make sure that the mount point exists in /data, if not create it
        if [ ! -d "/data/$MOUNTPOINT" ]; then
            ERR=$(mkdir -p /data/$MOUNTPOINT;echo $?)
            if [ $ERR -eq 0 ]; then
                echo -e "| STORAGE\tOK\t\tMount point created:\t/data/$MOUNTPOINT"
            else
                echo -e "| STORAGE\tFAIL\t\tMount point had a creation error:\t/data/$MOUNTPOINT"
                echo -e " --------------------------------------------------------------------------------------------"
                exit 1
            fi
        fi
}

function do_mount_disk(){
    DISK=$1
    MOUNTID=$2
    MOUNTPOINT="mount$MOUNTID"
    # Create /data/$MOUNTID if it doesn't exist
    do_create_mountpoint $MOUNTPOINT

    # Add /dev/$DISK to /etc/fstab if it doesn't exist
    if ! grep -q "/dev/$DISK" /etc/fstab; then
        debug -e "| STORAGE\tINFO\t\tAdding /data/$MOUNTPOINT to /etc/fstab"
        echo -e "/dev/$DISK /data/mount$MOUNTID xfs defaults 0 0" >> /etc/fstab
        ERR=$(echo $?)
        if [ $ERR -eq 0 ]; then
            echo -e "| STORAGE\tOK\t\tAdded to fstab:\t\t$DISK\t$(do_get_disk_size $DISK)G\t$(do_get_disk_format $DISK)"
        else
            echo -e "| STORAGE\tFAIL\t\tAdd to fstab:\t\t$DISK\t$(do_get_disk_size $DISK)G\t$(do_get_disk_format $DISK)"
            echo -e " --------------------------------------------------------------------------------------------"
            exit 1
        fi
    fi

    # Mount the disk
    echo -e "| STORAGE\tINFO\t\tMounting disk:\t\t$DISK\t$(do_get_disk_size $DISK)G\t$(do_get_disk_format $DISK)"
    ERR=$(mount /dev/$DISK /data/$MOUNTPOINT;echo $?)
    if [ $ERR -eq 0 ]; then
        echo -e "| STORAGE\tOK\t\tDisk mounted:\t\t$DISK\t$(do_get_disk_size $DISK)G\t$(do_get_disk_format $DISK)"
    else
        echo -e "| STORAGE\tFAIL\t\tDisk had a mount error:\t\t$DISK\t$(do_get_disk_size $DISK)G\t$(do_get_disk_format $DISK)"
        echo -e " --------------------------------------------------------------------------------------------"
        exit 1
    fi
}

# Print the disks found
echo -e " --------------------------------------------------------------------------------------------"
for disk in ${DISKS[@]}; do
    echo -e "| STORAGE\tINFO\t\tDisk found:\t\t$disk\t$(do_get_disk_size $disk)G\t$(do_get_disk_format $disk)"
done

# Loop through the disks, if they aren't formatted remove all partitioning and format them using xfs
for DISK in ${DISKS[@]}; do
    # Get the filesystem type of the disk
    FORMAT=$(lsblk -d -n -o FSTYPE /dev/$DISK)

    # Get the next available mountid
    export MOUNTID=0
    export MOUNTID=$(next_mountid)
    # If $FORMAT is empty, the disk is not formatted so format it with xfs
    if [ -z "$FORMAT" ]; then
        # Announce that the disk is not formatted
        debug -e "| STORAGE\tINFO\t\t$DISK is not formatted, wiping and formatting with xfs"

        # Format the disk
        do_format_disk $DISK $MOUNTID

        # Mount the disk
        do_mount_disk $DISK $MOUNTID
    else
        # If $FORMAT is set to xfs, the disk is formatted with xfs so set DISK_FMT to "1"
        if [ "$FORMAT" == "xfs" ]; then
            # Announce that the disk is formatted with xfs
            echo -e "| STORAGE\tSKIP\t\tPre-formatted (xfs):\t$DISK\t\t$(do_get_disk_size $DISK)G\t$(do_get_disk_format $DISK)"

            # Mount the disk
            do_mount_disk $DISK $MOUNTID
        else
            # Announce that the disk is formatted with something other than xfs then erase the disk and format it with xfs
            echo -e "| STORAGE\tINFO\t\t$DISK is formatted with $FORMAT, erasing and formatting with xfs"

            # Format the disk
            do_format_disk $DISK $MOUNTID

            # Mount the disk
            do_mount_disk $DISK $MOUNTID
        fi
    fi
done


echo -e " --------------------------------------------------------------------------------------------"
exit 0

#EOF