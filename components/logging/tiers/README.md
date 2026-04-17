# Tier-Based Configuration

> [!IMPORTANT]
> These tier patches are only applicable to Beluga release `2.3` and above.

These tier directories are packaged as Kustomize components so they can be
referenced from another repo under `components:`.

Example:

```yaml
components:
  - github.com/pingidentity/ping-cloud-base-patches//components/logging/tiers/tier3
```

Individual components can also be applied independently:

```yaml
components:
  - github.com/pingidentity/ping-cloud-base-patches//components/logging/tiers/tier3/fluentbit
  - github.com/pingidentity/ping-cloud-base-patches//components/logging/tiers/tier3/opensearch
  - github.com/pingidentity/ping-cloud-base-patches//components/logging/tiers/tier3/logstash
```

See the Tier-Based Configuration guide for details:

https://pingidentity.atlassian.net/wiki/spaces/PDA/pages/2731900990/Tier-Based+Configuration
