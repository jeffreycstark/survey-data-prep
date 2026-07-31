#!/usr/bin/env Rscript
# src/r/audit/test_oob_triage.R
#
# Fault-injection tests for Layer 3b (out-of-range triage, Check E).
# Run:  Rscript src/r/audit/test_oob_triage.R
# Exit: 0 if all pass, 1 otherwise.
#
# The point of this layer is that ~24,000 silently-deleted respondent-values sat
# in unread logs. These tests therefore pin the real events that motivated it
# (they are regression fixtures, taken verbatim from the committed logs) as well
# as the classifier's boundaries and the exemption plumbing.

suppressPackageStartupMessages({ library(here); library(yaml) })
source(here::here("src", "r", "audit", "03_oob_triage.R"))

.pass <- 0L; .fail <- 0L
ok <- function(cond, msg) {
  if (isTRUE(cond)) { .pass <<- .pass + 1L; cat(sprintf("  PASS  %s\n", msg)) }
  else              { .fail <<- .fail + 1L; cat(sprintf("  FAIL  %s\n", msg)) }
}

tmp <- file.path(tempdir(), paste0("oobtri_", as.integer(runif(1, 1e6, 9e6))))
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

# Convenience: classify with a named type / declared-elsewhere set.
cls <- function(omin, omax, vmin, vmax, type = "ordinal", elsewhere = numeric(0)) {
  classify_oob_event(omin, omax, vmin, vmax, type, elsewhere)
}

write_log <- function(rows, name = "oob_log.csv") {
  p <- file.path(tmp, name)
  utils::write.csv(rows, p, row.names = FALSE)
  p
}

mk_row <- function(variable, wave, n_oob, obs_min, obs_max, valid_min, valid_max) {
  data.frame(variable = variable, wave = wave, n_oob = n_oob,
             obs_min = obs_min, obs_max = obs_max,
             valid_min = valid_min, valid_max = valid_max,
             stringsAsFactors = FALSE)
}


cat("\n-- classifier: the motivating real events ------------------------------\n")

# wvs freedom_vs_equality w2: 8,787 x code 3 in a 1-2 item. A whole third
# response option deleted. Must be scale_extension + error.
ok(cls(3, 3, 1, 2) == "scale_extension",
   "wvs freedom_vs_equality w2 (code 3, valid 1-2) -> scale_extension")
ok(grade_oob_event("scale_extension", 8787) == "error",
   "  ... 8,787 occurrences -> error")

# afro dem_satisfaction w9: 932 x code 0 in a 1-4 item. Already known
# (JEFF_MUST_INVESTIGATE.md) — found by a human, not a check. Must go error.
ok(cls(0, 0, 1, 4) == "zero_leak",
   "afro dem_satisfaction w9 (code 0, valid 1-4) -> zero_leak")
ok(grade_oob_event("zero_leak", 932) == "error",
   "  ... 932 occurrences -> error")

# afro corr_perc_mp w9: 4,800 x code 94. 94 = "Question not asked", declared in
# seven other afro specs. Evidence-based sentinel -> warn (benign outcome).
ok(cls(94, 94, 0, 3, elsewhere = c(-1, 8, 9, 94, 98, 99)) == "sentinel_leak",
   "afro corr_perc_mp w9 (code 94 declared elsewhere) -> sentinel_leak")
ok(grade_oob_event("sentinel_leak", 4800) == "warn",
   "  ... stays warn even at 4,800 (value would be NA either way)")

# arab-barometer dem_feature_1st w2: 4-5 digit codes where spec declares 1-10.
ok(cls(2001, 10503, 1, 10) == "out_of_frame_code",
   "arab dem_feature_1st w2 (2001..10503, valid 1-10) -> out_of_frame_code")
ok(grade_oob_event("out_of_frame_code", 52) == "error",
   "  ... error regardless of volume")

# abs hh_size: 21..93 in a continuous 1-20 var = dirty raw tail, not a code bug.
ok(cls(21, 93, 1, 20, type = "continuous") == "outlier_tail",
   "abs hh_size (21..93, continuous) -> outlier_tail")
ok(grade_oob_event("outlier_tail", 24) == "warn", "  ... warn")

# lbs age y2010: 2,483 zeros in a continuous var. zero_leak must beat the
# continuous branch, or bulk sentinel-zeros would be written off as dirty data.
ok(cls(0, 0, 15, 110, type = "continuous") == "zero_leak",
   "lbs age y2010 (2,483 x code 0, continuous) -> zero_leak not outlier_tail")

# kinu conflict_*: code 9 in a 1-4 item, non-contiguous -> classic sentinel.
ok(cls(9, 9, 1, 4) == "sentinel_leak",
   "kinu conflict_overall_severity (code 9, valid 1-4) -> sentinel_leak")

# abs hh_generations w6: 107 x code 10 in a 1-4 item. Not contiguous, not a
# sentinel, not 10x the frame -> unclassified, but the volume must escalate it.
ok(cls(10, 10, 1, 4) == "unclassified",
   "abs hh_generations w6 (code 10, valid 1-4) -> unclassified")
ok(grade_oob_event("unclassified", 107) == "error",
   "  ... 107 occurrences crosses bulk_n -> error")


cat("\n-- classifier: boundaries that decide error vs warn ---------------------\n")

# Contiguity must be tested BEFORE the single-digit sentinel set, else a real
# 7th category on a 1-6 scale gets written off as Don't-know.
ok(cls(7, 7, 1, 6) == "scale_extension",
   "code 7 immediately outside a 1-6 scale -> scale_extension (not sentinel)")
ok(cls(9, 9, 1, 6) == "sentinel_leak",
   "code 9 outside a 1-6 scale (non-contiguous) -> sentinel_leak")
ok(cls(4, 4, 0, 3) == "scale_extension",
   "afro bribe_* w2 (code 4, valid 0-3) -> scale_extension")

# A variable's own declared codes are subtracted before matching, so a code the
# survey declares nowhere stays a real finding.
ok(cls(460, 460, 1, 3) == "out_of_frame_code",
   "afro urban_rural (code 460, valid 1-3, undeclared) -> out_of_frame_code")

ok(cls(0, 0, 0, 3) != "zero_leak",
   "code 0 where the scale ALREADY starts at 0 is not a zero_leak")
ok(cls(5, 5, 1, 4) == "scale_extension" && cls(0, 0, 1, 4) == "zero_leak",
   "the user's motivating case: stray 5 on a 1-4 scale -> scale_extension")

ok(grade_oob_event("scale_extension", 29) == "warn" &&
   grade_oob_event("scale_extension", 30) == "error",
   "escalate_n boundary is exact (29 warn / 30 error)")
ok(grade_oob_event("unclassified", 49) == "warn" &&
   grade_oob_event("unclassified", 50) == "error",
   "bulk_n boundary is exact (49 warn / 50 error)")
ok(cls(NA, 4, 1, 4) == "unclassified",
   "malformed row (NA bound) -> unclassified, never a silent pass")

# scale_extension is an ORDINAL concept. On a measured quantity a value one
# past the bound is dirty data — wvs age 15 against a floor of 16 is a
# 15-year-old, not a lost response option.
ok(cls(15, 15, 16, 110, type = "continuous") == "outlier_tail",
   "wvs age w3 (code 15, continuous, floor 16) -> outlier_tail not scale_extension")
ok(cls(15, 15, 16, 110, type = "ordinal") == "scale_extension",
   "  ... the same bounds on an ORDINAL var stay scale_extension")

# The evidence base must be sentinel-SHAPED. Both of these were downgraded to
# warn on the first live run because the survey declares the code as missing on
# some unrelated variable; both are real findings.
abs_declared  <- c(-2, -1, 0, 3, 5, 6, 7, 8, 9, 10, 11, 90, 97, 98, 99, 999)
afro_declared <- c(-1, 0, 6, 7, 8, 9, 10, 94, 97, 98, 99, 997, 998, 999)
shape <- function(x) x[x < 0 | abs(x) >= .SENTINEL_SHAPE_MIN]

ok(cls(10, 10, 1, 4, elsewhere = shape(abs_declared)) == "unclassified",
   "abs hh_generations (code 10 declared on an unrelated var) stays a finding")
ok(cls(0, 0, 1, 4, elsewhere = shape(afro_declared)) == "zero_leak",
   "afro dem_satisfaction (code 0 declared on an unrelated var) stays zero_leak")
ok(cls(94, 94, 0, 3, elsewhere = shape(afro_declared)) == "sentinel_leak",
   "  ... while sentinel-shaped 94 is still excused by the same evidence base")


cat("\n-- log handling: missing vs empty ---------------------------------------\n")

res_missing <- run_oob_triage("abs", log_path = file.path(tmp, "nope.csv"),
                              exemptions = list(), spec_ctx = list(),
                              write_report = FALSE)
ok(res_missing$status == "skip",
   "absent log -> skip (nothing is known), not ok")

empty_log <- write_log(mk_row(character(0), character(0), integer(0),
                              numeric(0), numeric(0), numeric(0), numeric(0)),
                       "empty.csv")
res_empty <- run_oob_triage("abs", log_path = empty_log, exemptions = list(),
                            spec_ctx = list(), write_report = FALSE)
ok(res_empty$status == "ok" && res_empty$n_rows == 0L,
   "empty log (header only) -> ok, a real clean bill")

bad_log <- file.path(tmp, "bad.csv")
utils::write.csv(data.frame(variable = "x", wave = "w1"), bad_log, row.names = FALSE)
res_bad <- run_oob_triage("abs", log_path = bad_log, exemptions = list(),
                          spec_ctx = list(), write_report = FALSE)
ok(res_bad$status == "config_error",
   "log missing required columns -> config_error, fails closed")


cat("\n-- grading a whole log + exemption plumbing -----------------------------\n")

log_rows <- rbind(
  mk_row("freedom_vs_equality", "w2", 8787, 3, 3, 1, 2),   # error
  mk_row("age",                 "w1",   53, 13, 15, 16, 110), # warn (continuous)
  mk_row("conflict_severity",   "w1",    2, 9, 9, 1, 4)     # warn (sentinel)
)
ctx <- list(types = c(age = "continuous"), var_missing = list(),
            survey_missing = numeric(0))

res <- run_oob_triage("wvs", log_path = write_log(log_rows), exemptions = list(),
                      spec_ctx = ctx, write_report = FALSE)
ok(res$status == "fail" && res$n_error == 1L && res$n_warn == 2L,
   "mixed log -> fail with 1 error / 2 warn")

res_ex <- run_oob_triage(
  "wvs", log_path = write_log(log_rows),
  exemptions = list(list(variable = "freedom_vs_equality",
                         reason = "documented third option, handled downstream")),
  spec_ctx = ctx, write_report = FALSE)
ok(res_ex$status == "warn" && res_ex$n_error == 0L && res_ex$n_ok == 1L,
   "exemption downgrades error -> ok_exempt")

res_ex_wave <- run_oob_triage(
  "wvs", log_path = write_log(log_rows),
  exemptions = list(list(variable = "freedom_vs_equality", wave = "w7",
                         reason = "different wave entirely")),
  spec_ctx = ctx, write_report = FALSE)
ok(res_ex_wave$n_error == 1L,
   "wave-scoped exemption does not leak to other waves")

res_ex_survey <- run_oob_triage(
  "wvs", log_path = write_log(log_rows),
  exemptions = list(list(variable = "freedom_vs_equality", survey = "abs",
                         reason = "different survey entirely")),
  spec_ctx = ctx, write_report = FALSE)
ok(res_ex_survey$n_error == 1L,
   "survey-scoped exemption does not leak to other surveys")

warn_only_ex <- run_oob_triage(
  "wvs", log_path = write_log(log_rows),
  exemptions = list(list(variable = "age", reason = "known dirty tail")),
  spec_ctx = ctx, write_report = FALSE)
ok(warn_only_ex$n_warn == 2L,
   "exemption does NOT silence warn rows — they stay visible")


cat("\n-- exemptions file validation -------------------------------------------\n")

write_ex <- function(entries, name) {
  p <- file.path(tmp, name)
  yaml::write_yaml(list(schema_version = 1, exempt_events = entries), p)
  p
}

ok(is.null(load_oob_exemptions(write_ex(
     list(list(variable = "x", reason = "because")), "ex_good.yml"))$error),
   "well-formed exemption loads")
ok(!is.null(load_oob_exemptions(write_ex(
     list(list(variable = "x")), "ex_noreason.yml"))$error),
   "reasonless exemption -> config error (cannot be a silent mute)")
ok(!is.null(load_oob_exemptions(write_ex(
     list(list(variable = "x", reason = "   ")), "ex_blank.yml"))$error),
   "whitespace-only reason -> config error")

p_broken <- file.path(tmp, "ex_broken.yml")
writeLines(c("exempt_events: [", "  - variable: x"), p_broken)
ok(!is.null(load_oob_exemptions(p_broken)$error),
   "unparseable exemptions file -> config error, never a silent pass")
ok(is.null(load_oob_exemptions(file.path(tmp, "absent.yml"))$error),
   "absent exemptions file is fine (means: nothing exempted)")

# The committed exemptions file must itself be valid.
ok(is.null(load_oob_exemptions()$error),
   "the repo's src/config/_audit/oob_exemptions.yml parses and validates")


cat("\n-- spec context ----------------------------------------------------------\n")

spec_dir <- file.path(tmp, "specs"); dir.create(spec_dir, showWarnings = FALSE)
yaml::write_yaml(list(
  missing_conventions = list(treat_as_na = list(codes = c(-1, 9, 94))),
  variables = list(
    list(id = "trust_x", type = "ordinal",
         missing = list(use_convention = "treat_as_na")),
    list(id = "age", type = "continuous",
         missing = list(use_convention = "treat_as_na", codes = c(999)))
  )
), file.path(spec_dir, "s.yml"))

sc <- load_spec_context(spec_dir = spec_dir)
ok(identical(unname(sc$types[["age"]]), "continuous"),
   "load_spec_context reads declared type")
ok(all(c(-1, 9, 94, 999) %in% sc$survey_missing),
   "load_spec_context unions convention + variable-level missing codes")
ok(999 %in% sc$var_missing[["age"]],
   "load_spec_context keeps per-variable missing codes")

# A variable's OWN codes must be subtracted, so its own convention can never
# explain away an event that got past that convention.
log_own <- write_log(mk_row("trust_x", "w1", 40, 94, 94, 1, 4), "own.csv")
res_own <- run_oob_triage("t", log_path = log_own, exemptions = list(),
                          spec_ctx = list(types = c(trust_x = "ordinal"),
                                          var_missing = list(trust_x = c(94)),
                                          survey_missing = c(94)),
                          write_report = FALSE)
ok(res_own$rows$class[1] != "sentinel_leak",
   "a code declared ONLY on this variable cannot excuse itself")

ok(load_spec_context(spec_dir = file.path(tmp, "no_such_dir"))$types |> length() == 0L,
   "absent spec dir -> empty context, no crash")


cat(sprintf("\n=== %d passed, %d failed ===\n", .pass, .fail))
quit(status = if (.fail > 0L) 1L else 0L)
