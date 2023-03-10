#!/bin/bash
###
### Proxmox K8S VM Build Script
###
QTY=$1
id=0
while [ $id -ne $QTY ]; do
	id=$(($id+1))
	./proxmox_vm_from_template.sh -b vmbr1000 -C 172.18.1.2$id/24 -c 4 -d 4 -g 172.18.1.1 -i 16$id -n dev-k8s0$id.gsw2 -r 16 -S 32 -s CEPH-GSW2-1 -t 10005 -v 1000
	./add_disk.sh -i 16$id -S 100
done
