# JetDeck FMS. Commands for local work and for CI. `make check` is the full check.

PACKAGE  := SimCore
SWIFT    := swift
GOLDENS  := $(PACKAGE)/Tests/GoldenTests/Goldens
REPORTS  := build/reports
CLI      := $(SWIFT) run --package-path $(PACKAGE) -c release simcore-cli

# The toolchain sometimes does not load the macro plugin of Swift Testing ("plugin for module
# 'TestingMacros' not found"). The explicit plugin path makes the test build stable.
SWIFTC_PATH     := $(shell xcrun --find swiftc)
TESTING_PLUGINS := $(patsubst %/bin/swiftc,%/lib/swift/host/plugins/testing,$(SWIFTC_PATH))
TEST     := $(SWIFT) test --package-path $(PACKAGE) $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

.PHONY: help build build-ios test lint-imports soak replay-goldens golden-update bench check clean

help:
	@echo "make build           build the SimCore package"
	@echo "make build-ios       build the SimCore library for iPadOS (needs Xcode)"
	@echo "make test            run all tests"
	@echo "make test-<Target>   run the tests of one target, for example: make test-Kernel"
	@echo "make lint-imports    check the layer rule for imports"
	@echo "make soak            run 30 000 steps (10 minutes of simulation time)"
	@echo "make replay-goldens  replay the reference recordings and compare the snapshots"
	@echo "make golden-update   make new reference snapshots after an intended change"
	@echo "make bench           measure the step time, report in $(REPORTS)/"
	@echo "make check           build, lint-imports, test, bench"
	@echo "make clean           remove build products"

build:
	$(SWIFT) build --package-path $(PACKAGE)

build-ios:
	cd $(PACKAGE) && xcodebuild -scheme SimCore -destination 'generic/platform=iOS' -derivedDataPath .build/xcode build

test:
	$(TEST)

test-%:
	$(TEST) --filter '^$*Tests\.'

lint-imports:
	$(PACKAGE)/Scripts/check-imports.sh

soak:
	$(TEST) --filter 'soak30000Steps'

replay-goldens:
	$(TEST) --filter '^GoldenTests\.'

golden-update:
	@test -f $(GOLDENS)/stub-10min/recording.json || \
		$(CLI) gen-recording --steps 30000 --events 300 --seed 1 --out $(GOLDENS)/stub-10min/recording.json
	$(CLI) golden-update $(GOLDENS)

bench:
	$(CLI) bench --steps 30000 --out $(REPORTS)/step-timing.json

check: build lint-imports test bench

clean:
	rm -rf $(PACKAGE)/.build build
