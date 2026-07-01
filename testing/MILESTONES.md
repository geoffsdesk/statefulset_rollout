# Milestone Tracker — StatefulSet Partition Stepping Workaround Verification

**Guide under test:** `customer-workaround-guide.md`
**Test date:** 2026-07-01
**Tester:** geoffanderson
**Cluster:** sts-rollout-test (us-central1-a)
**GKE version:** 1.35.5-gke.1324000

---

## Status Key

| Symbol | Meaning |
|--------|---------|
| `[ ]`  | Not started |
| `[~]`  | In progress |
| `[x]`  | Complete — criteria met |
| `[!]`  | Complete — criteria NOT met (see notes) |
| `[S]`  | Signed off by engineering reviewer |

---

## Milestones

### M0: Test Environment Provisioning & Baseline
- [x] GKE 1.35.x Standard cluster provisioned (1.35.5-gke.1324000, 5x e2-standard-4)
- [x] 115-replica Parallel StatefulSet deployed and all pods Ready (115/115)
- [x] Negative-control OrderedReady StatefulSet deployed (10/10)
- [x] All manifests committed to `testing/manifests/`
- [x] Evidence captured to `testing/evidence/M0-environment/`
- [ ] **Sign-off:** [ ]

### M1: Regression Confirmation
- [x] Native rolling update triggered — observed 1-by-1 sequential behavior (12 pods in 90s, max 1 updating at a time)
- [x] Wall-clock timing recorded for first 10 pods (~7.5s per pod, projected 14.4min for 115)
- [x] `maxUnavailable` present in annotation but stripped from live spec (feature gate disabled)
- [x] StatefulSet reverted to original image (clean state for M2+)
- [x] Evidence captured to `testing/evidence/M1-regression/`
- [ ] **Sign-off:** [ ]

### M2: Pre-flight Script Validation
- [x] `preflight.sh` extracted to `testing/scripts/`
- [x] Known-good StatefulSet: all [PASS] (5 PASS, 0 FAIL, 0 WARN)
- [x] Known-bad (OrderedReady): [FAIL] on podManagementPolicy
- [x] OnDelete strategy: [WARN] on updateStrategy
- [x] PVC StatefulSet: [WARN] on volumeClaimTemplates (PVC name: data)
- [x] RBAC restricted SA: correctly reports `no` for patch/delete
- [x] Non-existent StatefulSet: exits cleanly (exit 0), reports [FAIL] and [WARN] appropriately
- [x] Evidence captured to `testing/evidence/M2-preflight/`
- [ ] **Sign-off:** [ ]

### M3: Manual Procedure Validation (Section 3)
- [x] Partition=115 locks rollout — 0/115 pods updated after template change
- [x] Batch 1 (pods 92-114): parallel recreation confirmed (spread=12s)
- [x] Batch 2 (pods 69-91): parallel recreation confirmed (spread=7s)
- [x] Batch 3 (pods 46-68): parallel recreation confirmed (spread=9s)
- [x] Batch 4 (pods 23-45): parallel recreation confirmed (spread=7s)
- [x] Batch 5 (pods 0-22): parallel recreation confirmed (spread=9s)
- [x] All 115 pods on new image at completion (115/115 nginx:1.27.1)
- [x] Every kubectl command in guide is copy-paste correct (substituting STS name only)
- [x] Parallelism timestamp analysis (avg spread 8.8s vs 172.5s sequential — 5.4x speedup)
- [x] Evidence captured to `testing/evidence/M3-manual/`
- [ ] **Sign-off:** [ ]

### M4: Automated Script Validation (Section 4)
- [x] `parallel_rollout.sh` extracted to `testing/scripts/`
- [x] Dry-run: correct 5-batch sequence logged, partition unchanged after run
- [x] Live 115-replica run: all 5 batches complete, 115/115 on nginx:1.27.1
- [x] `-i nginx:1.27.1` flag: locked partition, applied image, completed rollout
- [x] `-y` flag: skipped confirmation prompt (used in live run)
- [x] Invalid parameters: `-b 0`, `-b abc`, `-t -1`, missing `-s` all produce clear ERROR messages
- [x] Selector auto-discovery: no fallback warning in logs (labels discovered correctly)
- [ ] Non-default namespace: `-n` flag _(not tested — requires additional setup)_
- [x] Wall-clock: 130s automated vs ~864s projected sequential (6.6x speedup)
- [x] Evidence captured to `testing/evidence/M4-automated/`
- [ ] **Sign-off:** [ ]

### M5: Failure Mode & Rollback Testing
- [ ] Bad image: script times out, partition resets to N, exits non-zero
- [ ] Short timeout (`-t 5`): triggers rollback on healthy-but-slow pods
- [ ] Post-rollback state: pods below last partition on old image (safe)
- [ ] PDB bypass: `kubectl delete pod` succeeds despite PDB `maxUnavailable: 0`
- [ ] OrderedReady negative: batch delete produces sequential recreation
- [ ] Mid-rollout node drain: records impact on batch health (stretch goal)
- [ ] Idempotency: two sequential rollouts (v1→v2, v2→v3) both succeed
- [ ] Evidence captured to `testing/evidence/M5-failure-modes/`
- [ ] **Sign-off:** [ ]

### M6: OnDelete Alternative Path (Section 0.6)
- [ ] OnDelete + Parallel StatefulSet: template update produces zero auto-updates
- [ ] Deleted batch recreates in parallel on new revision
- [ ] Full rollout completes successfully
- [ ] Trade-off test: incidental pod deletion returns on new revision (wider blast radius)
- [ ] Evidence captured to `testing/evidence/M6-ondelete/`
- [ ] **Sign-off:** [ ]

### M7: Independent Cold-Reader Walkthrough
- [ ] Walkthrough performed by independent reader OR clean-room self-test
- [ ] Different cluster/namespace/StatefulSet name used (no hardcoded assumptions)
- [ ] Every confusion point or ambiguity documented
- [ ] Guide corrections tracked as issues or separate commits
- [ ] Evidence captured to `testing/evidence/M7-independent/`
- [ ] **Sign-off:** [ ]

### M8: Evidence Package & Engineering Report
- [ ] All evidence files committed under `testing/evidence/M*-*/`
- [ ] `testing/RESULTS.md` written with per-milestone pass/fail
- [ ] Key measurements included (baseline timing vs. workaround timing)
- [ ] Issues found and corrections made are documented
- [ ] Residual risks / open items listed
- [ ] Package is self-contained — engineering can review without running anything
- [ ] **Sign-off:** [ ]

---

## Final Engineering Review

- [ ] All milestones signed off
- [ ] All success criteria in `SUCCESS-CRITERIA.md` have pass/fail with evidence reference
- [ ] Guide corrections (if any) committed with rationale
- [ ] **Engineering reviewer:** _(name)_
- [ ] **Review date:** _(date)_
- [ ] **Verdict:** APPROVED / APPROVED WITH CONDITIONS / REJECTED
