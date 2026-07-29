# OECD DAC bilateral aid — donor × recipient × year
#
# Deliverable 2.4 of paper-bank 24 (papers/24-unsc/DATA-REQUEST.md).
#
# Output:
#   data/processed/dac_aid_bilateral.{rds,parquet}
#
# ─────────────────────────────────────────────────────────────────────────────
# TABLE CHOICE: DAC Table 2a, per Jeff's decision 2026-07-29
# ─────────────────────────────────────────────────────────────────────────────
# The request originally specified CRS. CRS disbursements are only reliably
# populated from ~2002 while the paper's universe opens in 1970, so a CRS-based
# aid measure would leave most of the panel empty for reasons unrelated to the
# design. Table 2a (ODA disbursements to countries and regions) is donor ×
# recipient × year and runs from 1960 — the right granularity for both uses the
# paper has: a donor-flow-weighted bloc position, and a median split on
# post-exit aid change.
#
# Decision was to build BOTH, 2a primary and CRS alongside, so sensitivity to
# the choice is testable via `source_table`. CRS is a separate pull for SECTOR
# detail and is NOT yet done.
#
# ⚠️ TABLE 2a IS DISBURSEMENTS ONLY. The request asks for `flow_type` to carry
# disbursement AND commitment. MEASURE 305 ("ODA, commitments") exists in the
# DAC2A codelist but returns NoResultsFound for every query — the measure is
# declared, not populated.
#
# Commitments therefore come from **DAC3A** ("Aid (ODA) commitments to countries
# and regions"), which this script also reads. DAC3A is the same donor ×
# recipient × year granularity and starts in 1970 — exactly the paper's universe.
# That is a better commitment source than CRS, which is activity-level and would
# need aggregating up. An earlier revision of this header claimed commitments
# "can only come from CRS"; that was written before DAC3A was found, and is
# wrong. CRS remains wanted for sector detail only.
#
# ─────────────────────────────────────────────────────────────────────────────
# MULTILATERALS: retained and flagged, NOT dropped, NOT weighted
# ─────────────────────────────────────────────────────────────────────────────
# Per decision 2026-07-29. Multilaterals are not UNGA member states and have no
# ideal point, so they cannot contribute to a donor-flow-weighted BLOC POSITION
# without imputing one. They ship with donor_type = "multilateral" so the paper
# can measure their share of flows and exclude them from the weighting. The
# request is explicit that they must not be dropped silently.
#
# `donor_type` / `recipient_type` also carry "aggregate" (ALLD = all official
# donors, DAC, G7, …). ⚠️ THOSE ARE SUMS OF OTHER ROWS. Filtering to
# donor_type == "bilateral" is REQUIRED before summing, or every total is
# double-counted several times over.
#
# ─────────────────────────────────────────────────────────────────────────────
# UNITS AND BASE YEAR
# ─────────────────────────────────────────────────────────────────────────────
# OECD ships these in millions (UNIT_MULT = 6). This applies the multiplier, so
# `oda_usd_const` and `oda_usd_current` are in ACTUAL USD, not millions.
# Constant-price base year is whatever each release ships, per the decision to
# avoid a second deflation step — and the two DIFFER (see EXPECTED_BASE below).
#
# Coverage: DAC2A 1960–2022, DAC3A 1970–2024. DAC2A 2023/2024 return HTTP 404 —
# not yet published, not a download failure.

library(here)
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(arrow)
  library(countrycode)
})

DIR_2A <- here("data", "oecd-dac", "raw", "dac2a-2026-07-29")   # disbursements
DIR_3A <- here("data", "oecd-dac", "raw", "dac3a-2026-07-29")   # commitments
stopifnot(dir.exists(DIR_2A), dir.exists(DIR_3A))

# ⚠️ THE TWO TABLES USE DIFFERENT CONSTANT-PRICE BASE YEARS: DAC2A is based
# 2022, DAC3A is based 2024. `oda_usd_const` is therefore NOT comparable across
# `source_table` without re-basing, and differencing a commitment against a
# disbursement in constant terms is WRONG unless one is converted first.
# `const_base_year` ships per row so this cannot be done by accident silently.
# Current-price (`oda_usd_current`) is comparable across both.
EXPECTED_BASE <- c(dac2a = "2022", dac3a = "2024")

read_table <- function(dir, prefix, label) {
  chunks <- list.files(dir, pattern = paste0("^", prefix, "_.*\\.csv$"), full.names = TRUE)
  raw <- lapply(chunks, read_csv, col_types = cols(.default = col_character(),
                                                   OBS_VALUE = col_double())) %>%
    bind_rows()

  # ⚠️ The API returns HTTP 200 on a TRUNCATED response and curl writes the
  # partial body without complaint. Three of eight DAC2A chunks were silently
  # short on the first pull — one had lost 57% of its rows. Never trust chunk
  # completeness; assert it here so a bad download cannot reach the panel.
  yrs <- sort(unique(as.integer(raw$TIME_PERIOD)))
  gaps <- setdiff(seq(min(yrs), max(yrs)), yrs)
  if (length(gaps)) stop(label, " year gap — chunks incomplete: ", paste(gaps, collapse = ", "))

  bases <- unique(raw$BASE_PER[raw$PRICE_BASE == "Q" & !is.na(raw$BASE_PER)])
  if (!identical(as.character(bases), unname(EXPECTED_BASE[label]))) {
    stop(label, " unexpected constant-price base: ", paste(bases, collapse = ", "),
         " (expected ", EXPECTED_BASE[label], ")")
  }

  cat(sprintf("  %-6s %s obs | %d–%d, no gaps | const base %s\n",
              label, format(nrow(raw), big.mark = ","), min(yrs), max(yrs), bases))
  raw %>% mutate(source_table = label, const_base_year = as.integer(bases))
}

cat("\n── OECD DAC ──\n")
raw <- bind_rows(
  read_table(DIR_2A, "dac2a", "dac2a"),
  read_table(DIR_3A, "dac3a", "dac3a")
)

# ─────────────────────────────────────────────────────────────────────────────
# ENTITY CLASSIFICATION — validated against ISO 3166, not against string shape
# ─────────────────────────────────────────────────────────────────────────────
# ⚠️ An earlier revision typed anything matching ^[A-Z]{3}$ as a country. That is
# wrong and expensively so: ACP, EAC ("East African Community") and LDC ("Least
# developed countries") are GROUPINGS that happen to be three uppercase letters.
# They were therefore labelled `bilateral` — the exact rows the docs tell
# consumers to keep. Summing bilateral->bilateral disbursements with them
# included INFLATES total ODA BY 41.8% (1,455.6bn of 3,485.8bn current USD
# across 2.58% of rows), because they are sums of other rows already present.
#
# The reliable test is whether the code is a real ISO 3166-1 alpha-3, which
# `countrycode` answers. Of 265 three-letter codes in the OECD codelist, 249
# validate and 16 do not; every one of the 16 is a grouping (ACP, AES, CIS, DAE,
# EEA, SDR, EAC, DAC, ODA, LDC, WBA/WBM world bunkers, IEA, WXD) except two real
# places that have no ISO3 because they are not UN members. Those two are
# hand-patched rather than silently swept into `aggregate`.
NON_ISO_TERRITORIES <- c("XKV",   # Kosovo — real polity, no ISO 3166 entry
                         "CPT")   # Clipperton Island

codes <- read_csv(file.path(DIR_2A, "cl_area_org.csv"), col_types = cols()) %>%
  mutate(
    is_iso3 = grepl("^[A-Z]{3}$", code) &
              !is.na(suppressWarnings(
                countrycode::countrycode(code, "iso3c", "iso.name.en", warn = FALSE))),
    entity_type = case_when(
      grepl("^[0-9]", code)            ~ "multilateral",
      code %in% NON_ISO_TERRITORIES    ~ "bilateral",
      is_iso3                          ~ "bilateral",
      TRUE                             ~ "aggregate"
    )
  ) %>%
  select(-is_iso3)

# Regression guard: the three that caused the 41.8% inflation must never again
# come out as bilateral.
stopifnot(codes$entity_type[match(c("ACP", "EAC", "LDC"), codes$code)] == "aggregate")

tidy <- raw %>%
  transmute(
    donor_code     = DONOR,
    recipient_code = RECIPIENT,
    year           = as.integer(TIME_PERIOD),
    flow_type      = case_when(MEASURE == "206" ~ "disbursement",
                               MEASURE == "305" ~ "commitment",
                               TRUE ~ NA_character_),
    price_base     = PRICE_BASE,
    value          = OBS_VALUE * 10^as.integer(UNIT_MULT),
    source_table, const_base_year
  ) %>%
  filter(!is.na(flow_type), !is.na(value))

out <- tidy %>%
  pivot_wider(id_cols = c(donor_code, recipient_code, year, flow_type,
                          source_table, const_base_year),
              names_from = price_base, values_from = value,
              values_fn = ~ .x[1]) %>%
  rename(oda_usd_const = Q, oda_usd_current = V) %>%
  left_join(codes %>% select(donor_code = code, donor_name = name,
                             donor_type = entity_type), by = "donor_code") %>%
  left_join(codes %>% select(recipient_code = code, recipient_name = name,
                             recipient_type = entity_type), by = "recipient_code") %>%
  mutate(donor_iso3     = ifelse(donor_type     == "bilateral", donor_code,     NA_character_),
         recipient_iso3 = ifelse(recipient_type == "bilateral", recipient_code, NA_character_)) %>%
  select(donor_code, donor_iso3, donor_name, donor_type,
         recipient_code, recipient_iso3, recipient_name, recipient_type,
         year, flow_type, oda_usd_const, oda_usd_current,
         const_base_year, source_table) %>%
  arrange(donor_code, recipient_code, year, flow_type)

stopifnot(!any(duplicated(out[, c("donor_code", "recipient_code", "year", "flow_type")])))

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)
saveRDS(out, here("data", "processed", "dac_aid_bilateral.rds"))
write_parquet(out, here("data", "processed", "dac_aid_bilateral.parquet"))

cat(sprintf("\n  rows: %s | %d–%d\n", format(nrow(out), big.mark = ","),
            min(out$year), max(out$year)))
cat("  donors by type:\n")
print(out %>% distinct(donor_code, donor_type) %>% count(donor_type))
cat("  flow_type:\n"); print(out %>% count(flow_type))
cat(sprintf("  bilateral donor × recipient × year rows: %s\n",
            format(sum(out$donor_type == "bilateral" & out$recipient_type == "bilateral"),
                   big.mark = ",")))
cat(sprintf("  const base year: %s | oda_usd_const non-missing: %.1f%%\n",
            EXPECTED_BASE, 100 * mean(!is.na(out$oda_usd_const))))
cat("  ->", here("data", "processed", "dac_aid_bilateral.rds"), "\n")

# ── Freshness manifest ──────────────────────────────────────────────────────
# specs = character(): OECD DAC is a donor x recipient x year macro panel, not a
# survey — no YAML harmonize specs, no waves, no questionnaire.
# engine = this module's own script, NOT the shared harmonize engine: nothing
# here calls harmonize_all() or recoding.R, so recording those would mark this
# module STALE on every unrelated recoding.R edit.
#
# Every CSV under both raw pull directories is hashed, so a re-pull that changes
# any slice (or adds a year range) is caught rather than silently absorbed.
source(here("src", "r", "utils", "provenance.R"))
write_manifest(
  survey  = "oecd_dac",
  inputs  = sort(c(list.files(DIR_2A, pattern = "\\.csv$", full.names = TRUE),
                   if (dir.exists(DIR_3A))
                     list.files(DIR_3A, pattern = "\\.csv$", full.names = TRUE)
                   else character())),
  specs   = character(),
  outputs = Filter(file.exists, c(
    here("data", "processed", "dac_aid_bilateral.rds"),
    here("data", "processed", "dac_aid_bilateral.parquet"))),
  engine  = "src/r/data_prep_modules/oecd_dac/99_create_final_dataset.R"
)
cat("  -> manifest:", here("outputs", "oecd_dac", "manifest.json"), "\n")
