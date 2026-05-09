#!/usr/bin/env Rscript
# Convert all SPSS .sav files to .rds for faster loading.
#
# W6 SPECIAL CASE
# ---------------
# Wave 6 is NOT a single merged .sav file. ABS releases each W6 country
# separately (e.g. W6_Cambodia_Release_*.sav, W6_Korea_*.sav, ...). The
# canonical multi-country w6.rds is built by `src/scripts/build_abs_w6.R`,
# which stacks every per-country file in data/abs/raw/wave6/ into one frame
# (~14,876 rows across all currently-released countries).
#
# Earlier versions of this script hardcoded the Cambodia-only file as the
# W6 source, which silently overwrote the multi-country build with a
# Cambodia-only ~1,242-row dataset. To eliminate that hazard:
#   1. The W1–W5 loop below no longer touches W6.
#   2. After the loop, we delegate to build_abs_w6.R for W6 — but only if
#      no existing w6.rds with > 5,000 rows is present. The threshold is a
#      sanity guard: any plausible multi-country build clears 5k rows;
#      Cambodia alone is ~1.2k. If a multi-country file already exists, we
#      refuse to rebuild and instruct the user to delete it explicitly.

library(haven)
library(here)

cat("\n=== CONVERTING SURVEY WAVES TO RDS ===\n")

wave_info <- list(
  w1 = list(file = "data/abs/raw/wave1/Wave1_20170906.sav", name = "w1"),
  w2 = list(file = "data/abs/raw/wave2/Wave2_20250609.sav", name = "w2"),
  w3 = list(file = "data/abs/raw/wave3/ABS3 merge20250609.sav", name = "w3"),
  w4 = list(file = "data/abs/raw/wave4/W4_v15_merged20250609_release.sav", name = "w4"),
  w5 = list(file = "data/abs/raw/wave5/20230505_W5_merge_15.sav", name = "w5")
  # W6 intentionally omitted — handled below via build_abs_w6.R.
)

for (wave in names(wave_info)) {
  sav_path <- here::here(wave_info[[wave]]$file)
  rds_path <- here::here("data", "processed", sprintf("%s.rds", wave))

  cat(sprintf("Loading %s from %s\n", wave, basename(sav_path)))
  data <- haven::read_sav(sav_path)

  cat(sprintf("Saving to %s (%d rows × %d cols)\n", basename(rds_path), nrow(data), ncol(data)))
  saveRDS(data, rds_path)
}

# --- W6: delegate to build_abs_w6.R, with a multi-country preservation guard ---
w6_path <- here::here("data", "processed", "w6.rds")
w6_threshold <- 5000L  # multi-country build is ~14.9k rows; Cambodia alone is ~1.2k

cat("\n--- Wave 6 (multi-country build) ---\n")

if (file.exists(w6_path)) {
  existing_w6 <- tryCatch(readRDS(w6_path), error = function(e) NULL)
  existing_n  <- if (is.null(existing_w6)) NA_integer_ else nrow(existing_w6)

  if (!is.na(existing_n) && existing_n > w6_threshold) {
    cat(sprintf(
      paste0(
        "SKIP: %s already has %s rows (> %s threshold), which looks like a\n",
        "multi-country build. Refusing to rebuild — running build_abs_w6.R\n",
        "now would only re-stack the same per-country .sav files, but we treat\n",
        "any existing multi-country w6.rds as authoritative to avoid clobbering\n",
        "downstream work. To force a rebuild, delete the file explicitly:\n",
        "  rm %s\n",
        "and rerun this script (or run src/scripts/build_abs_w6.R directly).\n"
      ),
      basename(w6_path),
      format(existing_n, big.mark = ","),
      format(w6_threshold, big.mark = ","),
      w6_path
    ))
  } else {
    cat(sprintf(
      "Existing %s has %s rows (<= %s threshold). Rebuilding via build_abs_w6.R.\n",
      basename(w6_path),
      if (is.na(existing_n)) "unreadable" else format(existing_n, big.mark = ","),
      format(w6_threshold, big.mark = ",")
    ))
    source(here::here("src", "scripts", "build_abs_w6.R"))
  }
} else {
  cat("No existing w6.rds. Building via build_abs_w6.R.\n")
  source(here::here("src", "scripts", "build_abs_w6.R"))
}

cat("\n✅ All waves converted to RDS format\n")
