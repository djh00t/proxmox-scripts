# Proxmox Scripts
This is a set of shell scripts that I have used to drive proxmox

## Build an image
Run proxmox_image_builder.sh to build an image. The script will do the following when run with default options:
1. Look for a file called ./proxmox_tools.cfg which contains variable options. If it doesn't exist it will run with default options.
2. Lookup the latest LTS version of Ubuntu from the Ubuntu website.
3. Set the coreect URl for that version of Ubuntu.
4. Get the next highest VMID from the proxmox server.
5. Download the Ubuntu image from the Ubuntu website.
6. Add cloud-init scripts and configs to the image.
7. Run virt-customise against the image using ./cloud/k8s_mods.txt
8. Upload the image to the proxmox server.
9. Enable firewall and add base rules to the image.
