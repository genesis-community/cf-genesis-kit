# Bug Fixes

- When features `autoscaler` and `migrate-1.3-without-consul` are both
  enabled, the removal code tries to update the `eventgenerator` and
  `metricscollector` properties in the `jobs` section in the wrong
  `instance_groups`, which results in the following error message:

  ```
  Error: Cannot tell what release template 'eventgenerator' (instance group 'as-collector')uuuis supposed to use, please explicitly specify one
  ```
  
  This fix swaps them, placing them in the correct hierarchy.
