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

# Navigation database (E02). AIRAC=next prepares the next cycle; the FAA publishes it before its effective date.
NAVDB_CLI    := $(SWIFT) run --package-path $(PACKAGE) -c release navdb-cli
AIRAC        ?= current
CYCLE         = $(shell $(PACKAGE)/Scripts/airac.sh $(AIRAC) ident)
CIFP_DIR      = build/cifp/$(CYCLE)
NAVDB         = build/navdb/navdb-$(CYCLE).sqlite
# The address of the database file in the manifest. A relative address is relative to the manifest.
NAVDB_URL    ?= navdb-$(CYCLE).sqlite
# Threshold of the ND query (radius 320 NM): p99 must be below it. See Docs/navdb.md.
NAVDB_P99_MS ?= 20
SAMPLE_AIRPORTS := KJFK,KMRY,KACK,TJSJ,PANC,KBTV,KCRQ,KASE,13FD,5KE

.PHONY: help build build-ios test lint-imports soak replay-goldens golden-update bench check clean \
	navdb-fetch navdb-convert navdb-verify navdb-bench navdb-manifest navdb-cycle navdb-sample

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
	@echo "make navdb-cycle     fetch, convert, verify, bench, manifest of the AIRAC cycle (AIRAC=current|next)"
	@echo "make navdb-fetch     download the FAA CIFP of the cycle to build/cifp/<cycle>/ (needs network)"
	@echo "make navdb-convert   convert CIFP to build/navdb/navdb-<cycle>.sqlite and write the report"
	@echo "make navdb-verify    check the database against the CIFP file"
	@echo "make navdb-bench     measure the ND query, fail when p99 > NAVDB_P99_MS"
	@echo "make navdb-manifest  write build/navdb/manifest.json for the database"
	@echo "make navdb-sample    make a new test sample from the full CIFP file"
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

navdb-fetch:
	$(PACKAGE)/Scripts/fetch-cifp.sh $(CIFP_DIR) $(AIRAC)

navdb-convert:
	$(NAVDB_CLI) convert --cifp $(CIFP_DIR)/FAACIFP18 --out $(NAVDB) --report $(REPORTS)/navdb-convert-$(CYCLE).json

navdb-verify:
	$(NAVDB_CLI) verify --cifp $(CIFP_DIR)/FAACIFP18 --db $(NAVDB) --report $(REPORTS)/navdb-verify-$(CYCLE).json

navdb-bench:
	$(NAVDB_CLI) bench --db $(NAVDB) --out $(REPORTS)/navdb-query.json --max-p99-ms $(NAVDB_P99_MS)

navdb-manifest:
	$(NAVDB_CLI) manifest --db $(NAVDB) --url $(NAVDB_URL) --out build/navdb/manifest.json

navdb-cycle: navdb-fetch navdb-convert navdb-verify navdb-bench navdb-manifest

navdb-sample:
	$(NAVDB_CLI) extract-sample --cifp $(CIFP_DIR)/FAACIFP18 --airports $(SAMPLE_AIRPORTS) \
		--out $(PACKAGE)/Tests/Fixtures/CIFP-sample-$(CYCLE).txt

clean:
	rm -rf $(PACKAGE)/.build build
