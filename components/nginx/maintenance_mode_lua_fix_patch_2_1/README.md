# Maintenance Mode Lua Snippet Fix — P1AS v2.1+

Fixes ingress-nginx config reload failures (`[emerg] Lua code block missing the closing long bracket "]]"`) that occur when the number of ingress hosts grows large (observed at ~100+ hosts).

## Root cause

The controller's config indenter (`cleanConf` in `internal/ingress/controller/template/template.go`) treats `#` as a comment marker even inside Lua long-bracket `[[ ]]` strings. The maintenance-mode HTML page in the `ingress-nginx-public` `location-snippet` contained `#` CSS hex colors, so each rendered server block leaked one indentation level. Indentation depth scales with ingress host count, and once the indented `access_by_lua_block` exceeds nginx's 4096-byte config token buffer, every reload fails and the controller crashloops.

Replacing the hex colors with `rgb()` values removes the `#` characters from the Lua string, so the re-indenter's depth tracking stays correct regardless of host count.

## Usage

1. Open the `k8s-configs/base/kustomization.yaml` file for your environment.
2. Locate (or add) the `components:` section.
3. Add the following:

```yaml
components:
  - github.com/pingidentity/ping-cloud-base-patches//components/nginx/maintenance_mode_lua_fix_patch_2_1
```

When testing, you may also add the branch name as shown below.

```yaml
components:
  - github.com/pingidentity/ping-cloud-base-patches//components/nginx/maintenance_mode_lua_fix_patch_2_1?ref=pdo-12367
```

4. Sync ArgoCD in all regions.

## What it patches

| Resource | Namespace | Change |
|---|---|---|
| `ConfigMap/nginx-configuration` | `ingress-nginx-public` | Replaces `location-snippet` with a version whose maintenance-mode CSS uses `rgb()` values instead of `#` hex colors. No other keys are modified. |

## Notes

- The private controller's `location-snippet` (heartbeat-only) contains no `#` inside Lua strings and is not affected; it is intentionally left untouched.
- Keep this rule in mind for future snippet edits: never use `#` inside `[[ ]]` string literals in `location-snippet`/`server-snippet` values.
