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
		Name:        "haproxy",
		CloudConfig: "aws",
		CPI:         "aws",
	})
	Test(Environment{
		Name:          "haproxy-tls",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CredhubVars:   "haproxy-tls",
		CPI:           "aws",
	})
	Test(Environment{
		Name:        "haproxy-self-signed",
		CloudConfig: "aws",
		CPI:         "aws",
	})
	// DB
	Test(Environment{
		Name:        "mysql-db",
		CloudConfig: "aws",
		CPI:         "aws",
	})
	Test(Environment{
		Name:        "postgres-db",
		CloudConfig: "aws",
		CPI:         "aws",
	})
	// BLOBSTORE
	Test(Environment{
		Name:          "blobstore-aws",
		CloudConfig:   "aws",
		RuntimeConfig: "dns",
		CredhubVars:   "aws",
		CPI:           "aws",
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
	// FEATURES
	Test(Environment{
		Name:        "container-routing-integrity",
		CloudConfig: "aws",
		CPI:         "aws",
	})
	Test(Environment{
		Name:        "native-garden-runc",
		CloudConfig: "aws",
		CPI:         "aws",
	})
	Test(Environment{
		Name:        "loggregator-forwarder-agent",
		CloudConfig: "aws",
		CPI:         "aws",
	})
	Test(Environment{
		Name:        "dns-service-discovery",
		CloudConfig: "aws",
		CPI:         "aws",
	})
	Test(Environment{
		Name:        "routing-api",
		CloudConfig: "aws",
		CPI:         "aws",
	})
	Test(Environment{
		Name:        "app-autoscaler-integration",
		CloudConfig: "aws",
		CPI:         "aws",
	})
	Test(Environment{
		Name:        "small-footprint",
		CloudConfig: "aws",
		CPI:         "aws",
	})
	// Test(Environment{
	// 	Focus:       true,
	// 	Name:        "nfs-volume-services",
	// 	CloudConfig: "aws",
	// 	CPI:         "aws",
	// })
})
