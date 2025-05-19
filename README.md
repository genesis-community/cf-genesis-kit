# Cloud Foundry Genesis Kit

This is a Genesis Kit for deploying [Cloud Foundry](https://docs.cloudfoundry.org) on BOSH. It provides a streamlined, maintainable deployment experience for Cloud Foundry operators.

The kit is built around the community-standard [cf-deployment](https://github.com/cloudfoundry/cf-deployment) and adds Genesis-specific conveniences, integrations, and best practices.

## Features

- **Multi-Cloud Support** - Deploy to AWS, Azure, GCP, vSphere, OpenStack, or Stackit
- **Modular Design** - Enable only the features you need
- **Database Options** - Use built-in database or integrate with external MySQL/PostgreSQL
- **Blobstore Options** - Configure for various storage backends (AWS S3, Azure, GCP, Minio)
- **Isolation Segments** - Support for multi-tenant isolation
- **High Availability** - Deploy resilient, production-ready environments
- **OCFP Mode** - Deploy an opinionated OpenSource Cloud Foundry Platform configuration

## Quick Start

To use it, you don't even need to clone this repository! Just run the following (using Genesis v2):

```bash
# Create a cf-deployments repo using the latest version of the cf kit
genesis init --kit cf

# Create a cf-deployments repo using v2.5.0 of the cf kit
genesis init --kit cf/2.5.0

# Create a my-cf-configs repo using the latest version of the cf kit
genesis init --kit cf -d my-cf-configs
```

Once you've created your configuration repository, follow these steps:

1. Create a new environment file using `genesis new <env>` 
2. Configure your environment with the desired features
3. Deploy Cloud Foundry with `genesis deploy <env>`

## Documentation

For detailed information, please consult the documentation:

- [Comprehensive Manual](MANUAL.md) - In-depth guide to all features and configurations
- [Cloud Foundry Documentation](https://docs.cloudfoundry.org) - Official Cloud Foundry documentation
- [Genesis Documentation](https://genesisproject.io/docs/) - Genesis deployment system documentation

## Requirements

- BOSH Director with Credhub
- BOSH DNS configured via runtime config
- Appropriate cloud infrastructure and networking

## Available Addons

- `setup-cli` - Installs CF CLI plugins like 'Targets'
- `login` - Log into the Cloud Foundry instance as admin
- `smoketest` - Run smoke tests against your deployment
- `asg` - Generate application security group (ASG) definitions

## Contributing

We welcome contributions! Please read our [Contributing Guidelines](CONTRIBUTING.md) and [Code of Conduct](CONDUCT.md).

## License

This kit is released under the [MIT License](LICENSE).