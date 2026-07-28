# MARPOR / CMP: per-manifesto BLM bootstrap standard errors
#
# Deliverable B of paper-bank 25 (papers/25-cmp/DATA-REQUEST.md).
#
# Output:
#   data/processed/marpor_manifesto_se.rds     (keyed party × edate)
#
# Implements Benoit, Laver & Mikhaylov (2009): each manifesto's coded
# quasi-sentences are treated as a multinomial draw across the CMP categories;
# the scale is recomputed on each of N resamples, and the SD of that bootstrap
# distribution is the per-manifesto standard error.
#
# A per-manifesto SE is a property of the CMP SOURCE DATA, not of any one
# paper's design — it is reusable by any future paper touching manifesto
# scaling, which is why it lives upstream here. AGGREGATION of these SEs into a
# corrected seat-weighted SD is paper-specific and stays in paper-bank.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE MULTINOMIAL N — and why it is `n_accounted`, not `total` and not `n_coded`
# ─────────────────────────────────────────────────────────────────────────────
# manifestoR::mp_bootstrap() has no N argument. It reads `row$total` and calls
#     rmultinom(N = total, prob = <cells matched by col_filter>)
# with a default col_filter of "^per(\\d{3}|\\d{4}|uncod)$" — i.e. the 56 parent
# categories PLUS `peruncod`. (The `per103_1`-style subcategory columns carry an
# underscore and are correctly excluded, so there is no double-counting.)
#
# In MPDS2025a the parents + `peruncod` sum to BELOW 100 in 19.5% of usable rows
# (docs/surveys/marpor.md, acceptance check 1): MPDS leaves some uncoded
# quasi-sentences out of `peruncod` entirely. So `total` overstates the base
# those cells actually account for, and drawing `total` sentences understates
# the sampling variance.
#
# Three internally consistent N/cell pairings exist. The N must match the cells
# it is being spread across:
#
#   scheme     N                                 cells               status
#   ---------  --------------------------------  ------------------  ----------
#   default    total                             parents + peruncod  manifestoR
#   ACCOUNTED  total * per_sum / 100             parents + peruncod  ► PRIMARY
#   CODED      total * sum(parents) / 100        parents only        sensitivity
#              (= the shipped `n_coded`)
#
# PRIMARY is `n_accounted`. It is BLM-faithful — BLM treat assignment to the
# uncoded category as a legitimate multinomial outcome, so `peruncod` stays in
# the cells — while fixing exactly the documented defect, because N is now the
# number of quasi-sentences those cells actually account for.
#
# ⚠️ REJECTED: N = `n_coded` with cells = parents + peruncod. An earlier draft of
# this module did that. It is inconsistent: `n_coded` has already removed the
# `peruncod` mass, yet `peruncod` is still left in as a cell absorbing draws, so
# the uncoded mass is discounted twice and the SE is inflated. Measured on a
# 400-row sample it runs ~1.5% above the manifestoR default at the median
# (~5.0% on affected rows) versus ~0.5% for PRIMARY — i.e. most of that gap was
# the bug, not the correction. Do not reinstate it.
#
# All three schemes ship, so the paper can report the choice as a robustness
# check rather than defend it in prose. They differ by <2% at the median.
#
# ─────────────────────────────────────────────────────────────────────────────
# Reproducibility
# ─────────────────────────────────────────────────────────────────────────────
# Each manifesto is seeded INDEPENDENTLY as BLM_SEED + row_index, so results are
# identical regardless of how many cores mclapply happens to use, and adding or
# removing a scheme does not perturb the others. Do not replace this with a
# single top-level set.seed() — that would make output core-count dependent.

library(here)
suppressPackageStartupMessages({
  library(dplyr)
  library(manifestoR)
  library(parallel)
})

source(here("src", "r", "data_prep_modules", "marpor", "0_load_marpor.R"))

# Reported in the paper — both must be citable.
BLM_SEED  <- 20260728
BLM_NREPS <- 1000

N_CORES <- max(1, min(detectCores() - 2, 10))

d <- readRDS(here("data", "processed", "marpor_party_election.rds"))
parents <- marpor_parent_categories(d)

dat <- d %>%
  filter(blm_usable, !is.na(total), total > 0) %>%
  mutate(n_accounted = round(total * per_sum / 100)) %>%
  filter(!is.na(n_accounted), n_accounted > 0,
         !is.na(n_coded),     n_coded     > 0)

cat(sprintf("\n── BLM bootstrap ──\n  %s manifestos | N = %d reps | seed = %d | cores = %d\n",
            format(nrow(dat), big.mark = ","), BLM_NREPS, BLM_SEED, N_CORES))
cat(sprintf("  excluded as un-bootstrappable: %s\n",
            format(nrow(d) - nrow(dat), big.mark = ",")))

CELLS_WITH_UNCOD <- "^per(\\d{3}|\\d{4}|uncod)$"   # manifestoR default
CELLS_PARENTS    <- "^per[0-9]{3}$"                # parents only

#' Bootstrap one manifesto under one N/cell scheme.
#'
#' Returns c(estimate, se). Seeded per-row so the result does not depend on
#' evaluation order or core count.
boot_one <- function(i, n_col, cells, scale) {
  row <- dat[i, ]
  row$total <- row[[n_col]]          # mp_bootstrap reads $total as the draw size
  set.seed(BLM_SEED + i)
  r <- if (identical(scale, "rile")) {
    mp_bootstrap(row, fun = rile, col_filter = cells,
                 N = BLM_NREPS, statistics = list(sd))
  } else {
    mp_bootstrap(row, fun = logit_rile, col_filter = cells,
                 N = BLM_NREPS, statistics = list(sd))
  }
  c(as.numeric(r[[1]]), as.numeric(r[["sd"]]))
}

run_scheme <- function(label, n_col, cells, scale = "rile") {
  t0 <- Sys.time()
  res <- mclapply(seq_len(nrow(dat)), boot_one,
                  n_col = n_col, cells = cells, scale = scale,
                  mc.cores = N_CORES)
  bad <- !vapply(res, function(x) is.numeric(x) && length(x) == 2L, logical(1))
  if (any(bad)) stop(sprintf("%s: %d rows failed to bootstrap", label, sum(bad)))
  m <- do.call(rbind, res)
  cat(sprintf("  %-28s %5.1f min\n", label,
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  list(est = m[, 1], se = m[, 2])
}

primary  <- run_scheme("rile / ACCOUNTED (primary)", "n_accounted", CELLS_WITH_UNCOD)
defaultS <- run_scheme("rile / manifestoR default",  "total",       CELLS_WITH_UNCOD)
codedS   <- run_scheme("rile / CODED (sensitivity)", "n_coded",     CELLS_PARENTS)

# logit_rile (Lowe et al. 2011) is a row-wise scale, so it bootstraps under the
# identical procedure at no extra design cost.
#
# ⚠️ It is here as a STAND-IN for the Franzmann–Kaiser SEs the DATA-REQUEST asked
# for "if cheap". FK is NOT cheap and not well defined per-manifesto: it needs
# country party-system base values estimated across the whole sample, so called
# on a single manifesto — inside or outside mp_bootstrap — it returns NaN. A
# joint bootstrap of the entire table would be required, which is a different
# estimand (each manifesto's SE would absorb other manifestos' resampling).
# FK point estimates on the full table remain computable; only the SEs are out.
logitS <- run_scheme("logit_rile / ACCOUNTED", "n_accounted", CELLS_WITH_UNCOD,
                     scale = "logit_rile")

out <- dat %>%
  transmute(
    country, countryname, party, partyname, partyabbrev, edate, eyear,
    total_mpds        = total,
    n_accounted,
    n_coded,
    peruncod,
    per_sum,
    rile,                                    # MPDS published value
    rile_boot         = primary$est,         # manifestoR::rile() recomputed from per*
    rile_se           = primary$se,          # ► PRIMARY SE
    rile_se_mrdefault = defaultS$se,         # sensitivity: manifestoR default N
    rile_se_coded     = codedS$se,           # sensitivity: parents-only cells
    logit_rile        = logitS$est,
    logit_rile_se     = logitS$se
  ) %>%
  mutate(rile_parity_gap  = abs(rile - rile_boot),
         rile_parity_flag = rile_parity_gap > 0.05)

# ─────────────────────────────────────────────────────────────────────────────
# PARITY: MPDS's published `rile` vs `rile` recomputed from the published per*
# ─────────────────────────────────────────────────────────────────────────────
# `rile_boot` is manifestoR::rile() evaluated on the ORIGINAL row, so it must
# reproduce the shipped `rile` to within MPDS's published rounding — unless MPDS
# itself is internally inconsistent.
#
# In MPDS2025a it is, for exactly 41 of 5,179 rows (0.79%), ALL of them Mexico,
# all from the 1998/2002 coding rounds (elections 1952–2000, worst in the 1990s;
# max gap 8.36 rile points). Mexico manifestos coded later — every 2010s row,
# 21 of 24 in the 2000s — reconcile to 0.001. So this is a source-side artifact
# of an early Mexico coding round, not a fault in the resample cells.
#
# ⚠️ `rile_se` is the SD of the RECOMPUTED rile across resamples. For flagged
# rows it therefore describes the dispersion of `rile_boot`, not of the shipped
# `rile`. Both levels ship so the paper can choose; see docs/surveys/marpor.md.
#
# The guard below is deliberately structural rather than a hard max: it trips on
# SYSTEMATIC breakage (a future release mangling the category block, or the
# defect spreading beyond one country) while tolerating the documented artifact.
PARITY_MAX_SHARE <- 0.015
n_bad         <- sum(out$rile_parity_flag)
share_bad     <- mean(out$rile_parity_flag)
countries_bad <- sort(unique(out$countryname[out$rile_parity_flag]))

cat(sprintf("\n  rile parity: %d rows (%.2f%%) above 0.05 | countries: %s | max gap %.3f\n",
            n_bad, 100 * share_bad,
            if (length(countries_bad)) paste(countries_bad, collapse = ", ") else "none",
            max(out$rile_parity_gap, na.rm = TRUE)))

if (share_bad > PARITY_MAX_SHARE) {
  stop(sprintf("rile parity: %.2f%% of rows exceed tolerance (limit %.2f%%) — the category block or the resample cells are wrong",
               100 * share_bad, 100 * PARITY_MAX_SHARE))
}
if (length(countries_bad) > 1) {
  stop(sprintf("rile parity: discrepancy is no longer confined to one country (%s) — investigate before shipping",
               paste(countries_bad, collapse = ", ")))
}

stopifnot(!any(duplicated(out[, c("party", "edate")])))

attr(out, "blm_seed")       <- BLM_SEED
attr(out, "blm_nreps")      <- BLM_NREPS
attr(out, "marpor_release") <- MARPOR_RELEASE
attr(out, "multinomial_n")  <- paste(
  "PRIMARY rile_se: N = n_accounted (= total * per_sum / 100),",
  "cells = 56 parent categories + peruncod.",
  "Per-row seed = blm_seed + row index.")

saveRDS(out, here("data", "processed", "marpor_manifesto_se.rds"))

cat(sprintf("\n  rows: %s\n", format(nrow(out), big.mark = ",")))
cat(sprintf("  rile_se        median %.3f | IQR %.3f–%.3f | max %.3f\n",
            median(out$rile_se), quantile(out$rile_se, .25),
            quantile(out$rile_se, .75), max(out$rile_se)))
# Scheme ratios are reported over rows with a NON-DEGENERATE denominator.
# A manifesto whose entire coded mass sits in categories outside the RILE index
# has rile = 0 in every resample, so its SE is exactly 0 under every scheme and
# the ratio is 0/0. MPDS2025a has one such row (Australia 1951, Country Party:
# per703 = 100). That is a correct result, not a failure — it is excluded from
# these summary ratios only, and ships with rile_se = 0 as it should.
ratio_vs <- function(num, den) {
  keep <- is.finite(num) & is.finite(den) & den > 0
  median(num[keep] / den[keep])
}
n_degen <- sum(out$rile_se == 0, na.rm = TRUE)
cat(sprintf("  vs manifestoR default : median ratio %.4f\n",
            ratio_vs(out$rile_se, out$rile_se_mrdefault)))
cat(sprintf("  vs CODED sensitivity  : median ratio %.4f\n",
            ratio_vs(out$rile_se, out$rile_se_coded)))
cat(sprintf("  degenerate (SE = 0, no RILE mass): %d\n", n_degen))
cat(sprintf("  logit_rile_se  median %.4f | non-finite %d\n",
            median(out$logit_rile_se[is.finite(out$logit_rile_se)]),
            sum(!is.finite(out$logit_rile_se))))
cat("  ->", here("data", "processed", "marpor_manifesto_se.rds"), "\n")
