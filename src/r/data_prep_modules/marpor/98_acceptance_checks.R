# MARPOR / CMP: DATA-REQUEST §7 acceptance checks + TASK 0 feasibility gate table
#
# Re-runnable evidence for paper-bank 25's TASK 0 gate. Prints the §7 checks and
# writes the full rule-change coverage table the CC brief asks for:
#   change | country | year | pre-elections | post-elections | Δ log eff. magnitude
#
# Output:
#   outputs/marpor/task0_rule_change_coverage.csv
#
# Gate condition (from the brief):
#   >= 8 usable changes (>=3 CMP-covered pre and >=2 post) -> proceed
#   5-7  -> proceed, but the position null MUST be reported as underpowered
#   < 5  -> stop; the design collapses
#
# Event-time convention: t = 0 is the FIRST election held under the new rule.
# "post" therefore INCLUDES t = 0; "pre" is strictly before it.

library(here)
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

cmp <- readRDS(here("data", "processed", "marpor_party_election.rds"))
es  <- readRDS(here("data", "processed", "electoral_systems.rds"))

# ── DES → CMP country-name crosswalk ────────────────────────────────────────
# Only 6 CMP countries fail an exact-name join to DES. Azerbaijan and Northern
# Ireland have no DES counterpart at all (the latter is inside the UK in DES but
# coded separately in CMP), so they are unmatchable rather than mis-mapped.
des_to_cmp <- c(
  "Bosnia"                   = "Bosnia-Herzegovina",
  "Macedonia"                = "North Macedonia",
  "United States of America" = "United States",
  "Greek Cyprus"             = "Cyprus"
)
es <- es %>%
  mutate(country_cmp = trimws(country),
         country_cmp = ifelse(country_cmp %in% names(des_to_cmp),
                              des_to_cmp[country_cmp], country_cmp))

cmp_el <- cmp %>%
  distinct(countryname, edate) %>%
  mutate(countryname = trimws(countryname),
         edate = as.Date(edate))

# ─────────────────────────────────────────────────────────────────────────────
cat("\n══ DATA-REQUEST §7 acceptance checks ══\n")

parents <- grep("^per[0-9]{3}$", names(cmp), value = TRUE)

## 1 — per* parity
cat("\n[1] per* row sums (56 parent categories + peruncod)\n")
s <- cmp$per_sum
cat(sprintf("    within 99-101 : %5d (%.1f%%)\n", sum(s > 99 & s < 101), 100*mean(s > 99 & s < 101)))
cat(sprintf("    below 100     : %5d (%.1f%%)  <- MPDS omits uncoded mass from peruncod\n",
            sum(s != 0 & s <= 99), 100*mean(s != 0 & s <= 99)))
cat(sprintf("    exactly 0     : %5d (%.1f%%)  <- uncoded manifestos\n", sum(s == 0), 100*mean(s == 0)))
cat("    => multinomial N for BLM is n_accounted (= total * per_sum / 100), NOT total.\n")
cat("       n_coded is correct ONLY with parents-only cells; it ships that way as the\n")
cat("       rile_se_coded sensitivity column. See docs/surveys/marpor.md.\n")

## 2 — quasi-sentence total
cat("\n[2] quasi-sentence total (column name in this release: `total`)\n")
cat(sprintf("    missing : %d (%.2f%%)\n", sum(is.na(cmp$total)), 100*mean(is.na(cmp$total))))
cat(sprintf("    BLM-usable rows: %d (%.2f%%)\n", sum(cmp$blm_usable), 100*mean(cmp$blm_usable)))

## 3 — absseat / totseats missingness by country
cat("\n[3] absseat missingness (worst 8 countries with >=5 elections)\n")
miss <- cmp %>%
  group_by(countryname) %>%
  summarise(n_elec = n_distinct(edate), absseat_miss = mean(is.na(absseat)), .groups="drop") %>%
  filter(n_elec >= 5) %>% arrange(desc(absseat_miss))
print(as.data.frame(head(miss, 8)), digits = 3, row.names = FALSE)
cat(sprintf("    overall absseat missing: %.2f%% | totseats: %.2f%%\n",
            100*mean(is.na(cmp$absseat)), 100*mean(is.na(cmp$totseats))))

## 4 — Deliverable B integrity
#
# These checks postdate the SE file. They are here so a re-run validates what
# 2_bootstrap_manifesto_se.R actually produced rather than assuming it.
cat("\n[4] Deliverable B — marpor_manifesto_se.rds\n")
se_path <- here("data", "processed", "marpor_manifesto_se.rds")
if (!file.exists(se_path)) {
  cat("    ⚠️ NOT BUILT. Run 2_bootstrap_manifesto_se.R (~10 min).\n")
} else {
  se <- readRDS(se_path)
  cat(sprintf("    rows: %d | expected (blm_usable & total>0): %d\n",
              nrow(se), sum(cmp$blm_usable & !is.na(cmp$total) & cmp$total > 0)))
  cat(sprintf("    key unique (party x edate): %s\n",
              !any(duplicated(se[, c("party", "edate")]))))
  cat(sprintf("    seed: %s | reps: %s\n",
              attr(se, "blm_seed"), attr(se, "blm_nreps")))

  # The bootstrap's own point estimate must reproduce MPDS's published rile.
  # It does not everywhere — see docs/surveys/marpor.md. Surfaced, not hidden.
  nbad <- sum(se$rile_parity_flag, na.rm = TRUE)
  cbad <- sort(unique(se$countryname[se$rile_parity_flag]))
  cat(sprintf("    rile parity breaches: %d (%.2f%%) | countries: %s | max gap %.3f\n",
              nbad, 100*mean(se$rile_parity_flag), paste(cbad, collapse = ", "),
              max(se$rile_parity_gap, na.rm = TRUE)))

  ok_ratio <- function(n, d) { k <- is.finite(n) & is.finite(d) & d > 0; median(n[k]/d[k]) }
  cat(sprintf("    rile_se median %.3f | vs manifestoR default %.4f | vs CODED %.4f\n",
              median(se$rile_se, na.rm = TRUE),
              ok_ratio(se$rile_se, se$rile_se_mrdefault),
              ok_ratio(se$rile_se, se$rile_se_coded)))
  cat(sprintf("    degenerate (SE = 0, no RILE mass): %d | logit_rile_se non-finite: %d\n",
              sum(se$rile_se == 0, na.rm = TRUE), sum(!is.finite(se$logit_rile_se))))

  if (nrow(se) != sum(cmp$blm_usable & !is.na(cmp$total) & cmp$total > 0)) {
    cat("    ⚠️ ROW COUNT MISMATCH — the SE file is stale relative to Deliverable A.\n")
  }
}

# ─────────────────────────────────────────────────────────────────────────────
cat("\n\n══ TASK 0 — rule-change coverage table ══\n")

# ⚠️ `mag_eff` on a rule-change row is the magnitude of the FIRST election under
# the NEW rule (t = 0), i.e. POST-change. An earlier version of this line read
#     select(prev_mag = mag_eff, ..., mag_eff)
# which dplyr dedupes to a single column, shipping the post-change value in the
# CSV under the name `prev_mag`. That is not a cosmetic mislabel — a paper-side
# consumer differencing against `prev_mag` would difference a value against
# itself. Verified: `prev_mag` matched `mag_eff` to 4e-13 across all 134 rows.
# The pre-change magnitude is recovered from the treatment itself, since
# delta_log_mag_eff = log(post) - log(pre).
changes <- es %>% filter(rule_change) %>%
  select(country = country_cmp, election_date, year, system_family,
         mag_eff_post = mag_eff, delta_log_mag_eff) %>%
  mutate(mag_eff_pre = mag_eff_post / exp(delta_log_mag_eff)) %>%
  relocate(mag_eff_pre, .before = mag_eff_post)

cov <- changes %>%
  rowwise() %>%
  mutate(
    n_pre  = sum(cmp_el$countryname == country & cmp_el$edate <  election_date),
    n_post = sum(cmp_el$countryname == country & cmp_el$edate >= election_date),
    cmp_country = any(cmp_el$countryname == country)
  ) %>%
  ungroup() %>%
  mutate(usable = cmp_country & n_pre >= 3 & n_post >= 2) %>%
  arrange(desc(usable), country, election_date)

dir.create(here("outputs", "marpor"), showWarnings = FALSE, recursive = TRUE)
write.csv(cov, here("outputs", "marpor", "task0_rule_change_coverage.csv"), row.names = FALSE)

n_usable <- sum(cov$usable)
cat(sprintf("\n  DES rule changes total          : %d\n", nrow(cov)))
cat(sprintf("  ...in CMP-covered countries      : %d\n", sum(cov$cmp_country)))
cat(sprintf("  ...USABLE (>=3 pre, >=2 post)    : %d\n", n_usable))

# ⚠️ The gate counts usable CHANGES, but the paper codes treatment CONTINUOUSLY
# as Δ log effective magnitude. A structural rule change that leaves effective
# magnitude unmoved (Δ = 0) contributes NO identifying variation to that
# specification, so it should not be counted toward the paper's effective N.
n_nonzero <- sum(cov$usable & !is.na(cov$delta_log_mag_eff) & cov$delta_log_mag_eff != 0)
n_zero    <- sum(cov$usable & !is.na(cov$delta_log_mag_eff) & cov$delta_log_mag_eff == 0)
n_na      <- sum(cov$usable & is.na(cov$delta_log_mag_eff))

verdict <- if (n_usable >= 8) "PASS — proceed to TASK 1" else
           if (n_usable >= 5) "CONDITIONAL — proceed, but report the position null as UNDERPOWERED" else
           "FAIL — stop; do not substitute a different design"
cat(sprintf("\n  GATE VERDICT: %s\n", verdict))
cat(sprintf("\n  ⚠️ Of the %d usable changes, only %d move effective magnitude:\n", n_usable, n_nonzero))
cat(sprintf("       %d have delta_log_mag_eff == 0 (rule structure changed, magnitude did not)\n", n_zero))
cat(sprintf("       %d have delta_log_mag_eff == NA\n", n_na))
cat(sprintf("     Under the brief's CONTINUOUS treatment coding, the effective N is %d, not %d.\n",
            n_nonzero, n_usable))

# The header used to promise "measurable continuous treatment" while the filter
# was `usable` alone, so it printed all 49 rows — including the 13 zeros and the
# NA that the warning two lines above had just excluded. Counting the printed
# list gave 49 and contradicted the stated effective N of 35.
cat(sprintf("\n  The %d usable changes that MOVE effective magnitude (the paper's actual N):\n",
            n_nonzero))
u <- cov %>%
  filter(usable, !is.na(delta_log_mag_eff), delta_log_mag_eff != 0) %>%
  select(country, year, n_pre, n_post, mag_eff_pre, mag_eff_post, delta_log_mag_eff) %>%
  arrange(country, year)
print(as.data.frame(u), digits = 3, row.names = FALSE)

cat(sprintf("\n  EXCLUDED from the continuous specification (%d):\n", n_zero + n_na))
x <- cov %>%
  filter(usable, is.na(delta_log_mag_eff) | delta_log_mag_eff == 0) %>%
  transmute(country, year, n_pre, n_post,
            reason = ifelse(is.na(delta_log_mag_eff),
                            "magnitude unavailable (NA)",
                            "rule changed, magnitude did not")) %>%
  arrange(country, year)
print(as.data.frame(x), row.names = FALSE)

## France verdict — called out separately, per the brief
cat("\n  ── France 1986/1988 reversal (brief asks for this explicitly) ──\n")
fr <- cov %>% filter(country == "France", year %in% c(1986, 1988))
if (nrow(fr) == 0) {
  cat("    ⚠️ NOT flagged as a rule change by DES structural fields — check manually.\n")
} else {
  print(as.data.frame(fr %>% select(year, n_pre, n_post, delta_log_mag_eff, usable)),
        digits = 3, row.names = FALSE)
}
cat("\n  -> ", here("outputs", "marpor", "task0_rule_change_coverage.csv"), "\n")
