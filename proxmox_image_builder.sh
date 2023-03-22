#!/bin/bash
###
### Download, Customise and register Latest Version Ubuntu Proxmox Template
###

# Import variables from ./proxmox_tools.cfg
source ./proxmox_tools.cfg

# If no APP is provided use default
APP=$1
if [ -z "$APP" ]; then
    APP=ubuntu
fi

# Find latest ubuntu LTS version number and release title
LATEST_LTS_TITLE_RELEASE=$(curl -s https://cloud-images.ubuntu.com/releases/streams/v1/com.ubuntu.cloud:released:download.json | jq -r '.products[] | select(.release_title|endswith("LTS")) | [.release_title, .release] | @tsv' | sort -nr | head -n1)

# Extract version number and release title
LATEST_LTS_NUMBER=$(echo $LATEST_LTS_TITLE_RELEASE | awk '{print $1}')
LATEST_LTS_NAME=$(echo $LATEST_LTS_TITLE_RELEASE | awk '{print $3}')

# Set URL for latest LTS image
URL="https://cloud-images.ubuntu.com/releases/${LATEST_LTS_NAME}/release/ubuntu-${LATEST_LTS_NUMBER}-server-cloudimg-amd64.img"

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

# Rename image and update $FILENAME
echo "Renaming image..."
echo
mv $FILENAME "$IMAGE_ID"-"$APP"-"$FILENAME"
FILENAME="$IMAGE_ID"-"$APP"-"$FILENAME"
echo "FILENAME: $FILENAME"
echo

# Add K8S cloud.cfg to template
echo "Download latest K8S cloud.cfg and scripts..."
echo
curl -s -o ./cloud/k8s_cloud.cfg https://gist.githubusercontent.com/fsg-gitbot/d4b80a55c744003bd5064d49db639bd0/raw/k8s-cloudinit.cfg
curl -s -o ./cloud/scripts/per-boot/01-mount-points.sh https://gist.githubusercontent.com/fsg-gitbot/e8729b10e585992fdff35d247319d775/raw/01-mountpoints.sh
curl -s -o ./cloud/scripts/per-boot/01-static-resolv-conf.sh https://gist.githubusercontent.com/fsg-gitbot/309947929f56abd075c644c000f01c8d/raw/01-static-resolv-conf.sh
curl -s -o ./cloud/scripts/per-boot/01-set-hostname.sh https://gist.githubusercontent.com/fsg-gitbot/a54170a504b02e9f10be032689434646/raw/01-set-hostname.sh
curl -s -o ./cloud/scripts/per-boot/01-set-mgmt-routes.sh https://gist.githubusercontent.com/fsg-gitbot/2eda62264e829345678662bc5477ef05/raw/01-set-mgmt-routes.sh
echo "Making scripts executable..."
chmod +x ./cloud/scripts/per-boot/*.sh

echo
echo "Adding K8S cloud-init customizations to image.."
echo
# Copy fresh cloud.cfg into current directory
cp cloud/k8s_cloud.cfg ./cloud.cfg
# Copy fresh cloud.cfg into snippets directory
cp cloud/k8s_cloud.cfg /mnt/pve/nfs-ordnance/snippets/cloud.cfg
# Push cloud-init customizations into image
virt-customize -a $FILENAME --commands-from-file ./cloud/k8s_mods.txt

echo
echo "Done"
echo

# Get image name for proxmox
IMAGE_NAME=$(echo $FILENAME | cut -d'.' -f1 | cut -d'-' -f1-5)

# Add image to proxmox
echo "Adding image to proxmox..."
echo
./proxmox_template_builder.sh -b vmbr1 -c 2 -i $FILENAME -n $IMAGE_NAME -r 8 -s 1 -S $STORAGE -v $IMAGE_ID
echo
echo "Done"
echo

# Make sure that firewall is enabled on VM
echo "Enabling firewall on VM..."
echo
pvesh set /nodes/`echo $HOSTNAME | cut -d'.' -f1`/qemu/$IMAGE_ID/firewall/options -enable 1
echo 
echo "Done"

# Cleanup
rm $FILENAME
# Cleanup cloud.cfg
rm cloud.cfg
# Cleanup cloud/scripts/per-boot
rm -rf ./cloud/scripts/per-boot/*.sh
echo
echo "VM Image Build Completed!"
echo