# Adding Component Patches to `base/kustomization.yaml`

These component patches are intended for scenarios where we need to temporarily increase resource sizing to address performance or stability issues. They provide a straightforward way to allocate additional capacity without requiring architectural changes.

### Steps

1. Open the `base/kustomization.yaml` file for your environment.  
2. Locate (or add) the `components:` section.  
3. Add the remote component patches you want to apply, using the GitHub repo path and optional `ref` for the branch/tag. For example:

```yaml
components:
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches/pingfederate?ref=pdo-10262
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches/pingaccess?ref=pdo-10262
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches/pingaccess-was?ref=pdo-10262
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches/nginx?ref=pdo-10262
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches/logstash?ref=pdo-10262
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches/fluent-bit?ref=pdo-10262
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches/pingdirectory?ref=pdo-10262
