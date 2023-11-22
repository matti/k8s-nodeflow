#!/usr/bin/env bash

export K8S_NODEFLOW_DEBUG=yes

for label in ${*} ; do
  (
    ./k8s-nodeflow.sh 1 "$label"
  ) 2>&1 | sed -le "s#^#$label: #;" &
done

wait
