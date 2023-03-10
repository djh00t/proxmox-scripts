#!/bin/bash
###
### Download and register Proxmox Template
###
URL=$1

# If no URL is provided use default
if [ -z "$URL" ]; then
    URL=https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
fi

STORAGE=nfs-ordnance

# Get highest vm id from proxmox
HIGHEST_ID=$(qm list | tail -n +2 | awk '{print $1}' | sort -n | tail -n 1)

# Set new VM ID
IMAGE_ID=$((HIGHEST_ID + 1))

# Tell user the next VM ID
echo
echo "IMAGE_ID: $IMAGE_ID"
echo

# Download image
wget $URL

# Get filename
FILENAME=$(basename $URL)

# Add qemu-guest-agent and net-tools to template
virt-customize -a $FILENAME --install qemu-guest-agent,net-tools

# Add K8S cloud.cfg to template
cp cloud/k8s_cloud.cfg ./cloud.cfg
virt-customize -a $FILENAME --copy-in ./cloud.cfg:/etc/cloud/
rm cloud.cfg

# Rename image and update $FILENAME
mv $FILENAME "$IMAGE_ID"-"$FILENAME"
FILENAME="$IMAGE_ID"-"$FILENAME"

# Get image name for proxmox
IMAGE_NAME=$(echo $FILENAME | cut -d'.' -f1 | cut -d'-' -f1-4)

# Add image to proxmox
./proxmox_template_builder.sh -b vmbr1 -c 2 -i $FILENAME -n $IMAGE_NAME -r 8 -s 1 -S $STORAGE -v $IMAGE_ID

# Make sure that firewall is enabled on VM
pvesh set /nodes/`echo $HOSTNAME | cut -d'.' -f1`/qemu/$IMAGE_ID/firewall/options -enable 1
