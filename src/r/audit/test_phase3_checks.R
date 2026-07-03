#!/usr/bin/env Rscript
# src/r/audit/test_phase3_checks.R
#
# Phase 3 tests: battery-coherence hints (Check B).
#
# Includes the plan's regression fixture: a sign-flipped battery item must
# produce a `hint`, both on synthetic data and on the real ABS output with
# system_deserves_support re-flipped to its pre-fix (ebe4f00^) state.
#
# Run:  Rscript src/r/audit/test_phase3_checks.R
# Exit: 0 if all pass, 1 otherwise.

suppressPackageStartupMessages({ library(here) })
source(here::here("src", "r", "audit", "04_battery_coherence.R"))

.pass <- 0L; .fail <- 0L
ok <- function(cond, msg) {
  if (isTRUE(cond)) { .pass <<- .pass + 1L; cat(sprintf("  PASS  %s\n", msg)) }
  else              { .fail <<- .fail + 1L; cat(sprintf("  FAIL  %s\n", msg)) }
}

cat("=== 3a: stem-battery extraction (synthetic verbatim) ===\n")
vb <- data.frame(
  wave = c("w1", "w1", "w1", "w1", "w1", "w1", "w1", "w2", "w2", "w2"),
  harmonized_name = c("i1", "i2", "i3", "i4", "solo", "p1", "p2",
                      "i1", "i2", "i3"),
  stem_text = c("How much do you agree with:",
                "How  much do you agree with: ",   # whitespace variant
                "How much do you agree with:",
                "How much do you agree with:",
                "",
                "Short battery stem", "Short battery stem",
                rep("How much do you agree with:", 3)),
  notes = c("", "", "", "Not included in this wave", "", "", "",
            "", "", ""),
  stringsAsFactors = FALSE
)
sb <- build_stem_batteries(vb)
ok(length(unique(sb$battery_id)) == 2, "two batteries (one per wave)")
w1b <- sb[sb$wave == "w1", ]
ok(setequal(w1b$variable, c("i1", "i2", "i3")),
   "w1 battery = i1,i2,i3 (whitespace-normalized; 'Not included' + stemless + size-2 stem excluded)")
ok(!any(sb$variable %in% c("solo", "p1", "p2", "i4")),
   "excluded items appear in no battery")

cat("\n=== 3b: sign-flipped item -> hint (synthetic harmonized) ===\n")
set.seed(42)
n <- 400
latent <- rnorm(n)
mk4 <- function() pmin(4, pmax(1, round(2.8 + 0.8 * latent + rnorm(n, 0, 0.5))))
raw <- list(i1 = mk4(), i2 = mk4(), i3 = mk4(), i4 = mk4())
batt <- tibble::tibble(
  battery_id = "stem:w1#01", battery_source = "stem",
  stem_excerpt = "synthetic agree battery", wave = "w1",
  wave_key = .canon_wave("w1"), variable = c("i1", "i2", "i3", "i4")
)

h_ok <- data.frame(wave = 1L, raw)
res_ok <- compute_battery_coherence("synthetic", harmonized = h_ok, batteries = batt)
ok(all(res_ok$status == "ok"), "coherent battery: all items ok")

h_flip <- h_ok
h_flip$i4 <- 5 - h_flip$i4
res_flip <- compute_battery_coherence("synthetic", harmonized = h_flip, batteries = batt)
i4 <- res_flip[res_flip$variable == "i4", ]
ok(identical(i4$status, "hint"), "flipped item -> hint")
ok(isTRUE(i4$neg_corr), "flipped item: neg_corr signal fired")
ok(all(res_flip$status[res_flip$variable != "i4"] == "ok"),
   "battery-mates of the flipped item stay ok (hint localizes the culprit)")

cat("\n=== 3c: mean-outlier signal in isolation (MAD~0 fallback) ===\n")
h_shift <- h_ok
h_shift$i4 <- pmin(4, h_ok$i1 + 1)   # positively correlated, mean shifted up ~1
res_shift <- compute_battery_coherence("synthetic", harmonized = h_shift, batteries = batt)
i4s <- res_shift[res_shift$variable == "i4", ]
ok(identical(i4s$status, "hint"), "mean-shifted item -> hint")
ok(isTRUE(i4s$mean_outlier) && !isTRUE(i4s$neg_corr),
   "mean_outlier fired without neg_corr (MAD~0 deviation fallback)")

cat("\n=== 3d: concept-fallback grouping (injected concept map) ===\n")
set.seed(7)
h2 <- data.frame(
  wave = 1L,
  a = sample(1:4, n, replace = TRUE), b = sample(1:4, n, replace = TRUE),
  c = sample(1:4, n, replace = TRUE),
  d = sample(0:10, n, replace = TRUE), e = sample(0:10, n, replace = TRUE),
  f = sample(1:4, n, replace = TRUE)
)
cm <- tibble::tibble(
  variable = c("a", "b", "c", "d", "e", "f"),
  concept = c("trust", "trust", "trust", "trust", "trust", "other"),
  type = c("ordinal", "ordinal", "ordinal", "continuous", "continuous", "ordinal")
)
cb <- build_concept_batteries("synthetic", h2, concept_map = cm)
ok(length(unique(cb$battery_id)) == 1, "exactly one concept battery")
ok(setequal(cb$variable, c("a", "b", "c")),
   "1..4 trust trio grouped; 0..10 pair (size 2) and lone 'other' excluded")
cb_ex <- build_concept_batteries("synthetic", h2, exclude = "a", concept_map = cm)
ok(nrow(cb_ex) == 0, "exclude= removes stem-covered vars before grouping")

cat("\n=== 3e: ABS regression — pre-fix system_deserves_support flagged ===\n")
abs_path <- here::here("data", "processed", "abs_harmonized.rds")
if (!file.exists(abs_path)) {
  cat("  SKIP  abs_harmonized.rds not found — integration regression not run\n")
} else {
  h <- readRDS(abs_path)
  vb_abs <- load_verbatim_items("abs")
  sb_abs <- build_stem_batteries(vb_abs)
  sys_ids <- unique(sb_abs$battery_id[sb_abs$variable == "system_deserves_support"])
  ok(length(sys_ids) > 0, "system_deserves_support belongs to >=1 stem battery")
  sys_batt <- sb_abs[sb_abs$battery_id %in% sys_ids, ]
  ok(!"system_needs_change" %in% sys_batt$variable,
     "intentional opposite system_needs_change NOT in the stem battery")

  res_cur <- compute_battery_coherence("abs", harmonized = h, batteries = sys_batt)
  cur <- res_cur[res_cur$variable == "system_deserves_support" &
                 !res_cur$status %in% c("skip", "na"), ]
  ok(nrow(cur) > 0 && all(cur$status == "ok"),
     sprintf("current (fixed) data: ok in all %d evaluated wave(s)", nrow(cur)))

  h_bug <- h
  h_bug$system_deserves_support <- 5 - h_bug$system_deserves_support
  res_bug <- compute_battery_coherence("abs", harmonized = h_bug, batteries = sys_batt)
  bug <- res_bug[res_bug$variable == "system_deserves_support" &
                 !res_bug$status %in% c("skip", "na"), ]
  ok(nrow(bug) > 0 && all(bug$status == "hint" & bug$neg_corr),
     "pre-fix state (5-x): hint with neg_corr in every evaluated wave")
  mates <- res_bug[res_bug$variable %in% c("system_capable", "system_prefer",
                                           "system_proud") &
                   !res_bug$status %in% c("skip", "na"), ]
  ok(nrow(mates) > 0 && all(mates$status == "ok"),
     "battery-mates stay ok under the bug (culprit is isolated)")
}

cat(sprintf("\n=== %d passed, %d failed ===\n", .pass, .fail))
if (.fail > 0L) quit(status = 1L) else quit(status = 0L)
