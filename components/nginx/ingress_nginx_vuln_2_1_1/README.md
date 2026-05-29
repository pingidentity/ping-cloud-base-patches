# ingress-nginx Vulnerability Patch (K000161019) — P1AS v2.1.1

Addresses CVE K000161019 for customers on P1AS `v2.1.1` by:

- Updating the `nginx-ingress-controller` image (both public and private) to the Chainguard-based fork without the vulnerability
- Removing modsecurity annotations from the `pingaccess-was-ingress` ingress object

## Usage

1. Open the `base/kustomization.yaml` file for your environment.
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

## What it patches

| Resource | Namespace | Change |
|---|---|---|
| `Deployment/nginx-ingress-controller` | `ingress-nginx-private` | Updates image to Chainguard fork |
| `Deployment/nginx-ingress-controller` | `ingress-nginx-public` | Updates image to Chainguard fork |
| `Ingress/pingaccess-was-ingress` | `ping-cloud` | Removes `enable-modsecurity` and `modsecurity-snippet` annotations |
