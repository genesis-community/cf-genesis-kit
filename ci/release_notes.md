# New Features

- The routing api is now available to use via the `routing-api` kit feature.
  This is needed to use cf management against a genesis deployed cloud foundry.

# Improvements

- Allow evacuation timeout to be set as a param, The default is now 10 minutes.

# Bug Fixes

- The route service feature was previously misconfigured and is now correctly in the api instance group   and cloud_controller_ng job.