#!/bin/bash
# Pre-flight check for StatefulSet partition stepping workaround
# Source: customer-workaround-guide.md Section 0.5
# Usage: ./preflight.sh <statefulset-name> <namespace>
STS="$1"; NS="${2:-default}"

if [ -z "$STS" ]; then
  echo "Usage: $0 <statefulset-name> [namespace]"
  exit 1
fi

echo "Pre-flight check for StatefulSet '$STS' in namespace '$NS'"
echo "============================================================"

PMP=$(kubectl get sts "$STS" -n "$NS" -o jsonpath='{.spec.podManagementPolicy}' 2>/dev/null)
[ -z "$PMP" ] && PMP="OrderedReady"
if [ "$PMP" = "Parallel" ]; then echo "[PASS] podManagementPolicy = Parallel"
else echo "[FAIL] podManagementPolicy = $PMP -> IMMUTABLE: recreate the StatefulSet (Section 0.1)"; fi

UST=$(kubectl get sts "$STS" -n "$NS" -o jsonpath='{.spec.updateStrategy.type}' 2>/dev/null)
[ -z "$UST" ] && UST="RollingUpdate"
if [ "$UST" = "RollingUpdate" ]; then echo "[PASS] updateStrategy.type = RollingUpdate"
else echo "[WARN] updateStrategy.type = $UST -> use the OnDelete variant (0.6); partition steps do not apply"; fi

ORD=$(kubectl get sts "$STS" -n "$NS" -o jsonpath='{.spec.ordinals.start}' 2>/dev/null)
if [ -z "$ORD" ] || [ "$ORD" = "0" ]; then echo "[PASS] ordinals.start = 0 (pods are $STS-0 .. N-1)"
else echo "[FAIL] ordinals.start = $ORD -> shift every delete/seq range by +$ORD"; fi

REP=$(kubectl get sts "$STS" -n "$NS" -o jsonpath='{.spec.replicas}' 2>/dev/null)
echo "[INFO] replicas = ${REP:-unknown} (guide batch math assumes this is N)"

MGRS=$(kubectl get sts "$STS" -n "$NS" -o jsonpath='{range .metadata.managedFields[*]}{.manager}{"\n"}{end}' 2>/dev/null | sort -u | paste -sd, -)
echo "[INFO] field managers: ${MGRS:-none}"
echo "  -> if argocd/configsync/flux/kustomize-controller appears, PAUSE GitOps first (Section 0.3)"

PVCS=$(kubectl get sts "$STS" -n "$NS" -o jsonpath='{.spec.volumeClaimTemplates[*].metadata.name}' 2>/dev/null)
if [ -z "$PVCS" ]; then echo "[PASS] no volumeClaimTemplates (no Persistent Disk attach risk)"
else echo "[WARN] uses PVCs ($PVCS) -> raise --timeout; expect PD detach/attach on reschedule (Section 0.4)"; fi

echo "[INFO] can patch sts: $(kubectl auth can-i patch statefulsets -n "$NS" 2>/dev/null)"
echo "[INFO] can delete pods: $(kubectl auth can-i delete pods -n "$NS" 2>/dev/null)"

READINESS=$(kubectl get sts "$STS" -n "$NS" -o jsonpath='{.spec.template.spec.containers[*].readinessProbe}' 2>/dev/null)
if [ -n "$READINESS" ]; then echo "[PASS] Readiness probe is configured"
else echo "[WARN] No readiness probe configured! Script health checks may be unreliable (Section 0.2)"; fi
