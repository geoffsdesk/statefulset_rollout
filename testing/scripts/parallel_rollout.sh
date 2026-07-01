#!/bin/bash
# Automated parallel partitioned rollout for StatefulSets
# Source: customer-workaround-guide.md Section 4
set -euo pipefail

# --- Configuration & Defaults ---
STS_NAME=""
NAMESPACE="default"
BATCH_SIZE=23
POLL_INTERVAL=10
TIMEOUT=300
NON_INTERACTIVE=false
DRY_RUN=false
NEW_IMAGE=""

usage() {
  echo "Usage: $0 -s <statefulset-name> [options]"
  echo "Options:"
  echo "  -s <name>        StatefulSet name (Required)"
  echo "  -n <namespace>   Kubernetes namespace (Default: 'default')"
  echo "  -b <batch-size>  Number of pods to update in parallel (Default: 23)"
  echo "  -p <interval>    Polling interval in seconds for health checks (Default: 10)"
  echo "  -t <timeout>     Max seconds to wait for a batch to become ready (Default: 300)"
  echo "  -i <image>       New container image to deploy (Optional)"
  echo "  -y               Non-interactive mode (disables confirmation prompt)"
  echo "  -d               Dry-run mode (logs actions without modifying the cluster)"
  exit 1
}

while getopts "s:n:b:p:t:i:ydh" opt; do
  case "$opt" in
    s) STS_NAME="$OPTARG" ;;
    n) NAMESPACE="$OPTARG" ;;
    b) BATCH_SIZE="$OPTARG" ;;
    p) POLL_INTERVAL="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    i) NEW_IMAGE="$OPTARG" ;;
    y) NON_INTERACTIVE=true ;;
    d) DRY_RUN=true ;;
    *) usage ;;
  esac
done

if [[ -z "$STS_NAME" ]]; then
  echo "ERROR: StatefulSet name (-s) is required."
  usage
fi

log() { echo "[$(date +'%Y-%m-%dT%H:%M:%S')] $1"; }
log_dry() { [[ "$DRY_RUN" = "true" ]] && echo "[DRY-RUN] $1" || log "$1"; }

get_statefulset_selector() {
  local raw_selector
  raw_selector=$(kubectl get statefulset "$STS_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null) || return 1
  [[ -z "$raw_selector" || "$raw_selector" == "{}" ]] && return 1
  echo "$raw_selector" | tr -d '{}"' | tr ':' '='
}

check_partition_health() {
  local target_partition=$1
  local pods_data
  # Fetch all pod statuses in a single call
  if ! pods_data=$(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" "}{.status.containerStatuses[*].ready}{"\n"}{end}' 2>/dev/null); then
    return 1
  fi

  declare -A pod_phases
  declare -A pod_ready

  while read -r line; do
    [[ -z "$line" ]] && continue
    read -r -a parts <<< "$line"
    local name="${parts[0]}"
    local phase="${parts[1]}"
    pod_phases["$name"]="$phase"
    local all_ready=true
    if [[ "${#parts[@]}" -lt 3 ]]; then
      all_ready=false
    else
      for ((i=2; i<${#parts[@]}; i++)); do
        if [[ "${parts[i]}" != "true" ]]; then
          all_ready=false
          break
        fi
      done
    fi
    pod_ready["$name"]="$all_ready"
  done <<< "$pods_data"

  local unhealthy_count=0
  for (( idx = target_partition; idx < REPLICAS; idx++ )); do
    local expected_pod="${STS_NAME}-${idx}"
    if [[ -z "${pod_phases[$expected_pod]:-}" ]]; then
      log "  -> Pod $expected_pod does not exist in API yet (recreating...)"
      unhealthy_count=$((unhealthy_count + 1))
      continue
    fi
    local phase="${pod_phases[$expected_pod]}"
    local ready="${pod_ready[$expected_pod]}"
    if [[ "$phase" != "Running" || "$ready" != "true" ]]; then
      log "  -> Pod $expected_pod is not ready (Phase: $phase, Ready: $ready)"
      unhealthy_count=$((unhealthy_count + 1))
    fi
  done

  [[ "$unhealthy_count" -gt 0 ]] && return 1 || return 0
}

rollback() {
  local total_replicas=$1
  log "WARNING: Rollout failed! Resetting partition to $total_replicas to lock rollout."
  if [[ "$DRY_RUN" = "true" ]]; then
    log_dry "kubectl patch statefulset $STS_NAME -n $NAMESPACE -p '{\"spec\":{\"updateStrategy\":{\"rollingUpdate\":{\"partition\":$total_replicas}}}}'"
  else
    kubectl patch statefulset "$STS_NAME" -n "$NAMESPACE" \
      -p "{\"spec\":{\"updateStrategy\":{\"rollingUpdate\":{\"partition\":$total_replicas}}}}"
  fi
  exit 1
}

# --- Parameter Validation ---
if ! [[ "$BATCH_SIZE" =~ ^[0-9]+$ ]] || [[ "$BATCH_SIZE" -le 0 ]]; then
  echo "ERROR: Batch size (-b) must be a positive integer."
  exit 1
fi
if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$POLL_INTERVAL" -le 0 ]]; then
  echo "ERROR: Polling interval (-p) must be a positive integer."
  exit 1
fi
if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -le 0 ]]; then
  echo "ERROR: Timeout (-t) must be a positive integer."
  exit 1
fi

log "Starting pre-flight validation..."
if ! command -v kubectl &> /dev/null; then
  echo "ERROR: 'kubectl' CLI is required."
  exit 1
fi

if ! REPLICAS=$(kubectl get statefulset "$STS_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.spec.replicas}' 2>/dev/null); then
  echo "ERROR: StatefulSet '$STS_NAME' not found."
  exit 1
fi

log "Found StatefulSet '$STS_NAME' with $REPLICAS replicas."
if [[ "$REPLICAS" -eq 0 ]]; then
  log "StatefulSet has 0 replicas. Nothing to roll out."
  exit 0
fi

POLICY=$(kubectl get statefulset "$STS_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.spec.podManagementPolicy}')
if [[ "$POLICY" != "Parallel" ]]; then
  echo "ERROR: StatefulSet must use 'podManagementPolicy: Parallel'."
  exit 1
fi

if ! SELECTOR=$(get_statefulset_selector); then
  log "WARNING: Could not auto-discover selector. Falling back to 'app=$STS_NAME'."
  SELECTOR="app=$STS_NAME"
fi

if [[ -n "$NEW_IMAGE" ]]; then
  log_dry "Locking rollout at partition=$REPLICAS and applying new image: $NEW_IMAGE..."
  CONTAINER_NAME=$(kubectl get statefulset "$STS_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].name}')
  patch_json="{\"spec\":{\"updateStrategy\":{\"rollingUpdate\":{\"partition\":$REPLICAS}},\"template\":{\"spec\":{\"containers\":[{\"name\":\"$CONTAINER_NAME\",\"image\":\"$NEW_IMAGE\"}]}}}}"
  if [[ "$DRY_RUN" = "true" ]]; then
    log_dry "kubectl patch statefulset $STS_NAME -n $NAMESPACE --type=strategic -p '$patch_json'"
  else
    kubectl patch statefulset "$STS_NAME" -n "$NAMESPACE" --type='strategic' -p "$patch_json"
    sleep 5
  fi
else
  if [[ "$DRY_RUN" = "false" ]]; then
    CURRENT_PARTITION=$(kubectl get statefulset "$STS_NAME" -n "$NAMESPACE" \
      -o jsonpath='{.spec.updateStrategy.rollingUpdate.partition}' 2>/dev/null || echo "0")
    if [[ "$CURRENT_PARTITION" -lt "$REPLICAS" ]]; then
      log "Resetting partition to $REPLICAS to ensure rollout is locked..."
      kubectl patch statefulset "$STS_NAME" -n "$NAMESPACE" \
        -p "{\"spec\":{\"updateStrategy\":{\"rollingUpdate\":{\"partition\":$REPLICAS}}}}"
    fi
  fi
fi

if [[ "$NON_INTERACTIVE" = "false" ]] && [[ "$DRY_RUN" = "false" ]] && [[ -t 0 ]]; then
  echo "==========================================================================="
  echo "  Ready to begin parallel partitioned rollout of $STS_NAME."
  echo "==========================================================================="
  read -p "Begin rollout? (y/N) " -n 1 -r; echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && { log "Cancelled."; exit 0; }
fi

CURRENT_PARTITION=$REPLICAS
while [[ "$CURRENT_PARTITION" -gt 0 ]]; do
  NEXT_PARTITION=$((CURRENT_PARTITION - BATCH_SIZE))
  [[ "$NEXT_PARTITION" -lt 0 ]] && NEXT_PARTITION=0

  log "---------------------------------------------------------------------------"
  log_dry "Processing Batch: Pods $NEXT_PARTITION to $((CURRENT_PARTITION - 1))"
  log "---------------------------------------------------------------------------"

  log_dry "Updating partition to $NEXT_PARTITION..."
  if [[ "$DRY_RUN" = "false" ]]; then
    kubectl patch statefulset "$STS_NAME" -n "$NAMESPACE" \
      -p "{\"spec\":{\"updateStrategy\":{\"rollingUpdate\":{\"partition\":$NEXT_PARTITION}}}}"
  fi

  PODS_TO_DELETE=""
  for ((i=NEXT_PARTITION; i<CURRENT_PARTITION; i++)); do
    PODS_TO_DELETE="$PODS_TO_DELETE $STS_NAME-$i"
  done

  log_dry "Deleting pods concurrently:$PODS_TO_DELETE"
  if [[ "$DRY_RUN" = "false" ]]; then
    # shellcheck disable=SC2086
    kubectl delete pods $PODS_TO_DELETE -n "$NAMESPACE"
  fi

  log "Waiting for batch to become healthy..."
  start_time=$(date +%s)
  while true; do
    if [[ "$DRY_RUN" = "true" ]]; then
      log_dry "Checking health of partition >= $NEXT_PARTITION..."
      break
    fi

    if check_partition_health "$NEXT_PARTITION"; then
      log "Batch healthy."
      break
    fi

    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    if [[ "$elapsed" -ge "$TIMEOUT" ]]; then
      log "ERROR: Timeout waiting for batch to become healthy."
      rollback "$REPLICAS"
    fi

    sleep "$POLL_INTERVAL"
  done

  CURRENT_PARTITION=$NEXT_PARTITION
done

log "==========================================================================="
log_dry "SUCCESS: Parallel partitioned rollout completed successfully for all $REPLICAS replicas!"
log "==========================================================================="
