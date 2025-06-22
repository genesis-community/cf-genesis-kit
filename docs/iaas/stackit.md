# Deploying Cloud Foundry on Stackit

This guide covers deploying Cloud Foundry to [Stackit](https://stackit.de/), an IaaS provider based on OpenStack that was recently added to the CF Genesis Kit.

## Overview

Stackit is a German-based cloud platform operated by Schwarz IT. The CF Genesis Kit supports deploying to Stackit infrastructure similarly to OpenStack, with some Stackit-specific optimizations.

## Requirements

Before deploying to Stackit, you'll need:

1. A BOSH director targeting Stackit with the appropriate CPI
2. Network and security groups configured in Stackit
3. Appropriate quotas for resources
4. Cloud configuration for your BOSH director

## Configuration

### Base Environment Configuration

Create your environment file with the following settings:

```yaml
---
kit:
  name: cf
  version: 2.5.2
  features:
    - stackit  # This feature will be automatically included when deploying to Stackit

params:
  base_domain: your-cf-domain.stackit.example
  system_domain: system.((base_domain))
  apps_domains:
    - run.((system_domain))
  availability_zones: [z1, z2, z3]
  
  # Recommended VM types for Stackit
  # These should match your cloud config
  api_vm_type: stackit-medium
  cc_worker_vm_type: stackit-small
  credhub_vm_type: stackit-small
  diego_api_vm_type: stackit-small
  diego_cell_vm_type: stackit-xlarge
  doppler_vm_type: stackit-small
  log_api_vm_type: stackit-medium
  nats_vm_type: stackit-small
  router_vm_type: stackit-small
  tcp_router_vm_type: stackit-small
  uaa_vm_type: stackit-medium
```

### Blobstore Configuration

With Stackit, you have two main options for blobstore:

#### 1. Internal Blobstore (default for Stackit in OCFP mode)

The default deployment with OCFP feature on Stackit uses an internal blobstore:

```yaml
kit:
  features:
    - ocfp
    - internal-blobstore  # This is applied automatically with OCFP on Stackit
```

#### 2. External S3-Compatible Storage

If you prefer to use an external S3-compatible storage, such as Stackit's object storage:

```yaml
kit:
  features:
    - minio-blobstore

params:
  blobstore_minio_endpoint: https://your-stackit-storage-endpoint
```

Remember to set the necessary credentials in Credhub:

```bash
genesis do MY-ENV -- credhub set -n /YOUR-BOSH-ENV/MY-CF-ENV/blobstore_access_key_id -t value -v YOUR-ACCESS-KEY
genesis do MY-ENV -- credhub set -n /YOUR-BOSH-ENV/MY-CF-ENV/blobstore_secret_access_key -t value -v YOUR-SECRET-KEY
```

### OCFP Deployment on Stackit

For an opinionated deployment, use the OCFP feature which is well-suited for Stackit:

```yaml
kit:
  features:
    - ocfp

params:
  # OCFP Specific Settings
  ocfp_env_scale: dev  # Or 'prod' for production settings
```

## Networking

Stackit deployments follow a similar networking model to OpenStack. You can use either:

1. **Single Network**: All components on one network
2. **Partitioned Network**: Core, edge, and runtime components on separate networks

For partitioned networks, use:

```yaml
kit:
  features:
    - ocfp
    - partitioned-network
```

## Availability Zones

Stackit normally supports multiple availability zones. Configure your environment accordingly:

```yaml
params:
  availability_zones: [z1, z2, z3]
```

## Example Complete Environment File

```yaml
---
kit:
  name: cf
  version: 2.5.2
  features:
    - ocfp
    - internal-blobstore
    - partitioned-network
    - haproxy
    - tls
    - self-signed

params:
  # Basic configuration
  base_domain: cf-demo.stackit.example
  system_domain: system.((base_domain))
  apps_domains:
    - run.((system_domain))
    
  # Network settings  
  availability_zones: [z1, z2, z3]
  
  # OCFP configuration
  ocfp_env_scale: dev
  
  # HAProxy settings
  haproxy_instances: 2
  haproxy_ips: [10.0.10.10, 10.0.10.11]
```

## Cloud Config Requirements

Ensure your Stackit BOSH cloud config includes the following:

- VM types with appropriate resource configurations
- Disk types for database and blobstore
- Network definitions
- Cloud properties specific to Stackit

## Known Limitations

- The Stackit environment currently doesn't support dynamic service offerings directly through CF
- Some specialty VM types may have quota limitations

## Troubleshooting

### Common Issues

1. **Resource Quotas**: Ensure you have sufficient quotas allocated in your Stackit account
2. **Network Connectivity**: Verify that your security groups allow the necessary communication between components
3. **API Rate Limiting**: If you encounter API rate limiting, adjust your deployment timing or contact Stackit support

## References

- [Stackit Documentation](https://docs.stackit.de/)
- [BOSH OpenStack CPI Documentation](https://bosh.io/docs/openstack-cpi/)
