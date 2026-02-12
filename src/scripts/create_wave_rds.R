#!/usr/bin/env Rscript
# Convert all SPSS .sav files to .rds for faster loading

library(haven)
library(here)

cat("\n=== CONVERTING SURVEY WAVES TO RDS ===\n")

wave_info <- list(
  w1 = list(file = "data/raw/wave1/Wave1_20170906.sav", name = "w1"),
  w2 = list(file = "data/raw/wave2/Wave2_20250609.sav", name = "w2"),
  w3 = list(file = "data/raw/wave3/ABS3 merge20250609.sav", name = "w3"),
  w4 = list(file = "data/raw/wave4/W4_v15_merged20250609_release.sav", name = "w4"),
  w5 = list(file = "data/raw/wave5/20230505_W5_merge_15.sav", name = "w5"),
  w6 = list(file = "data/raw/wave6/W6_Cambodia_Release_20240819.sav", name = "w6")
)

for (wave in names(wave_info)) {
  sav_path <- here::here(wave_info[[wave]]$file)
  rds_path <- here::here("data", "processed", sprintf("%s.rds", wave))
  
  cat(sprintf("Loading %s from %s\n", wave, basename(sav_path)))
  data <- haven::read_sav(sav_path)
  
  cat(sprintf("Saving to %s (%d rows × %d cols)\n", basename(rds_path), nrow(data), ncol(data)))
  saveRDS(data, rds_path)
}

cat("\n✅ All waves converted to RDS format\n")
