# Makefile — audit orchestration (audit ticket H1)
#
# The orchestrator itself is src/r/audit/run_all.R; this file only gives it the
# short, memorable entry points the ticket asked for. Every target is a thin
# wrapper — no logic lives here, so `make` and a bare Rscript call stay
# interchangeable.
#
#   make audit                 all surveys, all layers  (needs local data)
#   make audit SURVEY=abs      one survey
#   make audit-quick           skips the two slowest modules (G1 drift, F4 codebook)
#   make audit-specs           data-free layers only — this is what CI runs
#   make audit-report          print the last run's summary
#   make check-r               parse every R file (fast syntax gate)
#
# Note on data: raw survey files and data/processed/*.rds are gitignored, so
# `make audit` is a LOCAL command. Only `make audit-specs` can run on a clean
# checkout. See .github/workflows/audit.yml.

R      ?= Rscript
AUDIT  := src/r/audit/run_all.R
SURVEY ?=

# `make audit SURVEY=abs` -> --survey abs; plain `make audit` -> every survey
SURVEY_ARG := $(if $(SURVEY),--survey $(SURVEY),)

.PHONY: help audit audit-quick audit-specs audit-report check-r

help:
	@echo "Audit targets:"
	@echo "  make audit                 full audit, all layers (needs local data)"
	@echo "  make audit SURVEY=abs      restrict to one survey"
	@echo "  make audit-quick           skip G1 drift + F4 codebook (faster)"
	@echo "  make audit-specs           data-free layers only (what CI runs)"
	@echo "  make audit-report          print audit/SUMMARY.md from the last run"
	@echo "  make check-r               parse every R file under src/r"
	@echo ""
	@echo "Exit codes from run_all.R: 0 clean, 1 fails detected, 2 prereqs missing."

audit:
	$(R) $(AUDIT) $(SURVEY_ARG)

audit-quick:
	$(R) $(AUDIT) --quick $(SURVEY_ARG)

audit-specs:
	$(R) $(AUDIT) --specs-only $(SURVEY_ARG)

audit-report:
	@test -f audit/SUMMARY.md \
	  || { echo "no audit/SUMMARY.md — run 'make audit' first"; exit 1; }
	@cat audit/SUMMARY.md

check-r:
	$(R) src/r/audit/check_parse.R
