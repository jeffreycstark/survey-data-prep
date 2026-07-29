# UNSC non-permanent membership — term-level and country-year
#
# Deliverable 2.3 of paper-bank 24 (papers/24-unsc/DATA-REQUEST.md). This is the
# spine of the paper's identification strategy: exit from a non-permanent seat.
#
# Output:
#   data/processed/unsc_membership_terms.{rds,parquet}   country × term
#   data/processed/unsc_membership_cy.{rds,parquet}      country × year
#
# Source chain
# ------------
# Source 1 is the Wikipedia table, archived under data/unsc/raw/ with its
# revision id and parsed by
#   src/python/unsc_membership/parse_wikipedia_unsc.py
#
# ⚠️ CORRECTION (supersedes an earlier note in this file): the UN's own list at
#    un.org/securitycouncil is NOT unreachable. An initial fetch returned a
#    CloudFront 403, which was attributed to bot-blocking; in fact it was only
#    the default curl User-Agent. With ordinary browser headers the page returns
#    200 and serves the authoritative roster in a clean
#    "Country  1970-1971, 2004-2005, ..." format.
#
# ⚠️ SOURCE 2 IS STILL OUTSTANDING, but is no longer blocked. The request asks
#    for two independent sources reconciled, plus 15 hand-checked country-terms
#    recorded in the docs page. Neither is done yet. What IS done is the
#    structural check below, which is strong evidence the parse is right but is
#    NOT a substitute for reconciling against the UN's own list.
#
# ─────────────────────────────────────────────────────────────────────────────
# STRUCTURAL VALIDATION: 10 seats per year
# ─────────────────────────────────────────────────────────────────────────────
# The request notes there have been exactly 10 non-permanent seats throughout
# the 1970+ window and that any year not summing to 10 is a data error. Every
# year 1970-2025 sums to 10. Getting there caught a real defect: the Wikipedia
# `rowspan` attribute IS the term length, and assuming a flat two years
# double-counted the Italy(2017)/Netherlands(2018) SPLIT SEAT, throwing 2018 and
# 2019 to 11. That is the split-term edge case the request asks to be findable.
#
# ⚠️ The asterisk in the source marks the ARAB SEAT (which alternates between the
#    African and Asia-Pacific groups), NOT a split term. Carried as `arab_seat`.

library(here)
suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(countrycode)
})

WINDOW_START <- 1970

terms_raw <- read.csv(here("data", "unsc", "interim", "unsc_terms_wikipedia.csv"),
                      stringsAsFactors = FALSE)

# Regional-group columns follow the post-1965 allocation. Pre-1966 rows are
# outside the paper's window and their group labels would be wrong, so they are
# nulled rather than shipped misleading.
terms <- terms_raw %>%
  filter(term_end_year >= WINDOW_START) %>%
  mutate(regional_group = ifelse(term_start_year >= 1966, regional_group, NA_character_))

# ── Country codes ───────────────────────────────────────────────────────────
# The request is explicit that `countrycode` returns NA on precisely the states
# that matter here, and that a silent NA can truncate a post-exit window and
# corrupt the gate count. Hand-patches below; anything still unmatched is
# reported loudly rather than dropped.
name_patch <- c(
  "Byelorussian Soviet Socialist Republic"   = "BLR",
  "Ukrainian Soviet Socialist Republic"      = "UKR",
  "Czechoslovakia"                           = "CSK",
  "East Germany"                             = "DDR",
  "West Germany"                             = "DEU",
  "Socialist Federal Republic of Yugoslavia" = "YUG",
  "People's Republic of Bulgaria"            = "BGR",
  "Polish People's Republic"                 = "POL",
  "Socialist Republic of Romania"            = "ROU",
  "Democratic Republic of Madagascar"        = "MDG",
  "People's Republic of the Congo"           = "COG",
  "Republic of the Congo"                    = "COG",
  "Democratic Republic of the Congo"         = "COD",
  "Republic of Venezuela"                    = "VEN",
  "German Democratic Republic"               = "DDR",
  "Federal Republic of Germany"              = "DEU",
  "Spanish State"                            = "ESP",  # Franco-era name
  "Somali Democratic Republic"               = "SOM"
)

terms <- terms %>%
  mutate(
    iso3_auto = suppressWarnings(
      countrycode(country_name_raw, origin = "country.name", destination = "iso3c")),
    country_text_id = ifelse(!is.na(iso3_auto), iso3_auto,
                             unname(name_patch[country_name_raw])),
    COWcode = suppressWarnings(
      countrycode(country_text_id, origin = "iso3c", destination = "cown")),
    # Historical states countrycode cannot resolve to a COW code from ISO3.
    COWcode = case_when(
      country_text_id == "CSK" ~ 315,
      country_text_id == "DDR" ~ 265,
      country_text_id == "YUG" ~ 345,
      TRUE ~ as.numeric(COWcode)
    ),
    successor_state = case_when(
      country_text_id == "CSK" ~ "dissolved 1993 -> CZE + SVK",
      country_text_id == "DDR" ~ "merged 1990 -> DEU",
      country_text_id == "YUG" ~ "dissolved 1992 -> successor states",
      country_text_id %in% c("BLR", "UKR") & term_start_year < 1991 ~
        "held a UN seat as a Soviet republic; independent from 1991",
      TRUE ~ NA_character_
    )
  ) %>%
  group_by(country_text_id) %>%
  arrange(term_start_year, .by_group = TRUE) %>%
  mutate(term_seq = row_number()) %>%
  ungroup() %>%
  arrange(term_start_year, country_text_id)

unmatched <- terms %>% filter(is.na(country_text_id)) %>% distinct(country_name_raw)

terms_out <- terms %>%
  select(country_text_id, COWcode, country_name = country_name_raw,
         term_start_year, term_end_year, n_years, term_seq,
         regional_group, split_term, arab_seat, successor_state)

# ── Country-year long form ──────────────────────────────────────────────────
# `years_since_exit` is deliberately NOT computed — the request leaves it to the
# paper.
cy <- terms_out %>%
  rowwise() %>%
  mutate(year = list(seq(term_start_year, term_end_year))) %>%
  tidyr::unnest(year) %>%
  ungroup() %>%
  mutate(unsc_member = 1L,
         term_year = year - term_start_year + 1L) %>%
  select(country_text_id, COWcode, country_name, year, unsc_member,
         term_year, term_seq, regional_group, split_term, successor_state) %>%
  arrange(year, country_text_id)

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)
saveRDS(terms_out, here("data", "processed", "unsc_membership_terms.rds"))
write_parquet(terms_out, here("data", "processed", "unsc_membership_terms.parquet"))
saveRDS(cy, here("data", "processed", "unsc_membership_cy.rds"))
write_parquet(cy, here("data", "processed", "unsc_membership_cy.parquet"))

cat("\n── unsc_membership_terms ──\n")
cat(sprintf("  %d country-terms | %d countries | terms starting %d-%d\n",
            nrow(terms_out), n_distinct(terms_out$country_text_id),
            min(terms_out$term_start_year), max(terms_out$term_start_year)))
cat(sprintf("  split terms flagged: %d  |  Arab-seat terms: %d\n",
            sum(terms_out$split_term), sum(terms_out$arab_seat)))
if (nrow(unmatched)) {
  cat("  ⚠️ UNMATCHED country names (no ISO3):\n")
  print(as.data.frame(unmatched), row.names = FALSE)
} else {
  cat("  ✅ every country name resolved to an ISO3 code\n")
}

cat("\n── unsc_membership_cy ──\n")
seatcheck <- cy %>% filter(year >= WINDOW_START, year <= 2025) %>% count(year)
cat(sprintf("  %d country-years | %d-%d\n", nrow(cy), min(cy$year), max(cy$year)))
cat(sprintf("  seat-count invariant (10/yr, %d-2025): %s\n", WINDOW_START,
            if (all(seatcheck$n == 10)) "✅ holds in every year"
            else paste("⚠️ violated in", sum(seatcheck$n != 10), "years")))
cat("\n  splits:\n")
print(as.data.frame(terms_out %>% filter(split_term == 1) %>%
                    select(country_name, term_start_year, term_end_year)), row.names = FALSE)

# ── Freshness manifest ──────────────────────────────────────────────────────
# specs = character(): not a survey, no YAML harmonize specs.
# engine includes the PYTHON parser as well as this script: the term table is
# produced by parse_wikipedia_unsc.py, so a change there changes this output.
source(here("src", "r", "utils", "provenance.R"))
write_manifest(
  survey  = "unsc",
  inputs  = Filter(file.exists, c(
    here("data", "unsc", "raw", "wikipedia_unsc_members.wikitext"),
    here("data", "unsc", "interim", "unsc_terms_wikipedia.csv"))),
  specs   = character(),
  outputs = Filter(file.exists, c(
    here("data", "processed", "unsc_membership_terms.rds"),
    here("data", "processed", "unsc_membership_terms.parquet"),
    here("data", "processed", "unsc_membership_cy.rds"),
    here("data", "processed", "unsc_membership_cy.parquet"))),
  engine  = c("src/r/data_prep_modules/unsc/99_create_final_dataset.R",
              "src/python/unsc_membership/parse_wikipedia_unsc.py")
)
cat("\n  -> manifest:", here("outputs", "unsc", "manifest.json"), "\n")
