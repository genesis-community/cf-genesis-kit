# Isolation Segments in Cloud Foundry

This guide covers the configuration and management of isolation segments in Cloud Foundry deployments using the Genesis kit.

## Overview

Isolation segments provide a way to dedicate a set of Diego cells to specific applications or organizations, ensuring workload separation and multi-tenancy. They are particularly useful for:

- Isolating workloads with different security requirements
- Dedicating compute resources to specific tenants or applications
- Providing different runtime characteristics (CPU, memory, networking) to different workloads
- Implementing regulatory compliance requirements

## Enabling Isolation Segments

To enable isolation segments in your CF deployment, add the `isolation-segments` feature to your environment:

```yaml
kit:
  features:
    - isolation-segments
```

## Configuring Isolation Segments

Each isolation segment requires configuration in your environment file. At minimum, you need to specify a name:

```yaml
params:
  isolation_segments:
    - name: segment-1
```

### Full Configuration Options

For more control, you can specify additional parameters for each segment:

```yaml
params:
  isolation_segments:
    - name: high-performance
      instances: 3
      azs: [z1, z2]
      vm_type: large-highmem
      vm_extensions: [ 100GB_ephemeral_disk ]
      network_name: cf-runtime
      stemcell: default
      # Optional: specify placement tags
      tag: high-performance  # Default tag is the same as the name
      # You can also specify multiple tags (overrides 'tag')
      tags: 
        - high-performance
        - production
      # Optional: additional trusted certificates
      additional_trusted_certs:
        - |
          -----BEGIN CERTIFICATE-----
          MIIDXTCCAkWgAwIBAgIJAJC1HiIAZAiIMA0GCSqGSIb3DQEBCwUAMEUxCzAJBgNV
          ...certificate contents...
          Pfx/eDRQs+K3KQyQ=
          -----END CERTIFICATE-----
```

The parameters available are:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `name` | Name of the isolation segment (required) | |
| `azs` | Availability zones for the segment | [z1, z2] or inherits from params.availability_zones |
| `instances` | Number of Diego cell instances | 1 |
| `vm_type` | VM type for the Diego cells | Inherits from params.diego_cell_vm_type or "small-highmem" |
| `vm_extensions` | VM extensions to apply | [ 100GB_ephemeral_disk ] |
| `network_name` | Network to place VMs in | params.cf_runtime_network or "default" |
| `stemcell` | Stemcell to use | "default" |
| `tag` | Placement tag for the isolation segment | Same as name |
| `tags` | Multiple placement tags (overrides tag) | |
| `additional_trusted_certs` | Additional CA certificates to trust | |

## Managing Multiple Isolation Segments

You can define multiple isolation segments in your environment:

```yaml
params:
  isolation_segments:
    - name: development
      instances: 1
      vm_type: small
    
    - name: production
      instances: 3
      vm_type: large-highmem
      azs: [z1, z2, z3]
    
    - name: regulated
      instances: 2
      vm_type: medium
      tags:
        - regulated
        - pci-compliant
```

## Integrating with Other Features

### Volume Services with Isolation Segments

To enable NFS volume services in isolation segments:

```yaml
kit:
  features:
    - isolation-segments
    - nfs-volume-services
```

For LDAP authentication with NFS:

```yaml
kit:
  features:
    - isolation-segments
    - nfs-volume-services
    - nfs-ldap  # or nfs-ldap-tls for TLS connections
```

### SMB Volume Services with Isolation Segments

```yaml
kit:
  features:
    - isolation-segments
    - smb-volume-services
```

### Runtime Stack Support

By default, isolation segments use CFLinuxFS4. To add CFLinuxFS3 support:

```yaml
kit:
  features:
    - isolation-segments
    - cflinuxfs3
```

### Trusted Certificates

To add trusted certificates to isolation segments:

```yaml
params:
  isolation_segments:
    - name: secure-segment
      additional_trusted_certs:
        - |
          -----BEGIN CERTIFICATE-----
          MIIDXTCCAkWgAwIBAgIJAJC1HiIAZAiIMA0GCSqGSIb3DQEBCwUAMEUxCzAJBgNV
          ...certificate contents...
          Pfx/eDRQs+K3KQyQ=
          -----END CERTIFICATE-----
```

Or use the `trust-blacksmith-ca` feature to automatically include Blacksmith-generated certificates:

```yaml
kit:
  features:
    - isolation-segments
    - trust-blacksmith-ca
```

## Post-Deployment Configuration

After deploying, you need to:

1. **Create the isolation segment in CF**:
   ```bash
   cf create-isolation-segment SEGMENT_NAME
   ```

2. **Enable the isolation segment for an organization**:
   ```bash
   cf enable-org-isolation ORG_NAME SEGMENT_NAME
   ```

3. **Set the default isolation segment for an organization** (optional):
   ```bash
   cf set-org-default-isolation-segment ORG_NAME SEGMENT_NAME
   ```

4. **Set the default isolation segment for a space** (optional):
   ```bash
   cf set-space-isolation-segment SPACE_NAME SEGMENT_NAME
   ```

## Deployment Examples

### Basic Isolation Segment

```yaml
kit:
  features:
    - isolation-segments

params:
  isolation_segments:
    - name: untrusted
```

### Production Multi-Segment Setup

```yaml
kit:
  features:
    - isolation-segments
    - nfs-volume-services
    - cflinuxfs3

params:
  isolation_segments:
    - name: general
      instances: 3
      vm_type: large
      
    - name: high-security
      instances: 2
      vm_type: large-highmem
      network_name: restricted-network
      tags:
        - high-security
        - encrypted
      
    - name: legacy
      instances: 1
      vm_type: medium
```

### OCFP with Isolation Segments

```yaml
kit:
  features:
    - ocfp
    - isolation-segments
    - trust-blacksmith-ca

params:
  ocfp_env_scale: prod
  
  isolation_segments:
    - name: customer-a
      instances: 2
    
    - name: customer-b
      instances: 2
```

## Troubleshooting

### Common Issues

1. **Apps not routing to isolation segment**:
   - Verify the isolation segment was created with `cf isolation-segments`
   - Check that it was enabled for the organization
   - Ensure the space or organization has the isolation segment set as default, or specify it when pushing the app

2. **Placement tag issues**:
   - Verify the `tag` or `tags` parameter matches what you're using in CF
   - Check the Diego cell logs for placement errors

3. **Network connectivity**:
   - Isolation segment Diego cells must be able to communicate with core CF components
   - Verify network connectivity between all components

4. **Volume services not working in isolation segment**:
   - Ensure the appropriate volume service features are enabled alongside isolation-segments
   - Check that drivers are properly installed on isolation segment Diego cells

## References

- [Official Cloud Foundry Isolation Segments Documentation](https://docs.cloudfoundry.org/adminguide/isolation-segments.html)
- [Isolation Segments API Documentation](https://v3-apidocs.cloudfoundry.org/version/3.102.0/index.html#isolation-segments)