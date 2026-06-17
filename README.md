<!-- AI Generated -->
# p1as-eng-base-patches

Opt-in Kustomize [Component](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/components/) patches for PingOne Advanced Services (P1AS). Patches are organized by subsystem under `components/` and named with a version suffix matching their target P1AS release.

To apply a patch, add its path to the `components:` list in a CSR `kustomization.yaml`.

See the Confluence [Component Patch Homepage](https://pingidentity.atlassian.net/wiki/spaces/PDA/pages/1123516717/Component+Patch+Homepage) for full usage details.

## Available Patches

| Path | Description | Targeted P1AS Version(s) |
|-----------|-------------|----------|
| `karpenter/` | Updates EC2NodeClass AMI family to AL2023 | 2.1 |
| `logging/fluentbit_aws_patch_*` | Routes Fluent Bit logs to S3 via `amazon/aws-for-fluent-bit` | 1.19.2, 2.0, 2.1 |
| `logging/fluentbit_metrics_patch_*` | Adds Prometheus scrape annotations to Fluent Bit DaemonSet | 1.19.2, 2.0 |
| `logging/opensearch_ism_patch_*` | Deploys standard ISM policy (hot → warm at 30d → delete at 31d) | 1.19.2, 2.0 |
| `logging/opensearch_warm_nodes_patch_*` | Removes warm node pool; sets ISM audit retention to 45 days | 1.19.2, 2.0 |
| `logging/opensearch_drain_data_node_patch_*` | Enables `drainDataNodes` for graceful OpenSearch node removal | 1.19.2, 2.0 |
| `logging/opensearch_enable_auth_patch_*` | Configures authenticated Prometheus scraping of OpenSearch | 1.19.2, 2.0 |
| `logging/opensearch_alert_rbac_patch_*` | Applies RBAC config for OpenSearch alerting | 1.19.2, 2.0 |
| `logging/kube-rbac-proxy_*` | Enables kube-rbac-proxy on controller-manager | 1.19.2, 2.0 |
| `logging/osd_query_csv_patch_*` | Grants OSD users the ability to export queries as CSV | 1.19.2, 2.0 |
| `logging/osd_pf_unique_users_patch_*` | Adds PF unique-users dashboard; extends PF audit retention to 45 days | 1.19.2 |
| `network/nlb_heartbeat_patch_*` | Fixes missing NLB annotation and PingCentral heartbeat content-length (PDO-9671, PDO-9687) | 2.0 |
| `nginx/ingress_nginx_vuln_*` | Updates ingress controller to SigSci-enabled image; removes obsolete modsecurity annotations | 2.1.1 |
| `nginx_configmap_patch_*` | Configures ingress-nginx-public: SigSci module, worker tuning, upstream log format, SSL ciphers | 1.18, 1.19 |
| `remove_modsecurity_ingress_patch_*` | Removes modsecurity annotations from all ingress resources after ingress-nginx 1.14.4 upgrade | 2.2+ |
| `pingaccess/sync_admin_engine_certs_patch` | CronJob that detects admin cert changes and restarts engine pods to reload (PA and PA-WAS) | All |
| `sigsci_agent/` | Tunes SigSci sidecar CPU, nginx-ingress-controller resources, and HPA scaling | v1.19, 2.0.x, 2.1 |
| `xxl_patches_1_19/` | Increased resource limits/requests and HPA ranges for large-scale deployments across PF, PA, PD, nginx, Logstash, Fluent Bit, Prometheus | 1.19.2 |

## Contributing

See the Confluence [Component Patch Homepage](https://pingidentity.atlassian.net/wiki/spaces/PDA/pages/1123516717/Component+Patch+Homepage)