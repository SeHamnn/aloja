#!/bin/bash

#load init and common functions
type="cluster"
source include/include_deploy.sh

#Sequential Node deploy
for vm_id in $(seq -f "%02g" 0 "$numberOfNodes") ; do #pad the sequence with 0s

  vm_name="${clusterName}-${vm_id}"
  vm_ssh_port="2${clusterID}${vm_id}"

  logger "Atempting to shutdown node $vm_name..."
  node_stop "$vm_name"

done

logger "All done, took $(getElapsedTime starttime) seconds."