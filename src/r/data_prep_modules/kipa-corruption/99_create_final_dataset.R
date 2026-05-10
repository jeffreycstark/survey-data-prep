# KIPA Corruption: Create final combined dataset
#
# Loads per-wave master files from outputs/kipa-corruption/, adds country
# and year identifiers, saves kipa_corruption_harmonized.rds/.parquet.

library(here)
library(dplyr)
library(arrow)

source(here::here("src", "r", "data_prep_modules", "kipa-corruption", "0_load_waves.R"))
source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: kipa_corruption_harmonized\n")
cat(strrep("=", 70), "\n\n")

output_dir <- here("outputs", "kipa-corruption")
wave_files <- sort(list.files(output_dir,
                              pattern = "^master_w[0-9]{4}\\.rds$",
                              full.names = TRUE))

if (length(wave_files) == 0) {
  stop("No master files found in outputs/kipa-corruption/. Run 2_harmonize_all.R first.")
}

cat("Loading master wave files...\n")
wave_list <- list()
for (f in wave_files) {
  wave_name <- gsub("master_|\\.rds", "", basename(f))
  df <- readRDS(f)
  cat(sprintf("  %s: %s rows, %d cols\n",
              wave_name, format(nrow(df), big.mark = ","), ncol(df)))
  wave_list[[wave_name]] <- df
}

cat("\nAdding country and year identifiers...\n")
for (wave_name in names(wave_list)) {
  year_val <- as.integer(gsub("w", "", wave_name))
  wave_list[[wave_name]]$country <- "KOR"
  wave_list[[wave_name]]$year    <- year_val
}

cat("\nCombining waves...\n")
combined <- bind_rows(wave_list)
combined <- combined %>%
  mutate(wave = as.integer(gsub("w", "", wave)))

cat(sprintf("  Combined: %s rows, %d columns\n",
            format(nrow(combined), big.mark = ","), ncol(combined)))

kipa_corruption_harmonized <- combined %>% select(-row_id)

# Zap any remaining haven labels
kipa_corruption_harmonized <- kipa_corruption_harmonized %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")),
                ~ as.numeric(haven::zap_labels(.x))))

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

wave_summary <- kipa_corruption_harmonized %>%
  group_by(wave, year) %>%
  summarise(n = n(), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s respondents, %d survey years\n",
            format(nrow(kipa_corruption_harmonized), big.mark = ","),
            n_distinct(kipa_corruption_harmonized$wave)))

var_names <- setdiff(names(kipa_corruption_harmonized),
                     c("wave", "year", "country", "weight"))
cat(sprintf("\n%d harmonized variables:\n", length(var_names)))
cat(paste0("  ", var_names, collapse = "\n"), "\n")

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)

rds_path     <- here("data", "processed", "kipa_corruption_harmonized.rds")
parquet_path <- here("data", "processed", "kipa_corruption_harmonized.parquet")

saveRDS(kipa_corruption_harmonized, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))
arrow::write_parquet(kipa_corruption_harmonized, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

saveRDS(kipa_corruption_harmonized,
        here("outputs", "kipa-corruption", "kipa_corruption_harmonized.rds"))

cat(sprintf("\n✅ kipa_corruption_harmonized saved: %s rows, %d columns\n",
            format(nrow(kipa_corruption_harmonized), big.mark = ","),
            ncol(kipa_corruption_harmonized)))
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# RUN MANIFEST (audit ticket C2)
# ==============================================================================
# Inputs: one .sav per KOSSDA handle directory (cumulative + annuals). The
# loader prefers the Korean-label .sav over an English copy in the same
# directory; mirror that policy when picking the file to hash.
.kipa_corr_pick_sav <- function(handle) {
  hdir <- here("data", "kipa-corruption", "raw", "unzipped", handle)
  if (!dir.exists(hdir)) return(NA_character_)
  files <- list.files(hdir, pattern = "\\.sav$|\\.SAV$", full.names = TRUE)
  if (length(files) == 0) return(NA_character_)
  kor <- files[!grepl("^eng_", basename(files), ignore.case = FALSE)]
  if (length(kor) > 0) return(kor[1])
  files[1]
}
manifest_inputs <- vapply(names(.kipa_corruption_handle_year),
                          .kipa_corr_pick_sav, character(1))
manifest_inputs <- unname(manifest_inputs[!is.na(manifest_inputs)])

manifest_outputs <- c(
  rds_path,
  parquet_path,
  here("outputs", "kipa-corruption", "kipa_corruption_harmonized.rds")
)

write_manifest(
  survey      = "kipa-corruption",
  inputs      = manifest_inputs,
  specs       = list_survey_specs("kipa-corruption"),
  outputs     = manifest_outputs,
  output_path = here("outputs", "kipa-corruption", "manifest.json")
)

cat("Manifest written: ",
    here("outputs", "kipa-corruption", "manifest.json"), "\n", sep = "")
