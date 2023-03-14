#!/bin/bash
###
### Download and register Proxmox Template
###
# If no APP is provided use default
APP=$1
if [ -z "$APP" ]; then
    APP=ubuntu
fi


URL=$2
# Work out latest Ubuntu LTS version name and number
if [ "$APP" == "ubuntu-lts" ]; then
    URL=https://cloud-images.ubuntu.com/$(curl -s https://cloud-images.ubuntu.com/releases/streams/v1/com.ubuntu.cloud:released:download.json | jq -r '.index."com.ubuntu.cloud:released:aws".current | .version + "/" + .products."server".architectures."amd64".formats."disk1.img".subarchitecture.default' | sed 's/ //g')/disk1.img
fi


# Work out latest Ubuntu LTS image
if [ "$APP" == "ubuntu" ]; then
    URL=https://cloud-images.ubuntu.com/$(curl -s https://cloud-images.ubuntu.com/releases/streams/v1/com.ubuntu.cloud:released:download.json | jq -r '.index."com.ubuntu.cloud:released:aws".current | .version + "/" + .products."server".architectures."amd64".formats."disk1.img".subarchitecture.default' | sed 's/ //g')/disk1.img
fi


# If no URL is provided use default image
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

# Rename image and update $FILENAME
echo "Renaming image..."
echo
mv $FILENAME "$IMAGE_ID"-"$APP"-"$FILENAME"
FILENAME="$IMAGE_ID"-"$APP"-"$FILENAME"
echo "FILENAME: $FILENAME"
echo

# Add qemu-guest-agent and net-tools to template
echo "Installing qemu-guest-agent and net-tools into image..."
echo
virt-customize -a $FILENAME --install qemu-guest-agent,net-tools
echo
echo "Done"
echo

# Add K8S cloud.cfg to template
echo "Adding K8S cloud.cfg to image"
echo
cp cloud/k8s_cloud.cfg ./cloud.cfg
virt-customize -a $FILENAME --copy-in ./cloud.cfg:/etc/cloud/
rm cloud.cfg
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
echo
echo "VM Image Build Compelted"
echo