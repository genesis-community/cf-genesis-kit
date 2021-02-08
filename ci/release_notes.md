# DO NOT USE NOTES!!
## upgrade from v12.45.0 to v15.7.0

## note worthy!!!
- New Feature Service Discovery is enabled by default.

  `operations/enable-service-discovery.yml`	Inlined into manifest and emptied this ops file. see Manifest Updates section on the service discovery feature

- Fixed cc_deployment_updater issue where it always refers to only one MySQL instance even if the ccdb is scaled out. The change updates cc_deployment_updater to refer to CCDB using BOSH DNS record sql-db.service.cf.internal

- Breaking Changes
This release re-defines all certificates to define a set of subject alternative names that at least includes the common name, as mandated by changes in Golang 1.15. As a result, if you generate your own deployment certificates, you must ensure they include the common name in the list of subject alternative names. If you are using a BOSH-deployed Credhub instance to manage your credentials, please ensure that you are running at least v270.4.0 of BOSH, which includes support for the per-variable update_mode option.

- Added support for the new (pre 1.0) bionic stemcell by way of an experimental ops file

- `Defaults to syslog agents and remove syslog adapters`

	Replaces the scalable syslog architecture with the shared-nothing syslog architecture. This architecture is more efficient and will enable the usage of the aggregate drains feature.  This change adds two new add-ons to every VM in Cloud Foundry. Operator impact: If your VMs are operating at full or near capacity, you may need to increase the VM resources. If you want this change to occur without logs on app syslog drains being duplicated or dropped for much of the duration of the deploy, we recommend deploying v12 with the operations/experimental/add-disabled-syslog-agent-for-upgrade.yml ops file before deploying v13. This ops file is only needed for your last deployment of v12, and is not needed when deploying v13.


- do we need to remove these certs from credhub mapping?
```
- name: ((credhub_prefix))/adapter_rlp_tls
  type: certificate
  value:
    certificate: ((vault "((vault_prefix))/loggregator/certs/adapter_rlp_tls:certificate"))
    private_key: ((vault "((vault_prefix))/loggregator/certs/adapter_rlp_tls:key"))
    ca_name: ((credhub_prefix))/loggregator_ca
- name: ((credhub_prefix))/adapter_tls
  type: certificate
  value:
    certificate: ((vault "((vault_prefix))/loggregator/certs/adapter_tls:certificate"))
    private_key: ((vault "((vault_prefix))/loggregator/certs/adapter_tls:key"))
    ca_name: ((credhub_prefix))/loggregator_ca
```

- do we need to remove the syslog/adapter checks from blueprint hook
