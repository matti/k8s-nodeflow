#!/usr/bin/env bash
set -Euo pipefail

K8S_NODEFLOW_DEBUG=${K8S_NODEFLOW_DEBUG:-no}
K8S_NODEFLOW_NODES_MINIMUM=${K8S_NODEFLOW_NODES_MINIMUM:-0}

function _log() {
  [[ "$K8S_NODEFLOW_DEBUG" != "yes" ]] && return
  1>&2 echo "$(date) $*"
}

drain_all_in=$1
drain_nodes_with_this_label=$2
pods_not_running_by_this_label_prevent_draining=$3

while true; do
  started_at=$SECONDS

  while true; do
    pods_not_running=$(2>/dev/null kubectl get pod --no-headers \
      --all-namespaces \
      -l "$pods_not_running_by_this_label_prevent_draining" --field-selector=status.phase!=Running) || true

    [[ "$pods_not_running" == "" ]] && break

    pods_not_running_count=$(echo "$pods_not_running" | wc -l | xargs) || true
    _log "draining paused, '$pods_not_running_count' pods with label '$pods_not_running_by_this_label_prevent_draining' not running"

    sleep 3
  done

  node=""
  nodes_count=-1

  while true; do
    nodes=$(kubectl get node \
      --no-headers \
      --sort-by=.metadata.creationTimestamp \
      -l "$drain_nodes_with_this_label" \
      -o custom-columns=":metadata.name") || true

    nodes_count=$(echo "$nodes" | wc -l | xargs) || true
    node=$(echo "$nodes" | head -n 1) || true

    _log "nodes_count: '$nodes_count' node: '$node'"

    [[ "$node" != "" ]] && break

    _log "failed to get oldest node with label '$drain_nodes_with_this_label'"
    sleep 1
  done

  if [[ "$nodes_count" -lt "$K8S_NODEFLOW_NODES_MINIMUM" ]]; then
    _log "nodes_count too low"
    sleep 10
    continue
  fi

  while true; do
    _log "draining '$node'"
    >/dev/null 2>&1 kubectl drain "$node" --delete-local-data --ignore-daemonsets --force && break

    _log "failed to issue drain for '$node'"
    sleep 1
  done

  took=$((SECONDS - started_at))
  remaining=$((drain_all_in - took))
  per_iteration_delay=$((remaining / nodes_count))

  _log "took: '$took' remaining: '$remaining' per_iteration_delay='$per_iteration_delay'"

  if [[ "$per_iteration_delay" -lt 1 ]]; then
    sleep 1
  else
    sleep "$per_iteration_delay"
  fi
done
