# Cloud Foundry Genesis Kit Makefile

.PHONY: help tidy

# Default target - show available tasks
help:
	@echo "Available targets:"
	@echo "  make tidy    - Run perltidy on all Perl files in hooks/"
	@echo "  make help    - Show this help message"

# Run perltidy on hooks directory
tidy:
	@echo "Running perltidy on hooks/*.pm files..."
	@perltidy -b hooks/*.pm
	@echo "Tidying complete. Backup files created as *.bak"