package spec_test

import (
	"path/filepath"
	"runtime"

	. "github.com/genesis-community/testkit/testing"
	. "github.com/onsi/ginkgo"
)

var _ = Describe("Interal Kit", func() {
	BeforeSuite(func() {
		_, filename, _, _ := runtime.Caller(0)
		KitDir, _ = filepath.Abs(filepath.Join(filepath.Dir(filename), "../"))
	})

	Test(Environment{
		Name:          "bare",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	// ROUTING
	Test(Environment{
		Name:          "haproxy",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "haproxy-tls",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CredhubVars:   "haproxy-tls",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "haproxy-self-signed",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	// DB
	Test(Environment{
		Name:          "mysql-db",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "postgres-db",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	// BLOBSTORE
	Test(Environment{
		Name:          "blobstore-aws",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		// CredhubVars:   "aws",
		CPI: "aws",
	})
	Test(Environment{
		Name:          "blobstore-gcp",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CredhubVars:   "gcp",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "blobstore-azure",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CredhubVars:   "azure",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "blobstore-minio",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	// FEATURES
	Test(Environment{
		Name:          "container-routing-integrity",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "native-garden-runc",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "loggregator-forwarder-agent",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "dns-service-discovery",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "routing-api",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "app-autoscaler-integration",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "small-footprint",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "availability-zones",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "no-tcp-routers",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "router-synergy",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "override-vm-types-and-counts",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "override-vm-types-and-counts-old-names",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
	})
	Test(Environment{
		Name:          "upgrading-to-v2",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
		Exodus:        "v1",
	})
	Test(Environment{
		Name:          "upgraded-from-v1",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
		Exodus:        "migrated",
	})
	Test(Environment{
		Name:          "upgrade-from-v1-with-db-override-names",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
		Exodus:        "migrated",
	})
	Test(Environment{
		Name:          "upgrading-to-v2-with-204-overrides",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
		Exodus:        "v1",
	})
	Test(Environment{
		Name:          "upgraded-from-v1-with-204-overrides",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CPI:           "aws",
		Exodus:        "migrated",
	})
	// Test(Environment{
	// 	Focus:       true,
	// 	Name:        "nfs-volume-services",
	// 	CloudConfig: "aws",
	// 	CPI:         "aws",
	// })
})
