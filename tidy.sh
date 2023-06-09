#!/bin/bash
###
### Disk cleanup script for Debian
###
# Variables
# Set the number of days to keep logs
LOG_DAYS=7
# Get free disk space on root partition
DISK_SIZE=$(df -h / | tail -1 | awk '{ print $2 }' | sed 's/G//g')
DISK_SPACE_PRE=$(df -h / | tail -1 | awk '{ print $4 }' | sed 's/G//g')

# Clean up apt packages
echo "Clean up apt packages.."
apt autoremove --purge -y
echo "Done."
echo
echo "Clean up apt cache.."
apt clean -y
echo "Done."
echo
echo "Cleanup logging.."
journalctl --vacuum-time="$LOG_DAYS"d
echo "Done."
echo
echo "Cleanup kernels.."
# Cleanup Kernels
PVE_KERNELS=$( dpkg --list | awk '/ii/{ print $2}' | grep -E -i --color '^pve-kernel-([5-9]\.([0-9][0-2]?))(\.([0-9]{1,2}))?(-[0-9]-pve)?$' )
# If PVE_KERNELS is not empty, remove them
if [ -n "$PVE_KERNELS" ]; then
    echo "Removing PVE_KERNELS"
    for KERNEL in $PVE_KERNELS; do
        echo "Removing $KERNEL"
        apt remove -y "$KERNEL"
    done
    echo "Done."
    echo
fi

echo "Done."
echo
echo "Cleanup old snaps.."
# Cleanup snap apps if snap is installed
if [ -x "$(command -v snap)" ]; then
    echo "Removing old snap revisions"
    set -eu
    snap list --all | awk '/disabled/{print $1, $3}' |
        while read snapname revision; do
            snap remove "$snapname" --revision="$revision"
        done
fi
echo "Done."
echo
DISK_SPACE_POST=$(df -h / | tail -1 | awk '{ print $4 }' | sed 's/G//g')
# Calculate disk space freed up
DISK_SPACE_FREED=$(echo "$DISK_SPACE_POST - $DISK_SPACE_PRE" | bc)
echo "====================================================================="
echo " DISK SIZE:           $DISK_SIZE GB"
echo " STARTING DISK FREE:  $DISK_SPACE_PRE GB"
echo " FINAL DISK FREE:     $DISK_SPACE_POST GB"
echo " DISK SPACE FREED:    $DISK_SPACE_FREED GB"
echo "====================================================================="
echo

exit 0
