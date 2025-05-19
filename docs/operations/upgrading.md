# Upgrading and Migrating Cloud Foundry Deployments

This guide covers the processes for upgrading your Cloud Foundry deployment between different versions of the CF Genesis Kit.

## General Upgrade Process

Before upgrading between any versions of the CF Genesis Kit, follow these general best practices:

1. **Backup your data**:
   ```bash
   genesis do MY-ENV -- bbr backup
   ```

2. **Review release notes** for the target version

3. **Update the kit**:
   ```bash
   # In your Genesis deployment repository
   genesis fetch-kit cf/NEW_VERSION
   ```

4. **Check for required changes**:
   ```bash
   genesis check-secrets MY-ENV
   ```

5. **Deploy with increased verbosity**:
   ```bash
   genesis deploy -v MY-ENV
   ```

6. **Verify the deployment**:
   ```bash
   genesis do MY-ENV -- smoketest
   ```

## Migrating from v1.x to v2.x

The v2.x releases of the CF Genesis Kit represent a major architectural change, moving from a custom manifest generation to being based on the community standard [cf-deployment](https://github.com/cloudfoundry/cf-deployment).

### Pre-Migration Steps

1. **Backup your environment files and data**:
   ```bash
   # Backup environment file
   cp MY-ENV.yml MY-ENV-v1-backup.yml
   
   # Backup deployment data
   genesis do MY-ENV -- bbr backup
   ```

2. **Check current version and features**:
   ```bash
   genesis info MY-ENV
   ```

3. **Note your current configuration**, particularly:
   - Database configurations
   - Blobstore settings
   - Network configurations
   - Custom operations files

### Migration Process

1. **Update the kit to v2.x**:
   ```bash
   # In your Genesis deployment repository
   genesis fetch-kit cf/2.5.2  # Use the latest 2.x version
   ```

2. **Add migration feature flag**:
   ```yaml
   # Add to your environment file
   kit:
     features:
       - +migrated-v1-env  # This special flag helps with v1->v2 migrations
   ```

3. **Update database configuration** if needed:
   ```yaml
   # For v1 environments using internal postgres
   kit:
     features:
       - local-postgres-db
       
   # For v1 environments using external MySQL
   kit:
     features:
       - mysql-db
       
   # For v1 environments using external Postgres
   kit:
     features:
       - postgres-db
   ```

4. **Update blobstore configuration**:
   ```yaml
   # For v1 internal WebDAV blobstore
   # No specific action needed, this is migrated automatically
   
   # For v1 S3 blobstore
   kit:
     features:
       - aws-blobstore
       
   # For v1 Azure blobstore
   kit:
     features:
       - azure-blobstore
       
   # For v1 GCP blobstore
   kit:
     features:
       - gcp-blobstore
   ```

5. **Map v1 custom features** to v2 features:
   
   | v1 Feature | v2 Equivalent |
   |------------|---------------|
   | `haproxy` | `haproxy` |
   | `tls` | `tls` |
   | `self-signed` | `self-signed` |
   | `tiny` | `small-footprint` |
   | `nfs-volume-service` | `nfs-volume-services` |
   | `nfs-ldap` | `nfs-volume-services` + `nfs-ldap` |

6. **Verify DB name overrides** (if used):
   ```yaml
   # If you used custom DB names in v1
   kit:
     features:
       - +override-db-names
       
   params:
     uaadb_name: your_custom_uaa_db_name
     # ...other custom DB names
   ```

7. **Deploy with increased verbosity**:
   ```bash
   genesis deploy -v MY-ENV
   ```

### Post-Migration Tasks

1. **Verify all applications are running**:
   ```bash
   cf login -a https://api.YOUR_SYSTEM_DOMAIN
   cf apps
   ```

2. **Run smoke tests**:
   ```bash
   genesis do MY-ENV -- smoketest
   ```

3. **Check for any migration-specific warnings** in the deployment output

4. **Consider removing the migration flag** after a successful migration:
   ```yaml
   kit:
     features:
       # - +migrated-v1-env  # Remove this line after successful migration
   ```

## Upgrading from v2.0.x to v2.5.x

The v2.5.x releases introduce important changes, particularly around runtime stacks (changing from cflinuxfs3 to cflinuxfs4 as default).

### Pre-Upgrade Steps

1. **Backup your data**:
   ```bash
   genesis do MY-ENV -- bbr backup
   ```

2. **Check application compatibility** with cflinuxfs4 (Ubuntu 22.04)

3. **Update the kit**:
   ```bash
   genesis fetch-kit cf/2.5.2
   ```

### Key Changes to Address

1. **Runtime stack changes**:
   
   In v2.5.x, cflinuxfs4 is the default and only included stack. If you need to continue supporting cflinuxfs3, add:
   
   ```yaml
   kit:
     features:
       - cflinuxfs3
   ```

2. **New IaaS providers**:
   
   Support for Stackit has been added. No changes are needed unless migrating to Stackit.

3. **Check for deprecated features or parameters**:
   
   Review the release notes for any deprecated items.

### Post-Upgrade Tasks

1. **Run smoke tests**:
   ```bash
   genesis do MY-ENV -- smoketest
   ```

2. **Plan for application migrations** to cflinuxfs4 if needed

## Upgrading OCFP Deployments

OCFP (OpenSource Cloud Foundry Platform) deployments have special considerations.

### Pre-Upgrade Steps for OCFP

1. **Backup your OCFP deployment**:
   ```bash
   genesis do MY-ENV -- bbr backup
   ```

2. **Check current OCFP configuration**:
   ```bash
   genesis info MY-ENV
   ```

3. **Note any custom OCFP features** you have enabled

### OCFP Upgrade Process

1. **Update the kit**:
   ```bash
   genesis fetch-kit cf/2.5.2
   ```

2. **Review OCFP-specific changes** in the release notes

3. **Deploy with increased verbosity**:
   ```bash
   genesis deploy -v MY-ENV
   ```

### Post-Upgrade Tasks for OCFP

1. **Verify all OCFP features are working**:
   ```bash
   # Check if UAA admin client is working
   cf login -a https://api.YOUR_SYSTEM_DOMAIN
   
   # Test service brokers if applicable
   cf service-brokers
   ```

2. **Run smoke tests**:
   ```bash
   genesis do MY-ENV -- smoketest
   ```

## Troubleshooting Upgrade Issues

### Common Migration Issues

1. **Database migration errors**:
   - Verify database credentials in Credhub
   - Check connectivity to external databases
   - For internal databases, ensure sufficient disk space

2. **Blobstore access issues**:
   - Verify blobstore credentials in Credhub
   - For external blobstores, check IaaS permissions
   - For AWS S3, ensure policy allows required operations

3. **Certificate expiration**:
   - Check for expired certificates during upgrade
   - Rotate certificates if needed before upgrading

4. **Instance count mismatches**:
   - Adjust instance counts to match your desired configuration
   - Note that default instance counts may change between versions

### Recovery Steps

If the upgrade fails, you can attempt to recover:

1. **Return to the previous version**:
   ```bash
   genesis fetch-kit cf/PREVIOUS_VERSION
   genesis deploy MY-ENV
   ```

2. **Restore from backup** if necessary:
   ```bash
   genesis do MY-ENV -- bbr restore --artifact-path PATH_TO_BACKUP
   ```

3. **Try incremental upgrades** for major version changes:
   - For v1.x to v2.x, consider upgrading to the latest v1.x first
   - Then upgrade to an early v2.x version
   - Finally upgrade to the target version

## Special Topics

### Migrating Between Database Types

1. **Backup your current database**:
   ```bash
   genesis do MY-ENV -- bbr backup
   ```

2. **Update your environment file** with the new database features:
   ```yaml
   kit:
     features:
       # Remove old database feature
       # - local-postgres-db
       
       # Add new database feature
       - mysql-db
   
   # Add any required parameters for the new database
   params:
     external_db_host: YOUR_DB_HOST
     external_db_port: 3306
   ```

3. **Set up credentials** in Credhub:
   ```bash
   genesis do MY-ENV -- credhub set -n /YOUR-BOSH-ENV/MY-CF-ENV/external_db_password -t password -w YOUR_PASSWORD
   ```

4. **Deploy with increased verbosity**:
   ```bash
   genesis deploy -v MY-ENV
   ```

### Migrating Between Blobstore Types

1. **Backup your current blobstore data**:
   ```bash
   genesis do MY-ENV -- bbr backup
   ```

2. **Update your environment file** with the new blobstore features:
   ```yaml
   kit:
     features:
       # Remove old blobstore feature
       # - internal-blobstore
       
       # Add new blobstore feature
       - azure-blobstore
   
   # Add any required parameters for the new blobstore
   params:
     azure_environment: AzureCloud
   ```

3. **Set up credentials** in Credhub:
   ```bash
   genesis do MY-ENV -- credhub set -n /YOUR-BOSH-ENV/MY-CF-ENV/blobstore_storage_account_name -t value -v YOUR_ACCOUNT_NAME
   genesis do MY-ENV -- credhub set -n /YOUR-BOSH-ENV/MY-CF-ENV/blobstore_storage_access_key -t password -w YOUR_ACCESS_KEY
   ```

4. **Deploy with increased verbosity**:
   ```bash
   genesis deploy -v MY-ENV
   ```

5. **Manually migrate data** between blobstores if needed

## References

- [Cloud Foundry Deployment Documentation](https://github.com/cloudfoundry/cf-deployment)
- [BBR Documentation](https://docs.cloudfoundry.org/bbr/index.html)
- [Genesis Documentation](https://genesisproject.io/docs/)
- [CF Release Notes](https://github.com/cloudfoundry/cf-deployment/releases)