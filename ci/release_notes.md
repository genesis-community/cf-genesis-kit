# Improvements

- Added support for dynamic X.509 certificates TTL.  You can specify
  `ca_validity_period` and `cert_validity_period` under `params` in your
  environment file.  These default to `10y` and `1y` respectively.  This
  changes the previous default of 1 year for both.
