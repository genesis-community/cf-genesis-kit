# Bug Fixes

Previously, we had an incorrect spruce operation that confused `scheme` and
`schema`, which resulted in locketdb and silkdb data being written to a
database named `postgres` (rather than `locketdb` and `silkdb`, respectively.)

If you are upgrading from CF Genesis Kit version 1.1.0, 1.1.1, or 1.1.2, a
Genesis Migration Path (GMP) must be performed. Please visit
[CF-M0001: Database Scheme Fix Migration)[https://genesisproject.io/docs/migrations/cf/cf-m0001/] 
