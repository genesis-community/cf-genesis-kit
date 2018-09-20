# Bug Fixes

Previously, we had an incorrect spruce operation that confused `scheme` and
`schema`, which resulted in locketdb and diegodb data being written to a
database named `postgres` (rather than `locketdb` and `diegodb`, respectively.)

If you are upgrading from CF Genesis Kit version 1.1.0, 1.1.1, or 1.1.2, a
Genesis Migration Process (GMP) must be performed. Please review
[GMP-CF-0001: Database Scheme Fix Migration][gmp-cf-0001]

[gmp-cf-0001]: http://www.genesisproject.io/docs/migrations/gmp-cf-0001
