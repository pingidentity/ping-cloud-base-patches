# ingress-nginx Vulnerability Patch (K000161019) — P1AS v2.1.2

Addresses CVE K000161019 for customers on P1AS `v2.1.2` by:

- Updating the `nginx-ingress-controller` image (both public and private) to the Chainguard-based fork `v2.1.2-RC1`, which does not contain the vulnerability
- Removing modsecurity annotations from the `pingaccess-was-ingress` ingress object

## Usage

1. Open the `k8s-configs/base/kustomization.yaml` file for your environment.
2. Locate (or add) the `components:` section.
3. Add the following:

```yaml
components:
  - github.com/pingidentity/ping-cloud-base-patches//components/nginx/ingress_nginx_vuln_2_1_2
```

When testing, you may also add the branch name as shown below.

```yaml
components:
  - github.com/pingidentity/ping-cloud-base-patches//components/nginx/ingress_nginx_vuln_2_1_2?ref=PDO-12637
```

4. Sync ArgoCD in all regions.

## What it patches

| Resource | Namespace | Change |
|---|---|---|
| `Deployment/nginx-ingress-controller` | `ingress-nginx-private` | Updates image to Chainguard fork `v2.1.2-RC1` |
| `Deployment/nginx-ingress-controller` | `ingress-nginx-public` | Updates image to Chainguard fork `v2.1.2-RC1` |
| `Ingress/pingaccess-was-ingress` | `ping-cloud` | Removes `enable-modsecurity` and `modsecurity-snippet` annotations |
