# Success Criteria — StatefulSet Partition Stepping Workaround Verification

Each criterion is numbered, measurable, and traced to a milestone. Testing is not complete until every criterion has a recorded **PASS** or **FAIL** with an evidence file reference.

---

## M0: Test Environment Provisioning & Baseline

| ID | Criterion | Measurement | Evidence File |
|----|-----------|-------------|---------------|
| SC-0.1 | Cluster is GKE 1.35.x Standard mode | `gcloud container clusters describe` output shows `currentMasterVersion: 1.35.*` and `autopilot.enabled: false` | `evidence/M0-environment/cluster-describe.txt` |
| SC-0.2 | StatefulSet has 115 running/ready pods with `Parallel` policy | `kubectl get sts` shows `READY 115/115`; jsonpath shows `podManagementPolicy: Parallel` | `evidence/M0-environment/sts-status.txt` |
| SC-0.3 | All test manifests committed to repo | `ls testing/manifests/` shows all YAML files | `testing/manifests/*.yaml` |

---

## M1: Regression Confirmation

| ID | Criterion | Measurement | Evidence File |
|----|-----------|-------------|---------------|
| SC-1.1 | Pods update one at a time after rolling update | `kubectl get pods -w` log shows pods terminating/recreating sequentially by descending ordinal, never more than 1 simultaneously | `evidence/M1-regression/pod-watch.log` |
| SC-1.2 | Wall-clock proves sequential behavior | Time for 10 pods to update is >= 10x the time for a single pod (no batching) | `evidence/M1-regression/timing.txt` |
| SC-1.3 | `maxUnavailable` is set but ignored | `kubectl get sts -o jsonpath` shows `maxUnavailable: 20%` or `maxUnavailable: 23`; pod-watch proves only 1 updates at a time | `evidence/M1-regression/sts-spec.txt` |

---

## M2: Pre-flight Script Validation

| ID | Criterion | Measurement | Evidence File |
|----|-----------|-------------|---------------|
| SC-2.1 | All [PASS] on correctly configured StatefulSet | Script output shows [PASS] for podManagementPolicy, updateStrategy, ordinals, readinessProbe; no [FAIL] | `evidence/M2-preflight/known-good.log` |
| SC-2.2 | [FAIL] on OrderedReady policy | Script output contains `[FAIL] podManagementPolicy = OrderedReady` | `evidence/M2-preflight/ordered-ready.log` |
| SC-2.3 | [WARN] on OnDelete strategy | Script output contains `[WARN] updateStrategy.type = OnDelete` | `evidence/M2-preflight/on-delete.log` |
| SC-2.4 | [WARN] when PVCs present | Script output contains `[WARN] uses PVCs` | `evidence/M2-preflight/pvc.log` |
| SC-2.5 | RBAC checks report correct permissions | Script output shows `can patch sts: yes/no` and `can delete pods: yes/no` matching actual RBAC | `evidence/M2-preflight/rbac.log` |
| SC-2.6 | Script exits cleanly in all scenarios | Exit code 0 in all runs; no unhandled errors, no stack traces | All M2 log files |

---

## M3: Manual Procedure Validation

| ID | Criterion | Measurement | Evidence File |
|----|-----------|-------------|---------------|
| SC-3.1 | partition=115 prevents auto-update | After applying new template with partition=115, `kubectl get pods` shows all pods still on old image after 60s wait | `evidence/M3-manual/partition-lock.log` |
| SC-3.2 | Batch pods recreate concurrently | For each batch, `creationTimestamp` max spread across all pods in the batch is < 5 seconds | `evidence/M3-manual/batch-N-timestamps.txt` |
| SC-3.3 | Only pods >= partition on new revision | After each batch, `kubectl get pods -o jsonpath` shows new image only on pods with ordinal >= current partition | `evidence/M3-manual/batch-N-revisions.txt` |
| SC-3.4 | Each batch reaches Running/Ready | `kubectl get pods` after each batch shows all batch pods `Running` with `READY 1/1` (or equivalent) | `evidence/M3-manual/batch-N-health.txt` |
| SC-3.5 | All 115 pods on new image at completion | Final `kubectl get pods -o wide` shows all 115 pods with new image tag | `evidence/M3-manual/final-state.txt` |
| SC-3.6 | Every kubectl command is copy-paste correct | Manual log shows each guide command was executed verbatim (with name substitution only) and produced expected output | `evidence/M3-manual/terminal-recording.*` |

---

## M4: Automated Script Validation

| ID | Criterion | Measurement | Evidence File |
|----|-----------|-------------|---------------|
| SC-4.1 | Dry-run logs correct batches, no cluster changes | Script output shows `[DRY-RUN]` lines with correct pod ranges; `kubectl get sts` shows no partition change before/after | `evidence/M4-automated/dry-run.log` |
| SC-4.2 | _(removed — full scale only)_ | | |
| SC-4.3 | Live 115-replica run completes all 5 batches | Script exits 0; final `kubectl get sts` shows all 115 pods on new image, partition=0 | `evidence/M4-automated/live-115.log` |
| SC-4.4 | `-i` flag locks + deploys + rolls out | Script output shows partition lock, image patch, then batch sequence; final pods on specified image | `evidence/M4-automated/image-flag.log` |
| SC-4.5 | Invalid parameters produce errors | `-b 0`, `-b abc`, `-t -1` each produce `ERROR:` message and exit non-zero | `evidence/M4-automated/invalid-params.log` |
| SC-4.6 | Selector auto-discovery works | Script does not log `WARNING: Could not auto-discover selector` when labels exist | `evidence/M4-automated/live-115.log` |

---

## M5: Failure Mode & Rollback Testing

| ID | Criterion | Measurement | Evidence File |
|----|-----------|-------------|---------------|
| SC-5.1 | Bad image triggers rollback | Script logs `ERROR: Timeout`, patches partition back to N, exits non-zero | `evidence/M5-failure-modes/bad-image.log` |
| SC-5.2 | Short timeout triggers rollback | With `-t 5`, script rolls back even though pods would eventually become healthy | `evidence/M5-failure-modes/short-timeout.log` |
| SC-5.3 | Post-rollback state is safe | Pods below last successful partition are on old image; pods above are on new image (or rolled back) | `evidence/M5-failure-modes/post-rollback-state.txt` |
| SC-5.4 | PDB bypass confirmed | `kubectl delete pod` succeeds immediately despite PDB with `maxUnavailable: 0` | `evidence/M5-failure-modes/pdb-bypass.log` |
| SC-5.5 | OrderedReady produces sequential recreation | After batch delete on OrderedReady STS, creation timestamps show pods created >10s apart sequentially | `evidence/M5-failure-modes/ordered-ready-sequential.log` |

---

## M6: OnDelete Alternative Path

| ID | Criterion | Measurement | Evidence File |
|----|-----------|-------------|---------------|
| SC-6.1 | OnDelete template update: zero auto-updates | After applying new template, 60s wait shows all pods still on old image | `evidence/M6-ondelete/template-no-update.log` |
| SC-6.2 | Deleted batch recreates in parallel on new revision | Creation timestamps max spread < 5s; pods come up on new image | `evidence/M6-ondelete/batch-timestamps.txt` |
| SC-6.3 | Full rollout completes | All 115 pods on new image after all batches | `evidence/M6-ondelete/final-state.txt` |

---

## M7: Independent Cold-Reader Walkthrough

| ID | Criterion | Measurement | Evidence File |
|----|-----------|-------------|---------------|
| SC-7.1 | Independent reader completes procedure end-to-end | Log shows completion without external help or guide deviation | `evidence/M7-independent/walkthrough.log` |
| SC-7.2 | Every command is copy-paste correct | No commands required modification beyond name/namespace substitution | `evidence/M7-independent/walkthrough.log` |
| SC-7.3 | Confusion points documented | List of ambiguities or issues found (may be empty if none) | `evidence/M7-independent/issues.md` |

---

## M8: Evidence Package & Engineering Report

| ID | Criterion | Measurement | Evidence File |
|----|-----------|-------------|---------------|
| SC-8.1 | Every SC from M0-M7 has pass/fail with evidence | `RESULTS.md` table has no blank cells in Pass/Fail or Evidence columns | `testing/RESULTS.md` |
| SC-8.2 | All evidence committed | `git status` shows clean tree after final commit | `git log` |
| SC-8.3 | Guide corrections tracked | If corrections were made, each has its own commit with rationale in message | `git log` |
| SC-8.4 | Package is self-contained | Engineering reviewer confirms they can assess the workaround without running any commands | Reviewer sign-off in `MILESTONES.md` |
