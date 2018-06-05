Cloud Foundry Genesis Kit
==================

This is a Genesis Kit for the [Cloud Foundry][1]. It will deploy
a Cloud Foundry environment, loosely based off of [cf-deployments][2].

Quick Start
-----------

To use it, you don't even need to clone this repository!  Just run
the following (using Genesis v2):

```
# create a cf-deployments repo using the latest version of the cf kit
genesis init --kit cf

# create a cf-deployments repo using v1.0.0 of the cf kit
genesis init --kit cf/1.0.0

# create a my-cf-configs repo using the latest version of the cf kit
genesis init --kit cf -d my-cf-configs
```

Learn More
----------

For more in-depth documentation, check out the [manual][5].

[1]: https://docs.cloudfoundry.org
[2]: https://github.com/cloudfoundry/cf-deployment
[3]: MANUAL.md
