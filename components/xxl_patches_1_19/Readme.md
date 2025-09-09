# Adding Component Patches to `base/kustomization.yaml`

These component patches are intended for scenarios where we need to temporarily increase resource sizing to address performance or stability issues. They provide a straightforward way to allocate additional capacity without requiring architectural changes.
So far the following has only been tested against P1AS v1.19.2.0

### Steps

1. Open the `base/kustomization.yaml` file for your environment.  
2. Locate (or add) the `components:` section.  
3. Add the remote component patches you want to apply, using the GitHub repo path and optional `ref` for the branch/tag. For example:

```yaml
components:
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches_1_19/pingfederate?ref=pdo-10262
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches_1_19/pingaccess?ref=pdo-10262
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches_1_19/pingaccess-was?ref=pdo-10262
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches_1_19/nginx?ref=pdo-10262
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches_1_19/logstash?ref=pdo-10262
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches_1_19/fluent-bit?ref=pdo-10262
  - github.com/pingidentity/ping-cloud-base-patches//components/xxl_patches_1_19/pingdirectory?ref=pdo-10262
