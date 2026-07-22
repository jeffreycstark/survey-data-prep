#!/usr/bin/env Rscript
# src/r/audit/test_bin_width_parity.R
#
# Fault-injection tests for Check D (bin-width parity).
# Run:  Rscript src/r/audit/test_bin_width_parity.R
# Exit: 0 if all pass, 1 otherwise.

suppressPackageStartupMessages({ library(here) })
source(here::here("src", "r", "audit", "04_bin_width_parity.R"))

.pass <- 0L; .fail <- 0L
ok <- function(cond, msg) {
  if (isTRUE(cond)) { .pass <<- .pass + 1L; cat(sprintf("  PASS  %s\n", msg)) }
  else              { .fail <<- .fail + 1L; cat(sprintf("  FAIL  %s\n", msg)) }
}

# Synthetic registry (real fns from recoding.R are already sourced).
REG <- list(
  safe_6pt_to_4pt = list(fn = "safe_6pt_to_4pt", input_scale = c(1, 6),
                         output_scale = c(1, 4), reverses = TRUE,
                         monotonic = TRUE, requires_data = FALSE),
  safe_reverse_4pt = list(fn = "safe_reverse_4pt", input_scale = c(1, 4),
                          output_scale = c(1, 4), reverses = TRUE,
                          monotonic = TRUE, requires_data = FALSE),
  cond_flip = list(fn = "cond_flip", input_scale = c(1, 4),
                   output_scale = c(1, 4), reverses = TRUE,
                   monotonic = FALSE, requires_data = TRUE)
)

mkvar <- function(id, source, exceptions = list(),
                  scale = list(min = 1, max = 4)) {
  list(id = id, type = "ordinal", source = source, scale = scale,
       harmonize = list(default = list(method = "identity"),
                        exceptions = exceptions))
}

cat("=== D1: ABS-W5-class seam -> parity_error on the collapsing wave ===\n")
vs <- mkvar("toy_trust",
            source = list(w1 = "q1", w2 = "q1", w5 = "q1"),
            exceptions = list(
              w5 = list(method = "r_function", fn = "safe_6pt_to_4pt")))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(df$status[df$wave == "w5"] == "parity_error", "w5 flagged parity_error")
ok(df$signature[df$wave == "w5"] == "4:2|3:1|2:1|1:2",
   "w5 signature is 4:2|3:1|2:1|1:2")
ok(all(df$status[df$wave %in% c("w1", "w2")] == "ok"),
   "identity waves stay ok")
ok(all(df$signature[df$wave %in% c("w1", "w2")] == "4:1|3:1|2:1|1:1"),
   "identity signature is 4:1|3:1|2:1|1:1")

cat("\n=== D2: uniform collapse in ALL waves -> ok (comparability kept) ===\n")
vs <- mkvar("toy_uniform",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w1 = list(method = "r_function", fn = "safe_6pt_to_4pt"),
              w2 = list(method = "r_function", fn = "safe_6pt_to_4pt")))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(all(df$status == "ok"), "uniform 6->4 collapse everywhere is ok")

cat("\n=== D3: pure reversal vs identity -> identical signatures, ok ===\n")
vs <- mkvar("toy_reverse",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w2 = list(method = "r_function", fn = "safe_reverse_4pt")))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(all(df$status == "ok"), "reversal has all-1 widths -> no finding")

cat("\n=== D4: requires_data fn -> skip; lone remaining wave -> ok ===\n")
vs <- mkvar("toy_cond",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w2 = list(method = "r_function", fn = "cond_flip")))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(df$status[df$wave == "w2"] == "skip", "requires_data fn skips")
ok(df$status[df$wave == "w1"] == "ok", "single usable wave is ok")

cat("\n=== D5: method:recode merged bin -> parity_error (no registry) ===\n")
vs <- mkvar("toy_recode",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w2 = list(method = "recode",
                        mapping = list(`1` = 1, `2` = 1, `3` = 2, `4` = 3))))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(df$status[df$wave == "w2"] == "parity_error",
   "explicit merged mapping flagged")
ok(df$signature[df$wave == "w2"] == "3:1|2:1|1:2",
   "recode signature counts widths from mapping")

cat("\n=== D6: midpoint-drop recode (5 -> NA) -> NOT an error ===\n")
vs <- mkvar("toy_middrop",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w1 = list(method = "recode",
                        mapping = list(`1` = 1, `2` = 2, `3` = 3, `4` = 4,
                                       `5` = NULL))))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(all(df$status == "ok"),
   "dropping a midpoint to NA keeps all widths 1 -> ok")

cat("\n=== D6b: all-width-1 cardinality drift -> warn, not error ===\n")
vs <- mkvar("toy_drift",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w1 = list(method = "recode",
                        mapping = list(`1` = 1, `2` = 2, `3` = 3))))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(df$status[df$wave == "w1"] == "warn",
   "3-target vs 4-target with all widths 1 warns")
ok(df$status[df$wave == "w2"] == "ok", "modal wave stays ok")

cat("\n=== D7: unknown fn -> no_registry_entry ===\n")
vs <- mkvar("toy_unknown",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w2 = list(method = "r_function", fn = "not_a_real_fn")))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(df$status[df$wave == "w2"] == "no_registry_entry",
   "missing registry entry surfaced")

cat("\n=== D8: exemption downgrades computed statuses to ok_exempt ===\n")
vs <- mkvar("toy_trust",
            source = list(w1 = "q1", w5 = "q1"),
            exceptions = list(
              w5 = list(method = "r_function", fn = "safe_6pt_to_4pt")))
df <- compute_bin_width_for_var(vs, "toy", REG, exempt_ids = "toy_trust")
ok(all(df$status == "ok_exempt"), "exempted variable rows are ok_exempt")
ok(grepl("parity_error", df$message[df$wave == "w5"]),
   "exempt row message preserves the computed status")

cat("\n=== D9: survey-level API on real ABS specs ===\n")
abs_df <- compute_bin_width_parity("abs")
ok(nrow(abs_df) > 0, "abs sweep produced rows")
TRUST13 <- c("trust_president", "trust_courts", "trust_national_government",
             "trust_political_parties", "trust_parliament",
             "trust_civil_service", "trust_military", "trust_police",
             "trust_local_government", "trust_election_commission",
             "trust_newspapers", "trust_ngos", "trust_television")
err_vars <- unique(abs_df$variable[abs_df$status == "parity_error"])
ok(all(TRUST13 %in% err_vars),
   "all 13 W5 trust-battery items flagged parity_error")
# Pinned expectation from the triaged 2026-07-22 sweep (56 rows / 41 vars).
# If this fails after an exemption or spec fix, update deliberately — this
# pin exists so the visible-findings set only changes by editorial act.
EXPECTED_ABS_ERR <- sort(c(
  TRUST13,
  "community_leader_contact", "corrupt_local_govt", "corrupt_national_govt",
  "corrupt_witnessed", "current_status_unemployed", "econ_family_income_fair",
  "gate_contact_civil_servant", "gate_contact_elected",
  "gate_contact_influential", "gate_contact_media", "gate_demonstration",
  "gate_petition", "glob_cultural_defense", "glob_trade_protection",
  "gov_elections_real_choice", "govt_anticorrupt_effort",
  "govt_withholds_info", "hh_income_sat", "intl_china_world_influence",
  "intl_usa_world_influence", "news_internet", "pol_discuss",
  "procedural_preference_index", "sm_express_political",
  "trust_acquaintances", "trust_neighbors", "trust_relatives",
  "trust_strangers"))
ok(identical(sort(err_vars), EXPECTED_ABS_ERR),
   "ABS parity_error set exactly matches pinned expectation (41 vars)")
trust_err <- abs_df[abs_df$status == "parity_error" &
                    abs_df$variable %in% TRUST13, ]
ok(all(trust_err$wave == "w5"), "trust flags are w5 rows only")
ok(all(trust_err$signature == "4:2|3:1|2:1|1:2"),
   "trust w5 signatures all 4:2|3:1|2:1|1:2")

cat("\n=== D10: exemption file round-trip via tempfile ===\n")
tmp_ex <- tempfile(fileext = ".yml")
writeLines(c(
  "schema_version: 1",
  "exempt_variables:",
  "  - variable: trust_military",
  "    survey: abs",
  "    reason: test"), tmp_ex)
ids <- load_bin_width_exemptions("abs", tmp_ex)
ok(identical(ids, "trust_military"), "survey-matched exemption loads")
ok(length(load_bin_width_exemptions("kgss", tmp_ex)) == 0,
   "survey-restricted exemption does not leak to other surveys")

cat(sprintf("\n%d passed, %d failed\n", .pass, .fail))
quit(status = if (.fail > 0L) 1L else 0L)
