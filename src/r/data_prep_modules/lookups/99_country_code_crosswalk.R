# Country-code crosswalk — COW ↔ ISO3 ↔ DAC ↔ V-Dem, with year validity
#
# §3 of paper-bank 24's DATA-REQUEST. The request calls this "the actual
# harmonization work", and it is: four sources, four identifier conventions.
#
# Output:
#   data/lookups/country_code_crosswalk.csv
#   data/lookups/country_code_coverage_report.csv
#
# CANONICAL JOIN KEY: country_text_id (ISO3) + year, matching the V-Dem
# convention already used across this repo.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY THIS EXISTS: the silent-NA trap
# ─────────────────────────────────────────────────────────────────────────────
# The request warns that `countrycode` returns NA on exactly the cases that
# matter, because the states that dissolve or merge during the window are
# disproportionately states that held UNSC seats. Measured here, that is true
# and specific:
#
#   V-Dem has NO row for YUG, CSK or VCT.
#
# YUG and CSK are not obscure — both held non-permanent UNSC seats with real
# exit events inside the paper's window. Joining V-Dem on ISO3 alone silently
# NAs the regime moderator for those events, and a truncated post-exit window
# looks like an artefact rather than the join failure it is.
#
# The fix is to join V-Dem on COW where ISO3 disagrees:
#   YUG (COW 345) -> V-Dem SRB
#   CSK (COW 315) -> V-Dem CZE
# VCT (St Vincent & the Grenadines) is genuinely absent from V-Dem — a real
# coverage gap, not a naming mismatch, and it is reported as such.
#
# ⚠️ COW IS NOT UNIQUE EITHER. COW 345 covers both YUG and SRB, 315 both CSK and
# CZE, 678 both YAR and YEM. So neither key is safe alone; the pair plus a year
# range is what disambiguates.

library(here)
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
})

ip  <- readRDS(here("data", "processed", "unga_idealpoints.rds"))
cy  <- readRDS(here("data", "processed", "unsc_membership_cy.rds"))
vd  <- readRDS(here("data", "processed", "vdem_core.rds"))
aid <- readRDS(here("data", "processed", "dac_aid_bilateral.rds"))

cat("\n── country-code crosswalk ──\n")

obs <- bind_rows(
  ip %>% transmute(iso3 = country_text_id, cow = COWcode, name = country_name,
                   year, src = "unga"),
  cy %>% transmute(iso3 = country_text_id, cow = COWcode, name = country_name,
                   year, src = "unsc"),
  vd %>% transmute(iso3 = country_text_id, cow = COWcode, name = country_name,
                   year, src = "vdem"),
  aid %>% filter(recipient_type == "bilateral") %>%
    transmute(iso3 = recipient_iso3, cow = NA_real_, name = recipient_name,
              year, src = "dac_recipient"),
  aid %>% filter(donor_type == "bilateral") %>%
    transmute(iso3 = donor_iso3, cow = NA_real_, name = donor_name,
              year, src = "dac_donor")
) %>% filter(!is.na(iso3))

# ── V-Dem alias resolution, by COW where ISO3 disagrees ──────────────────────
# Derived rather than hardcoded: for each ISO3 absent from V-Dem, look for a
# V-Dem ISO3 sharing its COW code over overlapping years.
vdem_iso <- unique(vd$country_text_id)
vdem_by_cow <- vd %>% filter(!is.na(COWcode)) %>%
  distinct(cow = COWcode, vdem_text_id = country_text_id)

missing_in_vdem <- obs %>%
  filter(!iso3 %in% vdem_iso, src %in% c("unga", "unsc")) %>%
  distinct(iso3, cow) %>% filter(!is.na(cow))

alias <- missing_in_vdem %>%
  left_join(vdem_by_cow, by = "cow", relationship = "many-to-many") %>%
  filter(!is.na(vdem_text_id)) %>%
  distinct(iso3, vdem_text_id)

cat("  ISO3 present in UNGA/UNSC but absent from V-Dem: ",
    nrow(missing_in_vdem), "\n", sep = "")
if (nrow(alias)) {
  cat("  resolved via shared COW code:\n")
  for (i in seq_len(nrow(alias))) {
    cat(sprintf("    %s -> V-Dem %s\n", alias$iso3[i], alias$vdem_text_id[i]))
  }
}
unresolved <- setdiff(missing_in_vdem$iso3, alias$iso3)
if (length(unresolved)) {
  cat("  ⚠️ UNRESOLVED (genuine V-Dem coverage gaps, not naming): ",
      paste(unresolved, collapse = ", "), "\n", sep = "")
}

# ── the crosswalk itself ─────────────────────────────────────────────────────
xw <- obs %>%
  group_by(iso3, cow) %>%
  summarise(country_name = first(na.omit(name)),
            valid_from   = min(year), valid_to = max(year),
            sources      = paste(sort(unique(src)), collapse = "+"),
            .groups = "drop") %>%
  left_join(alias, by = "iso3") %>%
  mutate(
    vdem_text_id = coalesce(vdem_text_id, ifelse(iso3 %in% vdem_iso, iso3, NA_character_)),
    dac_code     = ifelse(iso3 %in% c(aid$donor_iso3, aid$recipient_iso3), iso3, NA_character_),
    in_unga = grepl("unga", sources), in_unsc = grepl("unsc", sources),
    in_vdem = !is.na(vdem_text_id),   in_dac  = !is.na(dac_code),
    succession_note = case_when(
      iso3 == "YUG" ~ "SFR Yugoslavia; COW 345 shared with SRB. V-Dem alias SRB. FRY suspended from UNGA 1992-2000.",
      iso3 == "CSK" ~ "Czechoslovakia; COW 315 shared with CZE. Dissolved 1993 -> CZE + SVK. V-Dem alias CZE.",
      iso3 == "DDR" ~ "German Democratic Republic; merged into DEU 1990. No post-1990 rows exist.",
      iso3 == "YAR" ~ "Yemen Arab Republic (North); COW 678 shared with YEM. Unified 1990 -> YEM.",
      iso3 == "YMD" ~ "People's Democratic Republic of Yemen (South); unified 1990 -> YEM.",
      iso3 == "SRB" ~ "Serbia; COW 345 shared with YUG. V-Dem's label for the whole 345 series.",
      iso3 == "CZE" ~ "Czechia; COW 316 post-1993, COW 315 pre-1993 as part of CSK.",
      iso3 == "SSD" ~ "South Sudan; seceded from SDN 2011.",
      TRUE ~ NA_character_
    )
  ) %>%
  select(country_text_id = iso3, COWcode = cow, dac_code, vdem_text_id,
         country_name, valid_from, valid_to,
         in_unga, in_unsc, in_vdem, in_dac, sources, succession_note) %>%
  arrange(country_text_id, valid_from)

dir.create(here("data", "lookups"), showWarnings = FALSE, recursive = TRUE)
write_csv(xw, here("data", "lookups", "country_code_crosswalk.csv"))

cat(sprintf("\n  crosswalk rows: %d | distinct ISO3: %d\n", nrow(xw), n_distinct(xw$country_text_id)))
cat(sprintf("  in UNGA %d | UNSC %d | V-Dem %d | DAC %d\n",
            sum(xw$in_unga), sum(xw$in_unsc), sum(xw$in_vdem), sum(xw$in_dac)))

# ── coverage report: every unmatched country-year ────────────────────────────
# The request asks for this explicitly. "Unmatched" = present in a paper-facing
# source but with no V-Dem counterpart, since V-Dem supplies the moderator.
report <- obs %>%
  filter(src %in% c("unga", "unsc")) %>%
  distinct(iso3, year, src) %>%
  left_join(xw %>% distinct(iso3 = country_text_id, vdem_text_id), by = "iso3") %>%
  mutate(vdem_year_present = paste(coalesce(vdem_text_id, "~"), year) %in%
                             paste(vd$country_text_id, vd$year)) %>%
  filter(!vdem_year_present) %>%
  count(iso3, src, name = "unmatched_country_years") %>%
  arrange(desc(unmatched_country_years))

write_csv(report, here("data", "lookups", "country_code_coverage_report.csv"))

cat(sprintf("\n  UNMATCHED country-years (no V-Dem row): %d across %d ISO3\n",
            sum(report$unmatched_country_years), n_distinct(report$iso3)))
print(as.data.frame(head(report, 12)), row.names = FALSE)
cat("\n  ->", here("data", "lookups", "country_code_crosswalk.csv"), "\n")
cat("  ->", here("data", "lookups", "country_code_coverage_report.csv"), "\n")
