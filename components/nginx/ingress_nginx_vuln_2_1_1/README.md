# ingress-nginx Vulnerability Patch (K000161019) — P1AS v2.1.1

Addresses CVE K000161019 for customers on P1AS `v2.1.1` by:

- Updating the `nginx-ingress-controller` image (both public and private) to the Chainguard-based fork without the vulnerability
- Removing modsecurity annotations from the `pingaccess-was-ingress` ingress object

## Usage

1. Open the `k8s-configs/base/kustomization.yaml` file for your environment.
2. Locate (or add) the `components:` section.
3. Add the following:

```yaml
components:
  - github.com/pingidentity/ping-cloud-base-patches//components/nginx/ingress_nginx_vuln_2_1_1
```

When testing, you may also add the branch name as shown below.

```yaml
components:
  - github.com/pingidentity/ping-cloud-base-patches//components/nginx/ingress_nginx_vuln_2_1_1?ref=pdo-11779
```

4. Sync ArgoCD in all regions.

## What it patches

| Resource | Namespace | Change |
|---|---|---|
| `Deployment/nginx-ingress-controller` | `ingress-nginx-private` | Updates image to Chainguard fork |
| `Deployment/nginx-ingress-controller` | `ingress-nginx-public` | Updates image to Chainguard fork |
| `Ingress/pingaccess-was-ingress` | `ping-cloud` | Removes `enable-modsecurity` and `modsecurity-snippet` annotations |

## Snippet-annotation helper: `patch-nginx-snippet-annotations.sh`

Newer ingress-nginx builds require both `allow-snippet-annotations: "true"` and `annotations-risk-level: "Critical"` to be set on the `nginx-configuration` ConfigMap before snippet annotations (`configuration-snippet`, `server-snippet`, `location-snippet`, `stream-snippet`) on ingress objects will be honored. This helper script inspects the live cluster and, if a snippet annotation is present but the ConfigMap is not configured to allow it, appends the required patch to the CSR's `k8s-configs/base/custom-patches.yaml`.

### Prerequisites

- Run from the root of the cluster-state-repo (the script derives `CSR_PATH` from its own location, so keep the script inside the CSR root).
- You must be connected to the target cluster via Teleport (`tsh kube login <cluster>`) before running the script. The script queries the live cluster via `kubectl` and will exit early if no context is set. On start-up it prints the currently connected context — confirm it matches the intended environment before letting the script continue.
- `jq` and `yq` (mikefarah/yq v4+) available on `PATH`. `yq` is required for in-place merging into existing `custom-patches.yaml` documents (`brew install yq` on macOS).
- `k8s-configs/base/custom-patches.yaml` must already exist.

### Usage

```bash
cp patch-nginx-snippet-annotations.sh <path-to-CSR>/
cd <path-to-CSR>
./patch-nginx-snippet-annotations.sh
```

### What it does

1. Scans all ingresses in the `ping-cloud` namespace for the four snippet annotations. If none are present, it exits without changes.
2. For each snippet-annotated ingress, reads its ingress class (`spec.ingressClassName` or the legacy `kubernetes.io/ingress.class` annotation) and maps it back to a controller namespace using the P1AS convention:

   | Ingress class | Controller namespace |
   |---|---|
   | `nginx-public` | `ingress-nginx-public` |
   | `nginx-private` | `ingress-nginx-private` |

   Only namespaces that actually serve a snippet-annotated ingress are considered — patching the other controller is skipped to avoid unnecessarily setting `annotations-risk-level: "Critical"` on it (which would widen the attack surface without justification). Snippet-annotated ingresses with no class set are flagged with a `WARNING` and skipped; determine which controller they belong to (set `spec.ingressClassName` or the legacy annotation on the ingress) and re-run.

3. For each in-scope namespace, checks the current `allow-snippet-annotations` and `annotations-risk-level` values on the `nginx-configuration` ConfigMap.
4. For each namespace where either value is not set correctly, writes only the missing/incorrect key(s) into `k8s-configs/base/custom-patches.yaml`:

   - **If a `ConfigMap/nginx-configuration` patch document for that namespace already exists**, the script merges the missing key(s) *in place* into that document (via `yq`). Any other keys the pre-existing patch sets (e.g., `http-snippet`, `proxy-buffer-size`) are preserved.
   - **If no such document exists**, a new document is appended, e.g.:

     ```yaml
     ---
     apiVersion: v1
     kind: ConfigMap
     metadata:
       name: nginx-configuration
       namespace: <ingress-nginx-public | ingress-nginx-private>
     data:
       annotations-risk-level: "Critical"
     ```

   The normal case is that `allow-snippet-annotations: "true"` is already applied as an earlier custom patch (otherwise nginx would be ignoring the snippet today), so only `annotations-risk-level: "Critical"` needs to be added.

After the script runs, review the diff on `custom-patches.yaml`, commit, push, and sync ArgoCD as described in the runbook.

> **Note:** The in-place merge means running the script twice is safe — it will not create duplicate documents. If two `nginx-configuration` documents already existed for the same namespace before the script ran (e.g., from manual edits), consolidate them by hand first: kustomize applies only the last matching document and discards keys from earlier ones.
