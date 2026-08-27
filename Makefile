.PHONY: help install run run-macos run-chrome test clean

FLUTTER_ROOT ?= $(abspath ../.flutter-sdk)
FLUTTER := $(FLUTTER_ROOT)/bin/flutter
DEVICE ?=

help:
	@echo "RosterIQ - NBA fantasy draft-night assistant"
	@echo ""
	@echo "  make install      Fetch Flutter dependencies"
	@echo "  make run          Run the app (physical device if plugged in)"
	@echo "  make run-macos    Run on macOS desktop"
	@echo "  make run-chrome   Run in Chrome browser"
	@echo "  make test         Run unit/widget tests"
	@echo "  make clean        Remove build artifacts"
	@echo ""
	@echo "Override device: make run DEVICE=iphone"

install:
	$(FLUTTER) pub get

run: install
ifdef DEVICE
	$(FLUTTER) run -d $(DEVICE)
else
	$(FLUTTER) run
endif

run-macos: install
	$(FLUTTER) run -d macos

run-chrome: install
	$(FLUTTER) run -d chrome

test: install
	$(FLUTTER) test

clean:
	$(FLUTTER) clean
