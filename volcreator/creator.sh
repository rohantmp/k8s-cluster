#! /bin/bash

function usage() {
        echo "Usage: $0 <server1:server2:...> <volume> <base_path> <start> <end>"
        echo "    0 <= start <= end <= 65535"
}

function tohexpath() {
        local -i l1=$1/256
        local -i l2=$1%256
        printf '%02x/%02x' $l1 $l2
}

function mkPvTemplate() {
        local servers=$1
        local volume=$2
        local subdir=$3
        local capacity=$4

        local pv_name="${servers}-${volume}-${subdir}"
        cat - << EOT
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: "$pv_name"
  labels:
    - cluster: "$servers"
    - volume: "$volume"
spec:
  capacity:
    storage: $capacity
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
#  storageClassName: $storage_class
  flexVolume:
    driver: "rht/glfs-subvol"
    options:
      cluster: $servers
      volume: $volume
      dir: $subdir
EOT
}

servers=$1
volume_name=$2
base_path=$3
declare -i i=$4
declare -i i_end=$5

if [ $# -ne 5 ]; then usage; exit 1; fi
if [ $i -lt 0 ]; then usage; exit 1; fi
if [ $i -gt $i_end ]; then usage; exit 1; fi
if [ $i_end -gt 65535 ]; then usage; exit 1; fi

while [ $i -le $i_end ]; do
    dir="$base_path/$(tohexpath $i)"
    echo creating: $dir
    mkdir -p $dir || exit 2
    mkPvTemplate $servers $volume_name $(tohexpath $1) "1Gi" >> $base_path/pvs.yml
    ((++i))
done

exit 0
