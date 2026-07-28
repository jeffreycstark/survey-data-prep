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
# ⚠️ THE MULTINOMIAL N IS `n_coded`, NOT `total`
# ─────────────────────────────────────────────────────────────────────────────
# manifestoR::mp_bootstrap() reads `row$total` and calls
#     rmultinom(N, total, row_permute)
# In ~17% of MPDS2025a rows the per* categories sum to well below 100 because
# MPDS omits uncoded quasi-sentences from `peruncod` (see docs/surveys/marpor.md,
# acceptance check 1). For those manifestos `total` overstates the coded base,
# so drawing `total` sentences understates the sampling variance and returns
# SEs that are too SMALL.
#
# Measured on affected rows: SEs computed with n_coded are ~10% LARGER than
# with total. That is the conservative direction — it makes the paper's
# dispersion result harder to obtain, not easier.
#
# mp_bootstrap has no N argument, so we substitute the column it reads:
#     dat$total <- dat$n_coded
# This is deliberate. Do not "fix" it back.

library(here)
suppressPackageStartupMessages({
  library(dplyr)
  library(manifestoR)
})

source(here("src", "r", "data_prep_modules", "marpor", "0_load_marpor.R"))

# Reported in the paper — both must be citable.
BLM_SEED  <- 20260728
BLM_NREPS <- 1000

d <- readRDS(here("data", "processed", "marpor_party_election.rds"))

dat <- d %>% filter(blm_usable, !is.na(n_coded), n_coded > 0)
cat(sprintf("\n── BLM bootstrap ──\n  %s manifestos | N = %d reps | seed = %d\n",
            format(nrow(dat), big.mark = ","), BLM_NREPS, BLM_SEED))
cat(sprintf("  excluded as un-bootstrappable: %s\n",
            format(nrow(d) - nrow(dat), big.mark = ",")))

# THE CORRECTION — see header.
dat$total <- dat$n_coded

t0 <- Sys.time()
set.seed(BLM_SEED)
boot_rile <- mp_bootstrap(dat, fun = rile, N = BLM_NREPS, statistics = list(sd))
cat(sprintf("  rile bootstrap: %.1f min\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))

out <- dat %>%
  select(country, countryname, party, partyname, edate, eyear,
         total_qs = n_coded, total_mpds = total) %>%
  mutate(rile     = boot_rile$rile,
         rile_se  = boot_rile$sd)

# Franzmann–Kaiser is the paper's robustness scaling. It is attempted but NOT
# allowed to block Deliverable B: FK is estimated relative to country-specific
# base values across the whole dataset, so a row-wise multinomial resample is
# not guaranteed to be well defined. If it fails, that is recorded and rile
# ships alone.
fk_ok <- FALSE
fk_msg <- ""
try({
  set.seed(BLM_SEED)
  boot_fk <- mp_bootstrap(dat, fun = franzmann_kaiser,
                          N = BLM_NREPS, statistics = list(sd))
  out$fk    <- boot_fk[[1]]
  out$fk_se <- boot_fk$sd
  fk_ok <- TRUE
}, silent = TRUE)
if (!fk_ok) {
  fk_msg <- "Franzmann-Kaiser bootstrap unavailable (row-wise resample not well defined for a country-baseline scale); rile only."
  cat("  ⚠️ ", fk_msg, "\n")
}

attr(out, "blm_seed")    <- BLM_SEED
attr(out, "blm_nreps")   <- BLM_NREPS
attr(out, "marpor_release") <- MARPOR_RELEASE
attr(out, "multinomial_n")  <- "n_coded (= total * sum(parent per*) / 100), NOT MPDS `total`"
attr(out, "fk_note")     <- fk_msg

stopifnot(!any(duplicated(out[, c("party", "edate")])))
saveRDS(out, here("data", "processed", "marpor_manifesto_se.rds"))

cat(sprintf("\n  rows: %s | rile_se: median %.2f, IQR %.2f–%.2f, max %.2f\n",
            format(nrow(out), big.mark = ","),
            median(out$rile_se, na.rm = TRUE),
            quantile(out$rile_se, .25, na.rm = TRUE),
            quantile(out$rile_se, .75, na.rm = TRUE),
            max(out$rile_se, na.rm = TRUE)))
cat("  Franzmann-Kaiser SEs:", if (fk_ok) "included" else "NOT included", "\n")
cat("  ->", here("data", "processed", "marpor_manifesto_se.rds"), "\n")
