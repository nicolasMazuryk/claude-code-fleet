# cc-orchestrator — run from the repo root. `make help` lists targets.
SHELL := /bin/bash
.DEFAULT_GOAL := help
BIN := $(CURDIR)/bin

# run <script> [args]: run bin/<script> if it exists, else say which phase delivers it
define run
	@if [ -x "$(BIN)/$(1)" ] || [ -x "$(CURDIR)/$(1)" ]; then \
	  if [ -x "$(CURDIR)/$(1)" ]; then "$(CURDIR)/$(1)" $(2); else "$(BIN)/$(1)" $(2); fi; \
	else echo "$(1): not implemented yet ($(3)); see prompts/plan.md" >&2; exit 2; fi
endef

.PHONY: help install-mac install-cloud sync capture doctor fleet lint test

help: ## list targets
	@awk 'BEGIN{FS=":.*## "} /^[a-z-]+:.*## /{printf "  %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install-mac: ## ./install.sh mac (idempotent; backs up ~/.claude/settings.json first)
	$(call run,install.sh,mac,Phase 3)

install-cloud: ## ./install.sh cloud (rsync + units over ssh cloud; idempotent)
	$(call run,install.sh,cloud,Phase 4)

sync: ## mirror Mac Claude Code settings to cloud (expect "4 ... relayed"); ARGS=--dry-run|--print|--install-plugins
	$(call run,cc-sync-settings,$(ARGS),Phase 4)

capture: ## snapshot Mac ~/.claude into config/ (sanitized), then review git diff
	$(call run,cc-capture,,Phase 1)

doctor: ## health check of this host (and cloud from the Mac)
	$(call run,cc-doctor,,Phase 7)

fleet: ## every session on Mac + cloud, waiting-for-you first
	$(call run,fleet,,Phase 3)

lint: ## shellcheck every shell script in the repo
	@command -v shellcheck >/dev/null || { echo "brew install shellcheck" >&2; exit 2; }
	@files=$$(tests/shell-files.sh); \
	if [ -z "$$files" ]; then echo "lint: no shell scripts yet"; else \
	  echo "$$files" | xargs shellcheck -x && echo "lint: ok ($$(echo "$$files" | wc -l | tr -d ' ') files)"; fi

test: ## bats tests in tests/
	@command -v bats >/dev/null || { echo "brew install bats-core" >&2; exit 2; }
	@bats tests/
