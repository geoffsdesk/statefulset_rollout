#!/bin/bash
# Captures pod creation timestamps for a batch and calculates max spread.
# This is the core parallelism proof: if max spread < 5s, pods were created concurrently.
#
# Usage: ./capture-timestamps.sh <statefulset-name> <namespace> <start-ordinal> <end-ordinal> [output-file]
# Example: ./capture-timestamps.sh test-sts default 92 114 batch1-timestamps.txt

set -euo pipefail

STS="$1"
NS="${2:-default}"
START="$3"
END="$4"
OUTPUT="${5:-/dev/stdout}"

echo "=== Pod Creation Timestamps for $STS pods $START-$END ===" | tee "$OUTPUT"
echo "Captured at: $(date -u +'%Y-%m-%dT%H:%M:%SZ')" | tee -a "$OUTPUT"
echo "---" | tee -a "$OUTPUT"

declare -a timestamps=()
declare -a epoch_times=()

for ((i=START; i<=END; i++)); do
  pod_name="${STS}-${i}"
  ts=$(kubectl get pod "$pod_name" -n "$NS" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "NOT_FOUND")
  echo "$pod_name  $ts" | tee -a "$OUTPUT"
  if [ "$ts" != "NOT_FOUND" ]; then
    epoch=$(date -d "$ts" +%s 2>/dev/null || echo "0")
    timestamps+=("$ts")
    epoch_times+=("$epoch")
  fi
done

echo "---" | tee -a "$OUTPUT"

if [ "${#epoch_times[@]}" -ge 2 ]; then
  min_epoch="${epoch_times[0]}"
  max_epoch="${epoch_times[0]}"
  for e in "${epoch_times[@]}"; do
    [ "$e" -lt "$min_epoch" ] && min_epoch="$e"
    [ "$e" -gt "$max_epoch" ] && max_epoch="$e"
  done
  spread=$((max_epoch - min_epoch))
  echo "Earliest: $(date -d "@$min_epoch" -u +'%Y-%m-%dT%H:%M:%SZ')" | tee -a "$OUTPUT"
  echo "Latest:   $(date -d "@$max_epoch" -u +'%Y-%m-%dT%H:%M:%SZ')" | tee -a "$OUTPUT"
  echo "Max spread: ${spread}s" | tee -a "$OUTPUT"
  if [ "$spread" -le 5 ]; then
    echo "VERDICT: PARALLEL (spread <= 5s)" | tee -a "$OUTPUT"
  elif [ "$spread" -le 30 ]; then
    echo "VERDICT: LIKELY PARALLEL with staggering (spread <= 30s)" | tee -a "$OUTPUT"
  else
    echo "VERDICT: SEQUENTIAL (spread > 30s — pods were NOT created concurrently)" | tee -a "$OUTPUT"
  fi
else
  echo "ERROR: Not enough pods found to compute spread" | tee -a "$OUTPUT"
fi
