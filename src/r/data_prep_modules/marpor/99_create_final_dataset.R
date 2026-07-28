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
