#!/bin/bash
###
### Proxmox K8S VM Build Script
###
QTY=$1
id=0
while [ $id -ne $QTY ]; do
	id=$(($id+1))
	qm stop 16$id
	qm destroy 16$id --destroy-unreferenced-disks=1 --purge=1 --skiplock=1
done
