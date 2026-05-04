# PDO-11468: Prometheus Agent OOMKill — Remote Write `queue_config` Analysis

**Date:** 2026-05-01  
**Branch:** `polaris/PDO-11468-prometheus-agent-oom-remote-write`  
**Ticket:** [PDO-11468](https://pingidentity.atlassian.net/browse/PDO-11468)  
**Analyst:** Walker Brown / Claude Sonnet 4.6

---

## 1. What the Ticket Requester Is Saying

The requester observed Prometheus Agent pods OOMKilling in multiple production environments (Met US Prod, Centene Prod). Investigation traced the root cause to unbounded shard growth in the `remote_write` queue — Prometheus was spawning too many shards under write load, exhausting pod memory. The smoking-gun log line is:

```
msg="Remote storage resharding" from=X to=Y
```

The manual fix applied in production was adding the following to `prometheus.yml` in the `prometheus-agent-config` ConfigMap:

```yaml
queue_config:
  max_shards: 30
  min_shards: 5
  capacity: 2500
  max_samples_per_send: 500
```

The requester correctly observed that because `prometheus.yml` is a string scalar embedded inside a ConfigMap (YAML-within-YAML), a surgical `strategic merge patch` or `json6902` patch cannot target individual keys inside that string — the entire ConfigMap content must be reproduced in any patch.

The requester also asked for a long-term approach involving variables for these settings.

---

## 2. Is the Root Cause Analysis Correct?

**Yes, it is accurate and well-understood.**

Prometheus `remote_write` uses a WAL-based queue with a sharding model. Each shard is a goroutine maintaining its own in-memory buffer. The defaults (as of Prometheus 2.x) are:

| Parameter | Default |
|---|---|
| `max_shards` | 50 |
| `min_shards` | 1 |
| `capacity` | 10000 (per shard) |
| `max_samples_per_send` | 2000 |

With `max_shards: 50` and `capacity: 10000` per shard, the theoretical maximum in-memory buffer is **50 × 10000 × ~(sample size)** which can easily consume several hundred MB to >1 GB under write pressure. The agent pod's memory limit is breached, triggering OOMKill. The resharding log message confirms the agent was actively scaling up shards in response to backpressure — a classic runaway growth scenario.

The requester's workaround values cap shard count at 30 and reduce per-shard capacity to 2500, limiting worst-case buffer to **30 × 2500 = 75,000 samples in flight** vs. the default **50 × 10000 = 500,000** — a ~6.7× reduction in max memory exposure.

---

## 3. Is the Proposed Fix (`queue_config` values) Correct and Safe?

### The values themselves

```yaml
max_shards: 30
min_shards: 5
capacity: 2500
max_samples_per_send: 500
```

**Assessment: Reasonable, but hardcoded and not universally correct.**

| Parameter | Value | Analysis |
|---|---|---|
| `max_shards: 30` | Below default (50) | Caps shard count. The trade-off is write throughput — if the remote write endpoint is slow or backpressured, 30 shards may cause samples to be dropped or WAL lag to grow. |
| `min_shards: 5` | Above default (1) | Forces 5 shards always active even at idle. Minor memory overhead, helps responsiveness on write burst. Fine. |
| `capacity: 2500` | Below default (10000) | 4× reduction from default per-shard buffer. Meaningfully reduces memory footprint per shard alongside `max_shards`. |
| `max_samples_per_send: 500` | Below default (2000) | 4× reduction from default batch size. Reduces per-flush memory pressure at the cost of more frequent sends. |

The values were "production-verified" on the affected environments and match the requester's manual fix, so they are known to stop the OOMKills on those specific clusters. All four values are reductions from their defaults — this is a conservative, memory-first configuration. The trade-off is throughput: a larger or busier cluster may eventually saturate 30 shards or find the reduced batch sizes insufficient, and a smaller/quieter cluster doesn't need `min_shards: 5`.

### The patching approach (full ConfigMap replacement)

The requester correctly identified the constraint: `prometheus.yml` is a multi-line string scalar embedded as a ConfigMap `data` value. Kustomize (and kubectl merge patch) cannot surgically target a key inside a string scalar — there is no JSON path into it.

The implemented approach — reproducing the full ConfigMap with `argocd.argoproj.io/sync-options: Replace=true` — is **correct and consistent** with the existing pattern in this repo (e.g., `opensearch_enable_auth_patch_*`). The `Replace=true` annotation is necessary because ArgoCD's default apply strategy will attempt a strategic merge, which can fail or misbehave on large ConfigMaps; `Replace` forces a clean overwrite.

**Risk of the full-replacement approach:** If the upstream base ConfigMap (`p1as-observability`) changes (new scrape job added, label changed, etc.), the patch silently wins — the patch's stale copy of `prometheus.yml` will override the upstream update, and the new upstream content will be invisible until the patch file is manually updated. This is the primary long-term maintenance risk.

---

## 4. What the Patch Actually Changes vs. the Base

Base (`p1as-observability/deploy/p1as-prometheus-agent/values.yaml`):

```yaml
remoteWrite:
- url: 'http://prometheus-headless:9090/api/v1/write'
# no queue_config
```

Patch (`prometheus_agent_queue_config_patch_2_1/prometheus-agent-config.yaml`):

```yaml
remote_write:
- url: 'http://prometheus:9090/api/v1/write'
  queue_config:
    max_shards: 30
    min_shards: 5
    capacity: 2500
    max_samples_per_send: 500
```

Two differences worth noting:
1. **`queue_config` block added** — the fix.
2. **URL differs**: base uses `http://prometheus-headless:9090/api/v1/write`, patch uses `http://prometheus:9090/api/v1/write`. The headless service vs. ClusterIP distinction matters for HA Prometheus setups. This difference pre-exists in the patch infrastructure and is not introduced by PDO-11468, but worth confirming it is intentional for the PCB 2.1 context.

---

## 5. Alternatives and Long-Term Recommendations

### Alternative A: Helm values override (preferred long-term)

If the prometheus-agent is managed via the `p1as-prometheus-agent` Helm chart (kube-prometheus-stack), the `remoteWrite` block in `values.yaml` supports the full queue_config structure natively:

```yaml
remoteWrite:
- url: 'http://prometheus-headless:9090/api/v1/write'
  queueConfig:
    maxShards: 30
    minShards: 5
    capacity: 2500
    maxSamplesPerSend: 500
```

This avoids full-replacement patches entirely — the Helm chart generates the ConfigMap, so values merge cleanly. This is the cleanest long-term path if/when the base moves to full Helm-managed config.

### Alternative B: Kustomize `replacements` or `vars` (medium term)

Introduce Kustomize variables for the queue_config values so that per-environment tuning doesn't require maintaining separate patch files per environment:

```yaml
# kustomization.yaml
vars:
- name: MAX_SHARDS
  objref: {kind: ConfigMap, name: prometheus-queue-config-vars, apiVersion: v1}
  fieldref: {fieldpath: data.maxShards}
```

This allows a single patch template with environment-specific variable injection. More complex to set up but avoids N copies of the full ConfigMap.

### Alternative C: Status quo (current implementation)

Keep the full-replacement patch for PCB 2.1+. Simple, auditable, consistent with the repo pattern. The maintenance risk (upstream drift) is manageable if there is a process to review patches when the base prometheus-agent-config is updated upstream.

**Recommendation:** The current patch (Alternative C) is the right short-term fix — it directly addresses production incidents with proven values. The long-term goal (as the requester hints) should be to drive these settings into the Helm values layer (Alternative A), making them first-class variables rather than buried in a copied YAML string.

---

## 6. Safety Assessment Summary

| Concern | Assessment |
|---|---|
| Root cause is correctly identified | ✅ Yes |
| Workaround values are safe | ✅ Yes, with caveat: may limit throughput on high-cardinality clusters |
| Patching approach (full replacement) is correct | ✅ Yes, given Kustomize's constraint on string scalars |
| `Replace=true` annotation is appropriate | ✅ Yes, consistent with repo pattern |
| Risk of upstream drift silently overridden | ⚠️ Real risk — mitigated by PCB 2.1+ scoping and change review process |
| Values are hardcoded (not parameterized) | ⚠️ Acceptable short-term; long-term variable injection preferred |
| URL difference (headless vs. ClusterIP) | ⚠️ Pre-existing, confirm intentional for PCB 2.1 context |

---

## 7. References

- Prometheus `remote_write` queue_config docs: https://prometheus.io/docs/prometheus/latest/configuration/configuration/#queue_config
- PDO-11468 Jira: https://pingidentity.atlassian.net/browse/PDO-11468
- Related incidents: P1ASSD-26098 (Met US Prod), P1ASSD-26162 (Centene Prod)
- Patch file: `components/monitoring/prometheus_agent_queue_config_patch_2_1/prometheus-agent-config.yaml`
- Base config: `p1as-apps/p1as-observability/deploy/p1as-prometheus-agent/values.yaml`
