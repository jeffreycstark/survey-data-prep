#' Tests for join_party_crosswalk()
#'
#' Run with:
#'   Rscript src/r/lookups/test_party_lineage.R
#'
#' Two test blocks:
#'   1. Synthetic 5-row check: confirm Korea code 301 W3 resolves to
#'      "Uri/Democratic lineage" / "progressive".
#'   2. Regression check against data/processed/party_winner_loser.csv:
#'      sample 100 W3 rows, run the helper, confirm output matches the
#'      pre-joined party_lineage and coalition columns.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(readr)
})

source(here::here("src", "r", "lookups", "party_lineage.R"))

cat("=== test 1: synthetic 5-row check ===\n")

synthetic <- tibble::tibble(
  country = c(3, 3, 7, 8, 12),
  wave    = c("W3", "W3", "W4", "W3", "W6"),
  pid     = c(301, 305, 702, 802, 9999)
)

res1 <- tryCatch(
  withCallingHandlers(
    join_party_crosswalk(
      synthetic,
      country_col = "country",
      wave_col    = "wave",
      code_col    = "pid"
    ),
    warning = function(w) {
      cat("  expected warning fired:\n  ", conditionMessage(w), "\n")
      invokeRestart("muffleWarning")
    }
  ),
  error = function(e) {
    cat("FAIL test 1: ", conditionMessage(e), "\n")
    quit(status = 1)
  }
)

cat("\nresult:\n")
print(res1)

stopifnot(
  "Korea 301 W3 lineage mismatch" =
    identical(res1$party_lineage[1], "Uri/Democratic lineage"),
  "Korea 301 W3 coalition mismatch" =
    identical(res1$coalition[1], "progressive"),
  "Taiwan 702 W4 lineage missing" =
    identical(res1$party_lineage[3], "DPP"),
  "Cambodia 9999 W6 should be NA (uncovered country)" =
    is.na(res1$party_lineage[5]),
  "synthetic row count drift" = nrow(res1) == nrow(synthetic)
)

cat("PASS test 1\n\n")

cat("=== test 2: regression vs party_winner_loser.csv (W3, n=100) ===\n")

pwl_path <- here::here("data", "processed", "party_winner_loser.csv")
if (!file.exists(pwl_path)) {
  cat("SKIP test 2: party_winner_loser.csv not found at ", pwl_path, "\n")
  quit(status = 0)
}

pwl <- readr::read_csv(pwl_path, show_col_types = FALSE) |>
  dplyr::filter(wave == "W3", !is.na(party_lineage)) |>
  dplyr::distinct(country, party_id_raw, party_lineage, coalition)

set.seed(42)
sample_df <- dplyr::sample_n(pwl, min(100, nrow(pwl))) |>
  dplyr::transmute(
    country = country,
    wave    = "W3",
    pid     = party_id_raw
  )

res2 <- suppressWarnings(join_party_crosswalk(
  sample_df,
  country_col = "country",
  wave_col    = "wave",
  code_col    = "pid"
))

joined <- res2 |>
  dplyr::left_join(
    pwl |> dplyr::rename(pid = party_id_raw,
                         lineage_ref = party_lineage,
                         coalition_ref = coalition),
    by = c("country", "pid")
  )

mismatches <- joined |>
  dplyr::filter(
    party_lineage != lineage_ref | coalition != coalition_ref |
      (is.na(party_lineage) != is.na(lineage_ref)) |
      (is.na(coalition) != is.na(coalition_ref))
  )

if (nrow(mismatches) > 0) {
  cat("FAIL test 2: ", nrow(mismatches), " of ", nrow(joined),
      " sample rows do not match the pre-joined reference.\n")
  print(utils::head(mismatches, 10))
  quit(status = 1)
}

cat("PASS test 2 (", nrow(joined), " sample rows match reference)\n\n",
    sep = "")
cat("ALL TESTS PASSED\n")
