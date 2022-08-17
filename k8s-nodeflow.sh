#!/usr/bin/env bash
set -Euo pipefail

K8S_NODEFLOW_DEBUG=${K8S_NODEFLOW_DEBUG:-no}
function _log() {
  [[ "$K8S_NODEFLOW_DEBUG" != "yes" ]] && return
  1>&2 echo "$@"
}

drain_every=${1:-600}
drain_nodes_with_this_label=$2
pods_not_running_by_this_label_prevent_draining=$3

while true; do
  started_at=$SECONDS

  while true; do
    pods_not_running=$(2>/dev/null kubectl get pod --no-headers \
      --all-namespaces \
      -l "$pods_not_running_by_this_label_prevent_draining" --field-selector=status.phase!=Running)

    [[ "$pods_not_running" == "" ]] && break
    _log "draining paused, pods with label '$pods_not_running_by_this_label_prevent_draining' not running:"
    _log "$pods_not_running"
    sleep 5
  done

  while true; do
    node=$(kubectl get node \
      --no-headers \
      --sort-by=.metadata.creationTimestamp \
      -l "$drain_nodes_with_this_label" \
      -o custom-columns=":metadata.name" \
      | head -n 1)

    [[ "$node" != "" ]] && break

    _log "failed to get oldest node with label '$drain_nodes_with_this_label'"
    sleep 1
  done

  while true; do
    >/dev/null 2>&1 kubectl drain "$node" --delete-local-data --ignore-daemonsets --force && break

    _log "failed to issue drain for '$node'"
    sleep 1
  done

  _log "issued drain for '$node'"

  took=$((SECONDS - started_at))
  remaining=$((drain_every - took))

  _log "took: $took"
  _log "remaining: $remaining"

  if [[ "$remaining" -lt 1 ]]; then
    sleep 1
  else
    sleep "$remaining"
  fi
done
