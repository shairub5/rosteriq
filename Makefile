.PHONY: help install run run-macos run-chrome test clean

FLUTTER_ROOT ?= $(abspath ../.flutter-sdk)
FLUTTER := $(FLUTTER_ROOT)/bin/flutter
DEVICE ?=
DEFINES_FILE ?= secrets.json

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
	@echo "Override device:       make run DEVICE=iphone"
	@echo "Override defines file: make run DEFINES_FILE=other.json"
	@echo "Copy secrets.json.example to secrets.json and fill in Yahoo client id for in-app login"

install:
	$(FLUTTER) pub get

run: install
ifdef DEVICE
	$(FLUTTER) run -d $(DEVICE) --dart-define-from-file=$(DEFINES_FILE)
else
	$(FLUTTER) run --dart-define-from-file=$(DEFINES_FILE)
endif

run-macos: install
	$(FLUTTER) run -d macos --dart-define-from-file=$(DEFINES_FILE)

run-chrome: install
	$(FLUTTER) run -d chrome --dart-define-from-file=$(DEFINES_FILE)

test: install
	$(FLUTTER) test

clean:
	$(FLUTTER) clean
