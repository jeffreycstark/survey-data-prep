# 99_create_final_dataset.R
# Final step: Combine harmonized waves and create abs_econdev_authpref.rds
#
# This script:
# 1. Loads the master harmonized datasets from outputs/
# 2. Row-binds all waves into a single dataset
# 3. Applies known data corrections
# 4. Zaps haven labels for clean R usage
# 5. Saves as abs_econdev_authpref.rds

library(here)
library(dplyr)
library(haven)

cat("\n=== CREATING FINAL DATASET: abs_econdev_authpref.rds ===\n\n")

# Load all master wave files
output_dir <- here("outputs")
wave_files <- sort(list.files(output_dir, pattern = "^master_w[1-6]\\.rds$", full.names = TRUE))

cat("Loading master wave files...\n")
wave_list <- lapply(wave_files, function(f) {
  wave_name <- gsub("master_|\\.rds", "", basename(f))
  wave_num <- as.integer(gsub("w", "", wave_name))
  cat("  Loading", basename(f), "...")
  df <- readRDS(f)
  # Add wave column
  df$wave <- wave_num
  cat(format(nrow(df), big.mark = ","), "rows\n")
  df
})

# Combine all waves
cat("\nCombining waves...\n")
abs_combined <- bind_rows(wave_list)
cat("  Combined dataset:", format(nrow(abs_combined), big.mark = ","), "rows,",
    ncol(abs_combined), "columns\n")

cat("\nApplying known data corrections...\n")
cat("  None (all corrections handled during harmonization)\n")

# Zap haven labels (convert labelled vectors to regular R vectors)
cat("\nZapping haven labels...\n")
abs_econdev_authpref <- abs_combined %>%
  mutate(across(where(haven::is.labelled), haven::zap_labels))

# Also zap any remaining label attributes
abs_econdev_authpref <- abs_econdev_authpref %>%
  mutate(across(everything(), ~{
    attr(.x, "label") <- NULL
    attr(.x, "format.spss") <- NULL
    attr(.x, "display_width") <- NULL
    .x
  }))

cat("  Labels zapped successfully\n")

# Summary by wave
cat("\n=== WAVE SUMMARY ===\n")
wave_summary <- abs_econdev_authpref %>%
  group_by(wave) %>%
  summarise(n = n(), .groups = "drop")
print(wave_summary)

# Save final dataset to data/processed (primary) and outputs (backup)
output_file <- here("data", "processed", "abs_econdev_authpref.rds")
saveRDS(abs_econdev_authpref, output_file)

# Also save to outputs for convenience
saveRDS(abs_econdev_authpref, here("outputs", "abs_econdev_authpref.rds"))

cat("\n=== FINAL DATASET SAVED ===\n")
cat("File:", output_file, "\n")
cat("Rows:", format(nrow(abs_econdev_authpref), big.mark = ","), "\n")
cat("Columns:", ncol(abs_econdev_authpref), "\n")
cat("Waves:", paste(unique(abs_econdev_authpref$wave), collapse = ", "), "\n")

# List variables
cat("\nVariables:\n")
var_names <- setdiff(names(abs_econdev_authpref), c("wave", "row_id"))
cat(paste(" ", var_names, collapse = "\n"), "\n")

cat("\n", paste(rep("=", 60), collapse = ""), "\n", sep = "")
cat("DONE: abs_econdev_authpref.rds ready for analysis\n")
cat(paste(rep("=", 60), collapse = ""), "\n\n", sep = "")
