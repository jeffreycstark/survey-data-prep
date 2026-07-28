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
cat("    => multinomial N for BLM is n_coded, NOT total. See docs/surveys/marpor.md\n")

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

# ─────────────────────────────────────────────────────────────────────────────
cat("\n\n══ TASK 0 — rule-change coverage table ══\n")

changes <- es %>% filter(rule_change) %>%
  select(country = country_cmp, election_date, year, system_family,
         prev_mag = mag_eff, delta_log_mag_eff, mag_eff)

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

cat("\n  Usable changes with a measurable continuous treatment:\n")
u <- cov %>% filter(usable) %>%
  select(country, year, n_pre, n_post, delta_log_mag_eff) %>%
  arrange(country, year)
print(as.data.frame(u), digits = 3, row.names = FALSE)

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
