# OCFP (OpenSource Cloud Foundry Platform) Deployments

The OCFP (OpenSource Cloud Foundry Platform) feature provides a highly opinionated deployment configuration for Cloud Foundry that applies best practices tailored to each supported infrastructure provider.

## Overview

OCFP simplifies Cloud Foundry deployments by making smart, infrastructure-aware decisions about configuration. Instead of requiring operators to understand and configure numerous options, OCFP provides a curated deployment experience with sane defaults and optimizations for each IaaS.

Key benefits:
- Preconfigured for optimal performance on each IaaS
- Simplified deployment experience
- Consistent architecture across environments
- Built-in best practices

## Enabling OCFP

To use OCFP, add it to your features list in your environment file:

```yaml
kit:
  features:
    - ocfp
```

## Infrastructure-specific Configurations

OCFP automatically applies appropriate configurations based on your infrastructure:

### AWS

```yaml
kit:
  features:
    - ocfp
    # AWS blobstore is automatically selected
```

OCFP on AWS will:
- Use AWS S3 for blobstore
- Configure appropriate security group settings
- Set up load balancers correctly
- Optimize deployment for AWS networking

### Azure

```yaml
kit:
  features:
    - ocfp
    # Azure blobstore is automatically selected
```

OCFP on Azure will:
- Use Azure Blob Storage
- Configure availability sets
- Optimize for Azure's network model

### GCP

```yaml
kit:
  features:
    - ocfp
    # GCP blobstore is automatically selected
```

OCFP on GCP will:
- Use Google Cloud Storage
- Configure appropriate network tags
- Optimize for GCP's networking model

### vSphere

```yaml
kit:
  features:
    - ocfp
    # MinIO blobstore is automatically selected
```

OCFP on vSphere will:
- Use MinIO for blobstore
- Configure appropriate resource pools
- Optimize for vSphere's networking model

### OpenStack/Stackit

```yaml
kit:
  features:
    - ocfp
    # Internal blobstore is automatically selected
```

OCFP on OpenStack/Stackit will:
- Use internal blobstore
- Configure appropriate security groups
- Optimize for OpenStack's networking model

## Deployment Scale

OCFP supports two deployment scales:

### Development Scale

```yaml
params:
  ocfp_env_scale: dev  # Default if not specified
```

Development scale provides:
- Smaller instance counts
- Lower resource utilization
- Suitable for development or test environments

### Production Scale

```yaml
params:
  ocfp_env_scale: prod
```

Production scale provides:
- Higher instance counts for HA
- Larger resource allocations
- Optimized for production workloads

## Network Configuration

By default, OCFP uses a single network for all components. For environments that need network separation, use the `split-network` feature:

```yaml
kit:
  features:
    - ocfp
    - split-network
```

This will create separate networks for:
- Core CF components
- Edge components (routers, etc.)
- Runtime components (Diego cells)
- Database components

## Database Options

By default, OCFP will use:
- Local PostgreSQL database for most infrastructures
- External database integration for certain IaaS providers

To explicitly use an internal database:

```yaml
kit:
  features:
    - ocfp
    - internal-db
```

To use an external database:

```yaml
kit:
  features:
    - ocfp
    # External DB is automatically configured
```

## SSL/TLS Configuration

OCFP supports custom SSL certificates. To provide your own certificates:

```yaml
params:
  router-ssl-path: /path/to/certificates  # Path to the user-provided certificate and key
```

Without this parameter, OCFP will generate self-signed certificates.

## Additional Features Compatible with OCFP

OCFP works well with these additional features:

```yaml
kit:
  features:
    - ocfp
    - trust-blacksmith-ca        # Trust CA certificates from Blacksmith
    - stratos-integration        # Include Stratos console
    - app-autoscaler-integration # Include app autoscaler
    - app-scheduler-integration  # Include app scheduler
    - scs-integration            # Include Spring Cloud Services
    - prometheus-integration     # Include Prometheus metrics
    - nfs-volume-services        # Include NFS volume service
    - nfs-ldap                   # Add LDAP support to NFS
    - smb-volume-services        # Include SMB volume service
    - windows-diego-cells        # Add Windows Diego cells
    - cflinuxfs3                 # Add cflinuxfs3 stack support
```

## Complete Example: OCFP on AWS

```yaml
---
kit:
  name: cf
  version: 2.5.2
  features:
    - ocfp
    - split-network
    - haproxy
    - tls
    - trust-blacksmith-ca
    - app-autoscaler-integration

params:
  # Basic configuration
  base_domain: example.com
  system_domain: system.((base_domain))
  apps_domains:
    - run.((system_domain))
    
  # Network settings  
  availability_zones: [z1, z2, z3]
  
  # OCFP configuration
  ocfp_env_scale: prod
  
  # HAProxy settings
  haproxy_ips: [10.0.10.10, 10.0.10.11]
```

## Limitations and Considerations

- OCFP is opinionated and may not suit all customization needs
- Some advanced configurations may not be compatible with OCFP
- Switching to/from OCFP after initial deployment may require careful migration

## Troubleshooting

### Common Issues

1. **Feature Compatibility**: Not all features are compatible with OCFP. If you encounter errors about incompatible features, review the features list.

2. **Network Configuration**: If using `split-network`, ensure your cloud config has the correct networks defined.

3. **Resource Allocation**: Production scale may require more resources than are available in your infrastructure. Consider using `ocfp_env_scale: dev` for smaller environments.