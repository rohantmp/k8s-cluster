#! /bin/bash
# vim: set ts=4 sw=4 et :

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

    local pv_name=$(echo "${servers}-${volume}-${subdir}" | tr ':/' '-')
    cat - << EOT
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: "$pv_name"
  labels:
    cluster: "$(echo $servers | tr ':' '-')"
    volume: "$volume"
    subdir: "$(echo $subdir | tr '/' '-')"
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

function kube_cmd() {
    local sa_dir=/var/run/secrets/kubernetes.io/serviceaccount
    kubectl \
        --server=https://kubernetes.default.svc.cluster.local \
        --token=$(cat $sa_dir/token) \
        --certificate-authority=$sa_dir/ca.crt \
        $*
}

endpoint_name=$1
volume_name=$2
base_path=$3
declare -i i=$4
declare -i i_end=$5

servers=$(kube_cmd get ep/$endpoint_name -o jsonpath='{.subsets[*].addresses[*].ip}' | tr ' ' ':')
if [ $? != 0 ]; then
    echo "Unable to retrieve IPs for ep/$endpoint_name. Aborting."
    exit 1
fi

if [ $# -ne 5 ]; then usage; exit 1; fi
if [ $i -lt 0 ]; then usage; exit 1; fi
if [ $i -gt $i_end ]; then usage; exit 1; fi
if [ $i_end -gt 65535 ]; then usage; exit 1; fi

gpod=$(kube_cmd -n glusterfs get po -l glusterfs-node=pod -o jsonpath='{.items[0].metadata.name}')
if [ $? -ne 0 ]; then
    echo Unable to locate a gluster pod. Aborting.
    exit 1
fi

#-- Make sure quota is enabled on the volume
kube_cmd -n glusterfs exec $gpod gluster volume quota $volume_name enable
if [ $? != 0 ]; then
    echo "Failed enabling quotas on the volume... continuing anyway."
fi

#-- df on a directory should report remaining quota allowance,
#-- not volume free space.
kube_cmd -n glusterfs exec $gpod gluster volume set $volume_name quota-deem-statfs on
if [ $? != 0 ]; then
    echo "Failed setting df space reporting volume option... continuing anyway."
fi

while [ $i -le $i_end ]; do
    subdir="$(tohexpath $i)"
    dir="$base_path/$subdir"
    echo "creating: $dir ($i/$i_end)"
    mkdir -p $dir
    if [ $? != 0 ]; then
        echo "Unable to create $dir"
        exit 2
    fi
    chmod 777 $dir
    if [ $? != 0 ]; then
        echo "Unable to set permissions on $dir"
        exit 2
    fi
    mkPvTemplate $servers $volume_name $subdir "1Gi" >> $base_path/pvs.yml
    kube_cmd -n glusterfs exec $gpod gluster volume quota $volume_name limit-usage /$subdir 1GB
    if [ $? != 0 ]; then
        echo -n "Unable to set gluster quota. "
        echo "pod=$gpod vol=$volume_name subdir=$subdir"
        exit 2
    fi
    mkPvTemplate $servers $volume_name $subdir "1Gi" | kube_cmd apply -f -
    if [ $? != 0 ]; then
        echo "Unable to create PV"
        exit 2
    fi
    ((++i))
done

exit 0
