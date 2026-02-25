SHELL := /bin/zsh

.PHONY: conformance conformance-preflight conformance-unit conformance-yaml conformance-yaml-batch conformance-yaml-scaffold conformance-run

conformance: conformance-preflight conformance-unit conformance-yaml

conformance-preflight:
	@ruby scripts/conformance_preflight.rb

conformance-unit:
	@if command -v clojure >/dev/null 2>&1; then \
		clojure -M:test ; \
	elif command -v bb >/dev/null 2>&1; then \
		bb test ; \
	elif command -v lein >/dev/null 2>&1; then \
		lein test ; \
	else \
		echo "No Clojure test runner found (clojure|bb|lein)."; \
		echo "Install one and rerun: make conformance"; \
		exit 1; \
	fi

conformance-yaml:
	@if command -v clojure >/dev/null 2>&1; then \
		clojure -M -m cantrip.conformance --batch ; \
	else \
		echo "Clojure CLI required for YAML conformance runner."; \
		exit 1; \
	fi

conformance-yaml-batch:
	@$(MAKE) conformance-yaml

conformance-yaml-scaffold:
	@echo "conformance-yaml-scaffold is deprecated; running full YAML conformance batch."
	@$(MAKE) conformance-yaml

conformance-run: conformance-unit
