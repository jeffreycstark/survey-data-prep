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

cat(sprintf("\n%d passed, %d failed\n", .pass, .fail))
quit(status = if (.fail > 0L) 1L else 0L)
