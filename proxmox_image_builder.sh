#!/bin/bash
###
### Download, Customise and register Latest Version Ubuntu Proxmox Template
###

# Import variables from ./proxmox_tools.cfg
source ./proxmox_tools.cfg

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

# Add base firewall rules to VM
function add_firewall_rules() {
  # Add firewall rules to VM
  HOST=$(hostname -s)
  VM=$IMAGE_ID
  AUTH_HEADER=$(echo "Authorization: PVEAPIToken=$PM_API_TOKEN_ID=$PM_API_TOKEN_SECRET")
  RULE_1=$(echo curl -s -X POST -k -H \'$AUTH_HEADER\' -H \'Content-Type: application/json\' -d \'{\"action\": \"admin_allow\",\"node\": \"$HOST\",\"vmid\": \"$VM\",\"enable\": 1,\"pos\": 0,\"type\": \"group\",\"comment\": \"Allow admins to access VM $VM\"}\' $PM_API_URL/nodes/$HOST/qemu/$VM/firewall/rules/)
  RULE_2=$(echo curl -s -X POST -k -H \'$AUTH_HEADER\' -H \'Content-Type: application/json\' -d \'{\"action\": \"k8s_internet\",\"node\": \"$HOST\",\"vmid\": \"$VM\",\"enable\": 1,\"pos\": 1,\"type\": \"group\",\"comment\": \"Standard K8S Internet Ruleset\"}\' $PM_API_URL/nodes/$HOST/qemu/$VM/firewall/rules/)
  # Push payloads at API
    A=$(eval $RULE_1)
    B=$(eval $RULE_2)

    ARR=($A $B)
    for num in ${ARR[@]};do
    # Check if API call was successful
    if [[ $(echo $num | jq -r '.data') == "null" ]]; then
        echo "API call successful"
    else
        echo "API call failed"
        echo $num
    fi
  done
}

# Get highest vm id from proxmox
HIGHEST_ID=$(qm list | tail -n +2 | awk '{print $1}' | sort -n | tail -n 1)

# Set new VM ID
IMAGE_ID=$((HIGHEST_ID + 1))

# Tell user the next VM ID
echo
echo "IMAGE_ID: $IMAGE_ID"
echo

# Get filename
FILENAME=$(basename $URL)

# Download image if $FILENAME does not already exist in current directory
if [ ! -f "$FILENAME" ]; then
    echo "Downloading image..."
    echo
    wget $URL
else
    echo "Image already exists in current directory"
    echo
fi



# Rename image and update $FILENAME if $APP is provided
echo "Renaming image..."
echo
if [ -n "$APP" ]; then
    cp $FILENAME "$IMAGE_ID"-"$APP"-"$FILENAME"
    FILENAME="$IMAGE_ID"-"$APP"-"$FILENAME"
else
    cp $FILENAME "$IMAGE_ID"-"$FILENAME"
    FILENAME="$IMAGE_ID"-"$FILENAME"
fi

echo "FILENAME: $FILENAME"
echo


# Add K8S cloud.cfg to template
echo "Download latest K8S cloud.cfg and scripts..."
echo
# If $CI_URL is provided, download it
if [ -n "$CI_URL" ]; then
    curl -s -o ./cloud/cloud.cfg $CI_URL
fi

# If $CI_SCRIPT_STORAGE is provided, download it
if [ -n "$CI_SCRIPT_STORAGE" ]; then
    curl -s -o ./cloud/scripts/per-boot/01-storage.sh $CI_SCRIPT_STORAGE
fi

# If $CI_SCRIPT_HOSTNAME is provided, download it
if [ -n "$CI_SCRIPT_HOSTNAME" ]; then
    curl -s -o ./cloud/scripts/per-boot/02-hostname.sh $CI_SCRIPT_HOSTNAME
fi

# If $CI_SCRIPT_RESOLVCONF is provided, download it
if [ -n "$CI_SCRIPT_RESOLVCONF" ]; then
    curl -s -o ./cloud/scripts/per-boot/03-resolvconf.sh $CI_SCRIPT_RESOLVCONF
fi

# If $CI_SCRIPT_ROUTE is provided, download it
if [ -n "$CI_SCRIPT_ROUTE" ]; then
    curl -s -o ./cloud/scripts/per-boot/04-route.sh $CI_SCRIPT_ROUTE
fi

echo "Making cloud scripts executable..."
chmod +x ./cloud/scripts/per-boot/*.sh
echo "Giving root:cloud ownership of cloud scripts..."
chown -R root:999 ./cloud

echo
echo "Adding K8S cloud-init customizations to image.."
echo
# Push cloud-init customizations into image
virt-customize -a $FILENAME --commands-from-file ./cloud/k8s_mods.txt

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

# Add base firewall rules to vm
add_firewall_rules

# Cleanup
rm $FILENAME
# Cleanup cloud.cfg
rm cloud/cloud.cfg
# Cleanup cloud/scripts/per-boot
rm -rf ./cloud/scripts/per-boot/*.sh
echo
echo "VM Image Build Completed!"
echo
