# KAMOS: Create final combined dataset
#
# Loads per-wave master files from outputs/kamos/,
# adds country and year identifiers, fixes missing weights,
# and saves kamos_harmonized.rds / .parquet.
#
# SURVEY YEARS:
#   W1 → 2016  (Feb–May; during active protest period)
#   W2 → 2017  (May–Jul; post-impeachment, early Moon administration)
#   W3 → 2018  (Apr–Jun; Moon governance midpoint)
#   W4 → 2019  (Apr–Jun; before Cho Kuk affair)
#
# WEIGHT NOTE:
#   W1 uses wt2 (trimmed post-stratification weight, mean ≈ 1, range 0.72–1.81)
#   W2 uses wt (post-stratification weight)
#   W3 uses wt (post-stratification weight)
#   W4 has no weight variable — all W4 respondents get weight = 1.0
#
# DEMOGRAPHICS NOTE:
#   W2/W3 have limited demographics (no gender, age is categorical 1-5).
#   Trust, economy, and political attitude items are fully available.

library(here)
library(dplyr)
library(arrow)

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: kamos_harmonized\n")
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "kamos")
wave_files <- sort(list.files(output_dir,
                               pattern = "^master_w[1-4]\\.rds$",
                               full.names = TRUE))

if (length(wave_files) == 0) {
  stop("No master files found in outputs/kamos/. Run 2_harmonize_all.R first.")
}

cat("Loading master wave files...\n")
wave_list <- list()

for (f in wave_files) {
  wave_name <- gsub("master_|\\.rds", "", basename(f))
  cat(sprintf("  %s: %s ... ", wave_name, basename(f)))
  df <- readRDS(f)
  cat(sprintf("%s rows, %d cols\n", format(nrow(df), big.mark = ","), ncol(df)))
  wave_list[[wave_name]] <- df
}

# ==============================================================================
# ADD COUNTRY AND YEAR
# ==============================================================================

cat("\nAdding country and year identifiers...\n")

survey_years <- c(w1 = 2016L, w2 = 2017L, w3 = 2018L, w4 = 2019L)

for (wave_name in names(wave_list)) {
  wave_list[[wave_name]]$country <- "KOR"
  wave_list[[wave_name]]$year    <- survey_years[[wave_name]]
  cat(sprintf("  %s → country=KOR, year=%d\n", wave_name, survey_years[[wave_name]]))
}

# ==============================================================================
# FIX W4 WEIGHT (no weight in raw data → assign 1.0)
# ==============================================================================

# Fix missing weights: W4 has no weight variable
for (wn in names(wave_list)) {
  if (all(is.na(wave_list[[wn]]$weight))) {
    cat(sprintf("\n%s weight is all NA — assigning 1.0 for unweighted analysis\n", wn))
    wave_list[[wn]]$weight <- 1.0
  }
}

# ==============================================================================
# COMBINE WAVES
# ==============================================================================

cat("\nCombining waves...\n")
kamos_combined <- bind_rows(wave_list)

# Convert wave column from character ("w1") to numeric (1, 4)
kamos_combined <- kamos_combined %>%
  mutate(wave = as.integer(gsub("w", "", wave)))

cat(sprintf("  Combined: %s rows, %d columns\n",
            format(nrow(kamos_combined), big.mark = ","),
            ncol(kamos_combined)))

# ==============================================================================
# CLEAN UP
# ==============================================================================

kamos_harmonized <- kamos_combined %>%
  select(-row_id)

# Zap any remaining haven labels
kamos_harmonized <- kamos_harmonized %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")),
                ~ as.numeric(haven::zap_labels(.x))))

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

wave_summary <- kamos_harmonized %>%
  group_by(wave, year) %>%
  summarise(n = n(), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s respondents, %d waves\n",
            format(nrow(kamos_harmonized), big.mark = ","),
            n_distinct(kamos_harmonized$wave)))

var_names <- setdiff(names(kamos_harmonized), c("wave", "year", "country", "weight"))
cat(sprintf("\n%d harmonized variables:\n", length(var_names)))
cat(paste0("  ", var_names, collapse = "\n"), "\n")

# ==============================================================================
# SAVE
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)

rds_path     <- here("data", "processed", "kamos_harmonized.rds")
parquet_path <- here("data", "processed", "kamos_harmonized.parquet")

saveRDS(kamos_harmonized, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

arrow::write_parquet(kamos_harmonized, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

saveRDS(kamos_harmonized, here("outputs", "kamos", "kamos_harmonized.rds"))

cat(sprintf("\n✅ kamos_harmonized saved: %s rows, %d columns\n",
            format(nrow(kamos_harmonized), big.mark = ","),
            ncol(kamos_harmonized)))
cat(strrep("=", 70), "\n\n")
