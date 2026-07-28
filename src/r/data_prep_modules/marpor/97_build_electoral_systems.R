# Electoral systems / district magnitude table
#
# Deliverable C of paper-bank 25 (papers/25-cmp/DATA-REQUEST.md).
#
# Output:
#   data/processed/electoral_systems.rds
#
# Unit: country × election (LEGISLATIVE, lower chamber).
#
# Sources, in the priority order the request specifies:
#   1. CLEA lower chamber — data/processed/clea_lc_20251015.RData (already in
#      repo). Constituency-level; aggregated here to observed district
#      magnitude. CLEA represents upper tiers inconsistently, so magnitude from
#      CLEA ALONE is wrong for mixed systems — which is exactly where several
#      treatment cases sit (Japan 1996, Italy, New Zealand 1996).
#   2. Bormann & Golder, Democratic Electoral Systems v5.0
#      (mattgolder.com, 1919–2021) — system family, tier structure, upper-tier
#      seats. This is the SPINE of the table; CLEA is joined on as a
#      cross-check.
#
# ─────────────────────────────────────────────────────────────────────────────
# ⚠️ DES USES -99 / -88 AS MISSING SENTINELS, NOT NA
# ─────────────────────────────────────────────────────────────────────────────
# seats, tier1_avemag, tier1_districts, upperseats, uppertier, enep and enpp all
# carry -99 (and tier1_avemag/tier2_districts also -88) for missing. Taking
# log() of an uncleaned magnitude silently yields NaN, and any mean over the raw
# column is nonsense. They are converted to NA below. Do not remove that step.
#
# ─────────────────────────────────────────────────────────────────────────────
# KNOWN GAP: legal threshold
# ─────────────────────────────────────────────────────────────────────────────
# The request asks for legal threshold. DES v5.0 does NOT carry a threshold
# column (verified against the v5.0 release schema — 50 columns, none is a
# threshold). It is therefore ABSENT from this table rather than silently
# imputed. If the paper needs it, it has to come from another source
# (e.g. Carey/Hix, or hand-coding for the treatment cases only).

library(here)
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

DES_VERSION <- "v5.0"
DES_PATH <- here("data", "electoral_systems", "raw",
                 "bormann_golder_des_v50", "es_data-v5_0.csv")

# ── 1. DES spine ────────────────────────────────────────────────────────────
des <- read.csv(DES_PATH, stringsAsFactors = FALSE)

# Legislative lower-chamber elections only.
des <- des %>% filter(presidential == 0)

sentinel_to_na <- function(x) ifelse(x %in% c(-99, -88), NA_real_, x)
num_cols <- c("seats", "tier1_avemag", "tier1_districts", "upperseats",
              "uppertier", "tier2_districts", "tier3_districts",
              "tier4_districts", "enep", "enpp", "majority_bonus")
num_cols <- num_cols[num_cols %in% names(des)]
des <- des %>% mutate(across(all_of(num_cols), ~ sentinel_to_na(as.numeric(.x))))

# year/month/day arrive as character in the v5.0 CSV — coerce before use.
des <- des %>%
  mutate(across(c(year, month, day), ~ suppressWarnings(as.integer(as.character(.x)))))

des <- des %>%
  mutate(
    election_date = as.Date(sprintf("%04d-%02d-%02d", year, month, day)),
    system_family = recode(as.character(legislative_type),
                           "1" = "majoritarian", "2" = "proportional",
                           "3" = "mixed", .default = NA_character_),
    # Upper-tier magnitude: the compensatory tier is usually a single national
    # district, in which case tier2_districts is 0/1 and M_upper = upperseats.
    n_districts_upper = ifelse(!is.na(tier2_districts) & tier2_districts > 0,
                               tier2_districts, 1),
    mag_upper  = ifelse(!is.na(upperseats) & upperseats > 0,
                        upperseats / n_districts_upper, NA_real_),
    seats_tier1 = ifelse(!is.na(seats) & !is.na(upperseats),
                         seats - upperseats, seats),
    # ── Tier-aware EFFECTIVE district magnitude ──────────────────────────────
    # Seat-weighted average of tier magnitudes:
    #     M_eff = (S1*M1 + S_upper*M_upper) / S_total
    # For single-tier systems (upperseats = 0 or NA) this reduces exactly to
    # M_eff = tier1_avemag, as it should. This is the transparent Taagepera-
    # style construction; the components ship alongside so the paper can
    # substitute its own operationalization without re-deriving anything.
    mag_eff = case_when(
      is.na(tier1_avemag) ~ NA_real_,
      is.na(upperseats) | upperseats == 0 ~ tier1_avemag,
      is.na(seats) | seats == 0 ~ NA_real_,
      TRUE ~ (seats_tier1 * tier1_avemag + upperseats * mag_upper) / seats
    ),
    log_mag_eff = ifelse(!is.na(mag_eff) & mag_eff > 0, log(mag_eff), NA_real_)
  )

# ── 2. Rule-change detection ────────────────────────────────────────────────
# "First election held under a changed rule": any change in the STRUCTURAL rule
# fields relative to the previous election in the same country. Continuous
# treatment (delta_log_mag_eff) ships alongside — the paper codes treatment as
# the change in log effective magnitude, not as a family switch, because a
# PR/majoritarian binary discards the France 1986/1988 reversal.
des <- des %>%
  arrange(country, election_date) %>%
  group_by(country) %>%
  mutate(
    prev_family  = lag(system_family),
    prev_elecrule = lag(elecrule),
    prev_t1f     = lag(tier1_formula),
    prev_mixed   = lag(mixed_type),
    prev_log_mag = lag(log_mag_eff),
    delta_log_mag_eff = log_mag_eff - prev_log_mag,
    rule_change = !is.na(prev_family) & (
      system_family != prev_family |
      (!is.na(elecrule) & !is.na(prev_elecrule) & elecrule != prev_elecrule) |
      (!is.na(tier1_formula) & !is.na(prev_t1f) & tier1_formula != prev_t1f) |
      (!is.na(mixed_type) != !is.na(prev_mixed)) |
      (!is.na(mixed_type) & !is.na(prev_mixed) & mixed_type != prev_mixed)
    ),
    election_seq = row_number()
  ) %>%
  ungroup()

# ── 3. CLEA observed magnitude (cross-check) ────────────────────────────────
e <- new.env()
load(here("data", "processed", "clea_lc_20251015.RData"), envir = e)
clea <- get(ls(e)[1], envir = e)

clea_mag <- clea %>%
  filter(!is.na(mag), mag > 0) %>%
  distinct(ctr_n, yr, mn, cst, mag) %>%
  group_by(ctr_n, yr, mn) %>%
  summarise(mag_clea_mean   = mean(mag, na.rm = TRUE),
            mag_clea_median = median(mag, na.rm = TRUE),
            n_districts_clea = n_distinct(cst),
            .groups = "drop") %>%
  mutate(ctr_n = trimws(ctr_n))

out <- des %>%
  mutate(country_j = trimws(country)) %>%
  left_join(clea_mag, by = c("country_j" = "ctr_n", "year" = "yr", "month" = "mn"))

match_rate <- mean(!is.na(out$mag_clea_mean))

out <- out %>%
  select(elec_id, country, ccode, ccode2, year, month, day, election_date,
         election_seq,
         system_family, legislative_type, elecrule, mixed_type, multi,
         tier1_formula, tier2_formula,
         seats, seats_tier1, upperseats, uppertier,
         tier1_districts, n_districts_upper,
         mag_tier1_ave = tier1_avemag, mag_upper, mag_eff, log_mag_eff,
         delta_log_mag_eff, rule_change,
         mag_clea_mean, mag_clea_median, n_districts_clea,
         enep, enpp, majority_bonus,
         regime, bmr_democracy, vd_polyarchy) %>%
  arrange(country, election_date)

attr(out, "des_version")     <- DES_VERSION
attr(out, "clea_match_rate") <- match_rate
attr(out, "threshold_note")  <-
  "Legal threshold NOT included: DES v5.0 carries no threshold column."
attr(out, "mag_eff_formula") <-
  "(seats_tier1 * mag_tier1_ave + upperseats * mag_upper) / seats; reduces to mag_tier1_ave for single-tier systems."

saveRDS(out, here("data", "processed", "electoral_systems.rds"))

cat("\n── electoral_systems ──\n")
cat(sprintf("  %s country-elections | %d countries | %d–%d\n",
            format(nrow(out), big.mark = ","), n_distinct(out$country),
            min(out$year, na.rm = TRUE), max(out$year, na.rm = TRUE)))
cat(sprintf("  DES %s (lower-chamber legislative only)\n", DES_VERSION))
cat(sprintf("  mag_eff non-missing: %.1f%% | CLEA magnitude matched: %.1f%%\n",
            100 * mean(!is.na(out$mag_eff)), 100 * match_rate))
cat(sprintf("  rule changes flagged: %d\n", sum(out$rule_change, na.rm = TRUE)))
cat("  ⚠️ legal threshold NOT available in DES v5.0 — see header.\n")
cat("  ->", here("data", "processed", "electoral_systems.rds"), "\n")

# Agreement between DES tier-1 magnitude and CLEA observed magnitude — a
# sanity check on the join, not a substantive result.
chk <- out %>% filter(!is.na(mag_clea_mean), !is.na(mag_tier1_ave))
if (nrow(chk) > 30) {
  cat(sprintf("\n  DES tier1 vs CLEA observed magnitude: r = %.3f (n = %d)\n",
              cor(log1p(chk$mag_tier1_ave), log1p(chk$mag_clea_mean),
                  use = "complete.obs"), nrow(chk)))
}
