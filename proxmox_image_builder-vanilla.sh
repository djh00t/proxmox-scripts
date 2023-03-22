#!/bin/bash
###
### Download, Customise and register Latest Version Ubuntu Proxmox Template
###

# Import variables from ./proxmox_tools.cfg
source ./proxmox_tools.cfg

# Set APP to RAW
APP="RAW"
CI_URL="https://gist.githubusercontent.com/fsg-gitbot/cc6f8ea71cd7387018928f30e84fd8ec/raw/vanilla-cloud.cfg"

# Get all ubuntu release numbers and titles
RELEASE_NUMBER_TITLE=$(curl -s https://cloud-images.ubuntu.com/releases/streams/v1/com.ubuntu.cloud:released:download.json | jq -r '.products[] | [.release_title, .release] | @tsv' | sort -nr | uniq)

# Find latest ubuntu LTS version number and release title
LATEST_LTS=$(echo "$RELEASE_NUMBER_TITLE" | grep "LTS" | head -n1)

# If $UBUNTU_RELEASE_NUMBER is provided make sure it is a valid release number
if [ -n "$UBUNTU_RELEASE_NUMBER" ]; then
    # Check if $UBUNTU_RELEASE_NUMBER is a valid release number
    if [[ $(echo "$RELEASE_NUMBER_TITLE" | grep "$UBUNTU_RELEASE_NUMBER") ]]; then
        # If $UBUNTU_RELEASE_NUMBER is a valid release number use it
        RELEASE_NUMBER=$UBUNTU_RELEASE_NUMBER
        echo "Using provided release number: $RELEASE_NUMBER"
        echo
    else
        # If $UBUNTU_RELEASE_NUMBER is not a valid release number use latest LTS
        RELEASE_NUMBER=$(echo $LATEST_LTS | awk '{print $1}')
        echo "Provided release number is not valid."
        echo "Using latest LTS release number: $RELEASE_NUMBER"
        echo
    fi
else
    # If $UBUNTU_RELEASE_NUMBER is not provided use latest LTS
    RELEASE_NUMBER=$(echo $LATEST_LTS | awk '{print $1}')
    echo "Using latest LTS release number: $RELEASE_NUMBER"
    echo
fi

# Lookup release name for $RELEASE_NUMBER
echo "Looking up release name for $RELEASE_NUMBER..."
RELEASE_NAME=$(echo "$RELEASE_NUMBER_TITLE" | grep $RELEASE_NUMBER | awk '{print $NF}')
echo
echo "Release Name: $RELEASE_NAME"

# Set URL for latest LTS image
URL="https://cloud-images.ubuntu.com/releases/${RELEASE_NAME}/release/ubuntu-${RELEASE_NUMBER}-server-cloudimg-amd64.img"
echo "URL: $URL"
echo

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

# Rename image and update $FILENAME if $APP is provided
echo "Renaming image..."
echo
if [ -n "$APP" ]; then
    mv $FILENAME "$IMAGE_ID"-"$APP"-"$FILENAME"
    FILENAME="$IMAGE_ID"-"$APP"-"$FILENAME"
else
    mv $FILENAME "$IMAGE_ID"-"$FILENAME"
    FILENAME="$IMAGE_ID"-"$FILENAME"
fi

echo "FILENAME: $FILENAME"
echo


#### Add K8S cloud.cfg to template
echo "Download latest K8S cloud.cfg and scripts..."
echo
# If $CI_URL is provided, download it
if [ -n "$CI_URL" ]; then
    curl -s -o ./cloud/cloud.cfg $CI_URL
fi

#### If $CI_SCRIPT_STORAGE is provided, download it
###if [ -n "$CI_SCRIPT_STORAGE" ]; then
###    curl -s -o ./cloud/scripts/per-boot/01-storage.sh $CI_SCRIPT_STORAGE
###fi
###
#### If $CI_SCRIPT_HOSTNAME is provided, download it
###if [ -n "$CI_SCRIPT_HOSTNAME" ]; then
###    curl -s -o ./cloud/scripts/per-boot/02-hostname.sh $CI_SCRIPT_HOSTNAME
###fi
###
#### If $CI_SCRIPT_RESOLVCONF is provided, download it
###if [ -n "$CI_SCRIPT_RESOLVCONF" ]; then
###    curl -s -o ./cloud/scripts/per-boot/03-resolvconf.sh $CI_SCRIPT_RESOLVCONF
###fi
###
#### If $CI_SCRIPT_ROUTE is provided, download it
###if [ -n "$CI_SCRIPT_ROUTE" ]; then
###    curl -s -o ./cloud/scripts/per-boot/04-route.sh $CI_SCRIPT_ROUTE
###fi
###
###echo "Making cloud scripts executable..."
###chmod +x ./cloud/scripts/per-boot/*.sh
###
###echo
###echo "Adding K8S cloud-init customizations to image.."
###echo
#### Push cloud-init customizations into image
###virt-customize -a $FILENAME --commands-from-file ./cloud/k8s_mods.txt
virt-customize -a $FILENAME install qemu-guest-agent,net-tools,plocate,htop,mtr-tiny,iftop,iotop,tcpdump

# Copy in the cloud-init configs
virt-customize -a $FILENAME copy-in ./cloud/cloud.cfg:/etc/cloud/

echo
echo "Done"
echo

# Get image name for proxmox
IMAGE_NAME=$(echo $FILENAME | cut -d'.' -f1-2)

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
rm cloud/cloud.cfg
# Cleanup cloud/scripts/per-boot
rm -rf ./cloud/scripts/per-boot/*.sh
echo
echo "VM Image Build Completed!"
echo