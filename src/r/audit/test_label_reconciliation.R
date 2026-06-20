#!/usr/bin/env Rscript
# src/r/audit/test_label_reconciliation.R
#
# Regression + unit tests for the label-reconciliation check.
#
# Fixtures encode the two real 2026-06-20 bug classes so a future spec edit that
# reintroduces a wrong-direction fn on an inverse-labeled item fails immediately:
#   (1) synthetic mini-cases via injected raw_labels/spec_labels (fast, no .sav)
#   (2) git-checkout of the pre-fix political_attitudes.yml (ebe4f00^) — Check A
#       MUST flag system_deserves_support as `error`, and the current spec as `ok`.
#
# Run:  Rscript src/r/audit/test_label_reconciliation.R
# Exit: 0 if all pass, 1 otherwise.

suppressPackageStartupMessages({ library(here); library(yaml) })
source(here::here("src", "r", "audit", "04_label_reconciliation.R"))

.pass <- 0L; .fail <- 0L
ok <- function(cond, msg) {
  if (isTRUE(cond)) { .pass <<- .pass + 1L; cat(sprintf("  PASS  %s\n", msg)) }
  else              { .fail <<- .fail + 1L; cat(sprintf("  FAIL  %s\n", msg)) }
}

# Helpers to build inputs in the haven/spec shapes.
raw_lab <- function(...) { v <- c(...); v }                 # names=text, value=code
spec_lab <- function(...) as.list(c(...))                   # names="1".., value=text
REG <- load_registry_index()
fe  <- function(fn) REG[[fn]]                               # real registry rows

cat("=== Synthetic unit cases ===\n")

# (1) THE BUG: non-reversing fn, raw agree@low, labels agree@high -> error.
r1 <- reconcile_one("t","bug_var","w1","q1","safe_4pt_none", fe("safe_4pt_none"),
  raw_labels  = raw_lab("Strongly agree"=1,"Somewhat agree"=2,"Somewhat disagree"=3,"Strongly disagree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","2"="Somewhat disagree","3"="Somewhat agree","4"="Strongly agree"))
ok(r1$status=="error" && r1$reason=="opposite_labels",
   "non-reversing fn on inverse-labeled item -> error (system_deserves_support class)")

# (2) CORRECT reversal: reversing fn, raw agree@low, labels agree@high -> ok.
r2 <- reconcile_one("t","good_rev","w1","q2","safe_reverse_4pt", fe("safe_reverse_4pt"),
  raw_labels  = raw_lab("Strongly agree"=1,"Somewhat agree"=2,"Somewhat disagree"=3,"Strongly disagree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","2"="Somewhat disagree","3"="Somewhat agree","4"="Strongly agree"))
ok(r2$status=="ok", "correctly reversed item -> ok (system_capable class)")

# (3) CORRECT identity: non-reversing fn, raw and labels both agree@high -> ok.
r3 <- reconcile_one("t","good_id","w1","q3","safe_4pt_none", fe("safe_4pt_none"),
  raw_labels  = raw_lab("Strongly disagree"=1,"Somewhat disagree"=2,"Somewhat agree"=3,"Strongly agree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","2"="Somewhat disagree","3"="Somewhat agree","4"="Strongly agree"))
ok(r3$status=="ok", "correctly non-reversed item -> ok")

# (4) WRONG reversal: reversing fn, raw agree@high already matches labels -> error.
r4 <- reconcile_one("t","over_rev","w1","q4","safe_reverse_4pt", fe("safe_reverse_4pt"),
  raw_labels  = raw_lab("Strongly disagree"=1,"Somewhat disagree"=2,"Somewhat agree"=3,"Strongly agree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","2"="Somewhat disagree","3"="Somewhat agree","4"="Strongly agree"))
ok(r4$status=="error" && r4$reason=="opposite_labels",
   "reversal applied when raw already matches labels -> error (demo_political_equality class)")

# (5) Unknown fn -> skip.
r5 <- reconcile_one("t","unk","w1","q5","made_up_fn", REG[["made_up_fn"]],
  raw_labels = raw_lab("Strongly agree"=1,"Strongly disagree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","4"="Strongly agree"))
ok(r5$status=="skip" && r5$reason=="unknown_fn", "unknown fn -> skip/unknown_fn")

# (6) Nominal -> skip.
r6 <- reconcile_one("t","nom","w1","q6","safe_4pt_none", fe("safe_4pt_none"),
  raw_labels = raw_lab("Strongly agree"=1,"Strongly disagree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","4"="Strongly agree"), var_type="nominal")
ok(r6$status=="skip" && r6$reason=="nominal_no_polarity", "nominal -> skip/nominal_no_polarity")

cat("\n=== Git-based regression: pre-fix vs current political_attitudes.yml ===\n")
spec_rel <- "src/config/abs/harmonize_validated/political_attitudes.yml"
prefix_path <- tempfile(fileext = ".yml")
gx <- suppressWarnings(system2("git", c("show", paste0("ebe4f00^:", spec_rel)),
                               stdout = prefix_path, stderr = FALSE))
have_prefix <- file.exists(prefix_path) && file.info(prefix_path)$size > 0

if (have_prefix) {
  pre <- compute_label_reconciliation("abs", spec_files = prefix_path)
  sds_pre <- pre[pre$variable == "system_deserves_support", , drop = FALSE]
  ok(nrow(sds_pre) > 0 && any(sds_pre$status == "error"),
     "pre-fix (ebe4f00^) system_deserves_support -> error")
} else {
  cat("  SKIP  could not retrieve ebe4f00^ spec (commit missing?)\n")
}

cur <- compute_label_reconciliation("abs",
  spec_files = here::here(spec_rel))
sds_cur <- cur[cur$variable == "system_deserves_support", , drop = FALSE]
ok(nrow(sds_cur) > 0 && !any(sds_cur$status == "error") && any(sds_cur$status == "ok"),
   "current system_deserves_support -> no error, >=1 ok (fix holds; W6 raw labels absent -> skip)")

cat(sprintf("\n=== %d passed, %d failed ===\n", .pass, .fail))
if (.fail > 0L) quit(status = 1L) else quit(status = 0L)
