# Troubleshooting Cloud Foundry Deployments

This guide covers common issues and their solutions when deploying and operating Cloud Foundry with the Genesis kit.

## Deployment Issues

### Failed Deployment

#### Symptoms
- `genesis deploy` fails with BOSH errors
- Deployment reports failures in specific jobs or instance groups

#### Troubleshooting Steps

1. **Check BOSH logs** for the specific failure:
   ```bash
   genesis do MY-ENV -- bosh task-log
   ```

2. **Examine instance logs** for failing jobs:
   ```bash
   genesis do MY-ENV -- bosh -d cf logs FAILING_INSTANCE_GROUP
   ```

3. **Verify cloud config** matches your environment file:
   ```bash
   genesis do MY-ENV -- bosh cloud-config
   ```

4. **Check resource availability** on your IaaS to ensure you have sufficient quotas

#### Common Solutions

- If the error mentions missing VM types, update your cloud config
- If the error relates to network connectivity, check IaaS firewall and security group rules
- For compilation failures, increase CPU/memory of compilation VMs

### Blobstore Configuration Issues

#### Symptoms
- Deployment fails with errors about blobstore credentials or access
- Applications fail to stage or start after deployment succeeds

#### Troubleshooting Steps

1. **Verify credentials** are properly set in Credhub:
   ```bash
   genesis do MY-ENV -- credhub get -n /YOUR-BOSH-ENV/MY-CF-ENV/blobstore_access_key_id
   genesis do MY-ENV -- credhub get -n /YOUR-BOSH-ENV/MY-CF-ENV/blobstore_secret_access_key
   ```

2. **Check IaaS permissions** for the blobstore service account

3. **Verify endpoint configuration** for external blobstores:
   ```bash
   # For AWS S3
   genesis do MY-ENV -- bosh -d cf ssh api -c "curl -v BUCKET_ENDPOINT"
   
   # For Minio
   genesis do MY-ENV -- bosh -d cf ssh api -c "curl -v YOUR_MINIO_ENDPOINT"
   ```

#### Common Solutions

- Update credentials in Credhub if they've changed
- Adjust IAM permissions for the service account (for AWS/GCP)
- Verify network routes between CF and external blobstore

### Database Configuration Issues

#### Symptoms
- Deployment fails with database connectivity errors
- CF API/UAA/other components fail after successful deployment

#### Troubleshooting Steps

1. **Check database connectivity** from CF components:
   ```bash
   genesis do MY-ENV -- bosh -d cf ssh DATABASE_DEPENDENT_INSTANCE -c "telnet DB_HOST DB_PORT"
   ```

2. **Verify credentials** are correct in Credhub

3. **Check database status**:
   - For internal databases: `genesis do MY-ENV -- bosh -d cf ssh database/0 -c "sudo monit summary"`
   - For external databases: connect with appropriate client tool

#### Common Solutions

- Update database credentials in Credhub
- Adjust network security groups to allow database traffic
- For internal databases, ensure sufficient disk space is allocated

## Operational Issues

### Application Push Failures

#### Symptoms
- `cf push` commands fail
- Applications stay in "staging" state indefinitely

#### Troubleshooting Steps

1. **Check Diego Cell capacity**:
   ```bash
   cf curl /v2/info | jq .
   cf curl /v2/apps/$(cf app APP-NAME --guid)/stats | jq .
   ```

2. **Examine Diego Cell logs**:
   ```bash
   genesis do MY-ENV -- bosh -d cf logs diego-cell
   ```

3. **Check application logs**:
   ```bash
   cf logs APP-NAME --recent
   ```

#### Common Solutions

- Scale Diego cells if at capacity
- Update buildpacks if staging fails due to buildpack issues
- Check network connectivity if downloading dependencies fails

### Routing Issues

#### Symptoms
- Applications deploy successfully but are not accessible
- Intermittent 502/503 errors when accessing applications

#### Troubleshooting Steps

1. **Check Gorouter logs**:
   ```bash
   genesis do MY-ENV -- bosh -d cf logs router
   ```

2. **Verify route registration** in NATS:
   ```bash
   genesis do MY-ENV -- bosh -d cf ssh nats -c "grep -i route /var/vcap/sys/log/nats/nats.log | tail -n 100"
   ```

3. **Check load balancer configuration** for your IaaS

4. **Examine HAProxy configuration** if using the `haproxy` feature:
   ```bash
   genesis do MY-ENV -- bosh -d cf ssh haproxy -c "cat /var/vcap/jobs/haproxy/config/haproxy.config"
   ```

#### Common Solutions

- Restart Gorouter instances: `genesis do MY-ENV -- bosh -d cf restart router`
- Ensure load balancers are correctly configured for your IaaS
- Check security groups to allow traffic to/from Gorouter
- For TLS issues, verify certificate configuration

### UAA and Authentication Issues

#### Symptoms
- Users cannot log in
- Service brokers fail to authenticate
- `cf login` commands fail

#### Troubleshooting Steps

1. **Check UAA logs**:
   ```bash
   genesis do MY-ENV -- bosh -d cf logs uaa
   ```

2. **Verify UAA is running**:
   ```bash
   genesis do MY-ENV -- bosh -d cf instances
   curl -k https://uaa.SYSTEM_DOMAIN/info
   ```

3. **Check UAA database connectivity**:
   ```bash
   genesis do MY-ENV -- bosh -d cf ssh uaa -c "telnet DB_HOST DB_PORT"
   ```

#### Common Solutions

- Restart UAA instances: `genesis do MY-ENV -- bosh -d cf restart uaa`
- Ensure database connectivity for UAA
- Check for expired certificates and rotate if needed

### Diego Cell Issues

#### Symptoms
- Applications crash or restart frequently
- High CPU or memory usage on Diego cells
- Slow application scaling

#### Troubleshooting Steps

1. **Check cell capacity**:
   ```bash
   genesis do MY-ENV -- bosh -d cf ssh diego-cell -c "garden-shed gc"
   genesis do MY-ENV -- bosh -d cf ssh diego-cell -c "df -h"
   ```

2. **Examine cell logs**:
   ```bash
   genesis do MY-ENV -- bosh -d cf logs diego-cell
   ```

3. **Check container metrics**:
   ```bash
   cf curl /v2/apps/$(cf app APP-NAME --guid)/stats | jq .
   ```

#### Common Solutions

- Scale Diego cells horizontally by adding more instances
- Increase Diego cell VM resources (CPU/memory)
- Clean up unused app artifacts: `cf curl -X POST /v2/apps/$(cf app APP-NAME --guid)/instances`

## Feature-Specific Issues

### Isolation Segments Issues

#### Symptoms
- Applications don't deploy to specified isolation segments
- Isolation segment Diego cells don't register correctly

#### Troubleshooting Steps

1. **Verify segment was created in CF**:
   ```bash
   cf isolation-segments
   ```

2. **Check segment is enabled for org**:
   ```bash
   cf org ORG-NAME --isolation-segment
   ```

3. **Verify Diego cells are tagged correctly**:
   ```bash
   genesis do MY-ENV -- bosh -d cf ssh diego-cell -c "grep -i placement_tag /var/vcap/jobs/rep/config/config.json"
   ```

#### Common Solutions

- Create and enable the isolation segment in CF after deployment
- Ensure placement tags match between CF and BOSH configuration
- Check for network connectivity issues between segments and core CF

### OCFP Deployment Issues

#### Symptoms
- OCFP deployment fails with feature conflicts
- Network or VM type errors with OCFP

#### Troubleshooting Steps

1. **Check for feature conflicts**:
   ```bash
   grep -r "features:" YOUR_ENV_FILE
   ```

2. **Verify IaaS-specific configurations**:
   ```bash
   genesis do MY-ENV -- bosh cloud-config
   ```

3. **Examine BOSH deployment errors**:
   ```bash
   genesis do MY-ENV -- bosh task-log
   ```

#### Common Solutions

- Remove conflicting features (OCFP manages many features automatically)
- Ensure cloud config has the required VM types for your IaaS
- Use `internal-blobstore` or `internal-db` features if having external service issues

### Volume Services Issues

#### Symptoms
- Applications can't mount volumes
- Volume service broker fails to start

#### Troubleshooting Steps

1. **Check volume service broker status**:
   ```bash
   cf service-brokers
   cf service-access
   ```

2. **Examine volume driver logs on Diego cells**:
   ```bash
   genesis do MY-ENV -- bosh -d cf ssh diego-cell -c "cat /var/vcap/sys/log/nfsv3-driver/nfsv3-driver.log"
   ```

3. **Verify LDAP configuration** (if using nfs-ldap):
   ```bash
   genesis do MY-ENV -- bosh -d cf ssh diego-cell -c "cat /var/vcap/jobs/nfsv3-driver/config/ldap.json"
   ```

#### Common Solutions

- Create service offerings after deployment
- For LDAP issues, verify credentials and connectivity
- Check networking between Diego cells and NFS/SMB servers

## Advanced Troubleshooting

### BOSH Recovery Commands

```bash
# Force recreate problematic instances
genesis do MY-ENV -- bosh -d cf recreate INSTANCE_GROUP/INDEX

# Stop and start instances or entire deployment
genesis do MY-ENV -- bosh -d cf stop --hard
genesis do MY-ENV -- bosh -d cf start

# Run BOSH cloud check to detect and fix infrastructure issues
genesis do MY-ENV -- bosh -d cf cloud-check
```

### Accessing System Logs

```bash
# Stream all component logs
genesis do MY-ENV -- bosh -d cf logs

# Get recent logs for a specific component
genesis do MY-ENV -- bosh -d cf logs INSTANCE_GROUP/INDEX --recent

# Follow logs for a specific component
genesis do MY-ENV -- bosh -d cf logs INSTANCE_GROUP/INDEX -f
```

### Database Inspection

```bash
# Connect to internal database
genesis do MY-ENV -- bosh -d cf ssh database -c "sudo su - vcap -c '/var/vcap/packages/postgres-X.Y.Z/bin/psql -p 5524 -U vcap ccdb'"

# Inspect UAA database tables
SELECT * FROM users LIMIT 10;
SELECT * FROM identity_zone LIMIT 10;
```

## Contacting Support

If you've tried the troubleshooting steps and still have issues:

1. Gather system information:
   ```bash
   genesis do MY-ENV -- info > cf-info.txt
   genesis do MY-ENV -- bosh -d cf instances --vitals > instances-vitals.txt
   genesis do MY-ENV -- bosh -d cf logs --only "api/0,uaa/0,router/0,diego-cell/0" > key-components.log
   ```

2. Create a detailed issue on the [CF Genesis Kit GitHub repository](https://github.com/genesis-community/cf-genesis-kit/issues) with:
   - Environment configuration (redact secrets)
   - Error logs and output
   - Steps to reproduce the issue
   - Information gathered from the commands above