# MARPOR / CMP: Build the harmonized party × election table
#
# Deliverable A of paper-bank 25 (papers/25-cmp/DATA-REQUEST.md).
#
# Output:
#   data/processed/marpor_party_election.rds
#   data/processed/marpor_party_election.parquet
#
# Unit: ONE ROW PER PARTY PER ELECTION. Aggregation to country-election level
# (seat-weighted mean / SD of RILE) is a PAPER-SPECIFIC derived variable and
# belongs in paper-bank, NOT here.
#
# ⚠️ The full per101–per706 vector and the quasi-sentence total ship intact and
#    on purpose. The BLM (Benoit–Laver–Mikhaylov 2009) bootstrap treats each
#    manifesto's coded quasi-sentences as a multinomial draw across categories;
#    without the category vector and the total it is impossible. Do not "tidy"
#    these columns away.

library(here)
suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
})

source(here("src", "r", "data_prep_modules", "marpor", "0_load_marpor.R"))

d <- load_marpor_raw()

parents <- marpor_parent_categories(d)
subs    <- marpor_subcategories(d)

id_cols <- c("country", "countryname", "edate", "date",
             "party", "partyname", "partyabbrev", "parfam",
             "coderid", "manual", "coderyear", "testresult",
             "corpusversion", "datasetversion", "progtype", "datasetorigin")
wt_cols    <- c("pervote", "absseat", "totseats")
scale_cols <- c("rile", "planeco", "markeco", "welfare", "intpeace")
cnt_cols   <- c(parents, subs, "peruncod", "total")

keep <- c(id_cols, wt_cols, scale_cols, cnt_cols)
keep <- keep[keep %in% names(d)]

out <- d[, keep] %>%
  mutate(
    # ⚠️ MPDS ships `corpusversion` as a CHARACTER column in which absent values
    # are the literal string "NA", not R's NA — 3,128 of 5,285 rows in MPDS2025a.
    # `is.na()` therefore returns FALSE for every one of them, and any filter,
    # group_by or join on this column silently acquires a bogus "NA" level.
    # §2 of the data request names corpusversion as the provenance stamp the
    # paper cites its release from, so this has to be a real NA.
    #
    # Narrowly scoped to this column on purpose: a party abbreviation of "NA"
    # would be legitimate (none currently is), so a blanket sweep over character
    # columns could destroy real data in a future release.
    #
    # The populated 2,157 rows are "2025-1" — the manifestos present in the
    # CORPUS. Main-dataset-only manifestos have no corpus version, which is what
    # the blank means. The pinned release is recorded in 0_load_marpor.R
    # (MARPOR_RELEASE / MARPOR_CORPUS_VERSION) regardless.
    corpusversion = ifelse(as.character(corpusversion) == "NA",
                           NA_character_, as.character(corpusversion)),
    eyear     = as.integer(substr(as.character(edate), 1, 4)),
    seatshare = ifelse(!is.na(absseat) & !is.na(totseats) & totseats > 0,
                       absseat / totseats, NA_real_),
    # Parity diagnostic: parent categories + uncoded should reach 100.
    per_sum   = rowSums(across(all_of(c(parents, "peruncod"))), na.rm = TRUE),
    # Coded quasi-sentences actually accounted for by the category vector.
    # THIS, not `total`, is the correct multinomial N for the BLM bootstrap:
    # in ~17% of rows MPDS leaves uncoded mass out of `peruncod`, so `total`
    # overstates the coded base. See docs/surveys/marpor.md §Acceptance checks.
    n_coded   = ifelse(!is.na(total),
                       round(total * rowSums(across(all_of(parents)), na.rm = TRUE) / 100),
                       NA_real_),
    blm_usable = !is.na(total) & total > 0 & per_sum > 0
  ) %>%
  relocate(eyear, .after = date) %>%
  relocate(seatshare, .after = totseats) %>%
  arrange(countryname, edate, party)

stopifnot(!any(duplicated(out[, c("party", "edate")])))

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)
saveRDS(out, here("data", "processed", "marpor_party_election.rds"))
arrow::write_parquet(out, here("data", "processed", "marpor_party_election.parquet"))

cat("\n── marpor_party_election ──\n")
cat(sprintf("  %s rows × %d cols\n", format(nrow(out), big.mark = ","), ncol(out)))
cat(sprintf("  %d countries | %d elections | %d–%d\n",
            n_distinct(out$countryname), n_distinct(out$edate),
            min(out$eyear, na.rm = TRUE), max(out$eyear, na.rm = TRUE)))
cat(sprintf("  release: %s (corpus %s)\n", MARPOR_RELEASE, MARPOR_CORPUS_VERSION))
cat(sprintf("  BLM-usable rows: %s (%.1f%%)\n",
            format(sum(out$blm_usable), big.mark = ","),
            100 * mean(out$blm_usable)))
cat("  ->", here("data", "processed", "marpor_party_election.rds"), "\n")
cat("  ->", here("data", "processed", "marpor_party_election.parquet"), "\n")

# ── Freshness manifest ──────────────────────────────────────────────────────
# Records SHA-256 of every input, output and engine file so
# src/r/audit/06_check_freshness.R can answer "would a re-run change this?".
#
# specs = character(): MARPOR is not a survey and has no YAML harmonize specs.
# engine = this module's OWN scripts, NOT the shared harmonize engine — nothing
# here calls harmonize_all() or recoding.R, so recording those would mark this
# module STALE on every unrelated recoding.R edit.
#
# ⚠️ Outputs are recorded only if they exist. This module builds three artifacts
# across three scripts (99 -> party_election, 2 -> manifesto_se,
# 97 -> electoral_systems), so run the full pipeline before relying on the
# manifest; re-running 99 last refreshes it to cover all three.
source(here("src", "r", "utils", "provenance.R"))

.marpor_outputs <- c(
  here("data", "processed", "marpor_party_election.rds"),
  here("data", "processed", "marpor_party_election.parquet"),
  here("data", "processed", "marpor_manifesto_se.rds"),
  here("data", "processed", "electoral_systems.rds")
)

write_manifest(
  survey  = "marpor",
  inputs  = Filter(file.exists, c(
    here("data", "marpor", "raw", MARPOR_RELEASE,
         paste0(tolower(MARPOR_RELEASE), "_raw.rds")),
    here("data", "des", "raw", "v5_0", "es_data-v5_0.csv"),
    here("data", "processed", "clea_lc_20251015.RData"))),
  specs   = character(),
  outputs = Filter(file.exists, .marpor_outputs),
  engine  = c("src/r/data_prep_modules/marpor/0_load_marpor.R",
              "src/r/data_prep_modules/marpor/99_create_final_dataset.R",
              "src/r/data_prep_modules/marpor/2_bootstrap_manifesto_se.R",
              "src/r/data_prep_modules/marpor/97_build_electoral_systems.R")
)
cat("  -> manifest:", here("outputs", "marpor", "manifest.json"), "\n")
