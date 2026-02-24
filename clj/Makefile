SHELL := /bin/zsh

.PHONY: conformance conformance-preflight conformance-run

conformance: conformance-preflight conformance-run

conformance-preflight:
	@ruby scripts/conformance_preflight.rb

conformance-run:
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
