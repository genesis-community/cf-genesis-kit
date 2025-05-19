# Runtime Stacks in Cloud Foundry

This guide covers the configuration and management of runtime stacks in Cloud Foundry deployments using the Genesis kit.

## Overview

Runtime stacks are the root filesystems that provide the base operating environment for applications running on Cloud Foundry. The CF Genesis kit currently supports:

- **CFLinuxFS3** - Based on Ubuntu Bionic 18.04 LTS
- **CFLinuxFS4** - Based on Ubuntu Jammy 22.04 LTS (Default as of kit version 2.5.0)

## Default Configuration

As of version 2.5.0 of the CF Genesis Kit, CFLinuxFS4 is the default and only included stack. CFLinuxFS3 must be explicitly enabled if needed.

## Enabling Runtime Stacks

### CFLinuxFS4 (Default)

CFLinuxFS4 is automatically included in all deployments, so no explicit configuration is needed.

### CFLinuxFS3 (Legacy)

To include CFLinuxFS3 support, add the `cflinuxfs3` feature to your environment:

```yaml
kit:
  features:
    - cflinuxfs3
```

This will deploy Diego cells with both CFLinuxFS4 and CFLinuxFS3 support, allowing you to run applications on either stack.

## Managing Multiple Stacks

When both stacks are enabled, you can specify which stack to use for an application:

```bash
# Deploy using CFLinuxFS3
cf push my-app -s cflinuxfs3

# Deploy using CFLinuxFS4 (default if not specified)
cf push my-app -s cflinuxfs4
```

## Stack Migration Strategy

### Preparing for Migration

Before migrating applications from CFLinuxFS3 to CFLinuxFS4:

1. **Enable both stacks** in your CF deployment:
   ```yaml
   kit:
     features:
       - cflinuxfs3
   ```

2. **Verify compatibility** of your applications with CFLinuxFS4:
   - Test applications on CFLinuxFS4 before full migration
   - Check for dependencies on Ubuntu 18.04 packages that may not be in Ubuntu 22.04
   - Test with the same memory allocations to ensure compatibility

3. **Update buildpacks** to the latest versions that support CFLinuxFS4

### Migration Process

For a gradual migration approach:

1. **Selective migration**:
   - Push new versions of applications specifying CFLinuxFS4 stack
   - Use blue-green deployment to validate before switching traffic
   ```bash
   cf push app-name-new -s cflinuxfs4
   ```

2. **Restage existing applications** to use CFLinuxFS4:
   ```bash
   cf push app-name -s cflinuxfs4
   ```
   
   Or use bulk migration through CF API or cf-mgmt tools.

3. **Monitor applications** after migration for any performance or compatibility issues

### Post-Migration Cleanup

Once all applications have been migrated to CFLinuxFS4:

1. **Verify no applications** are using CFLinuxFS3:
   ```bash
   cf stacks
   cf curl /v3/apps?per_page=1000 | jq -r '.resources[] | select(.lifecycle.data.stack=="cflinuxfs3") | .name'
   ```

2. **Remove CFLinuxFS3 support** from your deployment:
   - Remove the `cflinuxfs3` feature from your environment file
   - Redeploy CF

## Trusted Certificates with Different Stacks

When using trusted certificates with your applications, you need to configure them for each stack:

```yaml
kit:
  features:
    - cflinuxfs3
    - trust-blacksmith-ca  # If using Blacksmith-generated certificates

# Your certificates will be injected into both CFLinuxFS3 and CFLinuxFS4 runtimes
```

For OCFP deployments, use:

```yaml
kit:
  features:
    - ocfp
    - cflinuxfs3
    - trust-blacksmith-ca
```

Which will apply the trusted certificates to both stacks.

## Isolation Segments and Stacks

When using isolation segments with multiple stacks:

```yaml
kit:
  features:
    - isolation-segments
    - cflinuxfs3

params:
  isolation_segments:
    - name: isolated-segment-1
      # This segment will support both CFLinuxFS3 and CFLinuxFS4
```

## Upgrading from Previous Kit Versions

### From v1.x to v2.x

In v1.x of the kit, CFLinuxFS2 was the default stack. When upgrading from v1.x to v2.x:

1. The stack will automatically be updated to CFLinuxFS3
2. If your applications require CFLinuxFS2, they will need to be updated as it's no longer supported

### From v2.0-2.4 to v2.5+

In earlier v2.x versions, CFLinuxFS3 was the default stack. When upgrading to v2.5+:

1. CFLinuxFS4 becomes the default stack
2. Add the `cflinuxfs3` feature explicitly if you need to continue supporting CFLinuxFS3

## Troubleshooting

### Common Issues

1. **Application fails to start after stack change**:
   - Check compatibility of application dependencies with the new stack
   - Verify buildpack compatibility
   - Check for hardcoded paths or dependencies on specific Ubuntu versions

2. **Missing libraries in CFLinuxFS4**:
   - Some libraries available in CFLinuxFS3 may not be in CFLinuxFS4
   - Use container-supplied dependencies or vendor necessary libraries

3. **Performance differences**:
   - CFLinuxFS4 may perform differently than CFLinuxFS3
   - Adjust memory allocations if necessary
   - Monitor application performance after migration

## References

- [Official Cloud Foundry Stack Documentation](https://docs.cloudfoundry.org/devguide/deploy-apps/stacks.html)
- [CFLinuxFS4 Release Notes](https://github.com/cloudfoundry/cflinuxfs4/releases)