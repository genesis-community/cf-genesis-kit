# Cloud Foundry Genesis Kit Makefile

.PHONY: help tidy test t spec genesis-version

# Which Genesis the test suites run against.
#
# The Ginkgo harness shells out to the bare command name `genesis`, so pointing
# the suite at a particular build means putting that build first on PATH under
# that name. Set GENESIS_BIN to any genesis binary -- a packed development
# build, for instance -- and the targets below link it into .genesis-bin/ and
# run against it. Left unset, they use whichever genesis is already on PATH.
#
# The Perl tests under t/ load the Genesis library directly rather than the
# binary, so they take GENESIS_LIB instead.
GENESIS_BIN ?= $(shell command -v genesis 2>/dev/null)
GENESIS_LIB ?= $(HOME)/.genesis/lib
GENESIS_PATH := $(CURDIR)/.genesis-bin

# Default target - show available tasks
help:
	@echo "Available targets:"
	@echo "  make test    - Run the Perl unit tests and the Ginkgo spec suite"
	@echo "  make t       - Run the Perl unit tests under t/"
	@echo "  make spec    - Run the Ginkgo spec suite under spec/"
	@echo "  make tidy    - Run perltidy on all Perl files in hooks/"
	@echo "  make help    - Show this help message"
	@echo ""
	@echo "Set GENESIS_BIN to run the spec suite against a specific genesis build,"
	@echo "and GENESIS_LIB to run the Perl tests against a specific genesis library."

$(GENESIS_PATH)/genesis:
	@test -n "$(GENESIS_BIN)" || { echo "No genesis binary on PATH; set GENESIS_BIN"; exit 1; }
	@mkdir -p $(GENESIS_PATH)
	@ln -sf "$(realpath $(GENESIS_BIN))" $(GENESIS_PATH)/genesis

genesis-version: $(GENESIS_PATH)/genesis
	@PATH="$(GENESIS_PATH):$$PATH" genesis version

test: t spec

t:
	@GENESIS_LIB=$(GENESIS_LIB) prove -v t/*.t

spec: genesis-version
	@cd spec && PATH="$(GENESIS_PATH):$$PATH" ginkgo -p .

# Run perltidy on hooks directory
tidy:
	@echo "Running perltidy on hooks/*.pm files..."
	@perltidy -b hooks/*.pm
	@echo "Tidying complete."
