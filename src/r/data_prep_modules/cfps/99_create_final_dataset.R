# CFPS: Create final combined dataset
#
# Loads per-wave master files from outputs/cfps/, adds country and year
# identifiers, and saves cfps_harmonized.rds / .parquet.
#
# SURVEY WAVES (adult module): 2010, 2014. CFPS is a FAMILY PANEL — rows are
# person-waves keyed by `pid`; cluster on pid, never treat rows as independent.
# 2016/2018/2020/2022 join when their files are downloaded (the Dataverse
# bundle cap skipped them — see data/cfps/raw/MANIFEST.TXT).
#
# WEIGHTS: weight_cs (cross-sectional national person weight per wave),
# weight_panel (2010-2014 panel weight, w2014 rows only).

library(here)
library(dplyr)
library(arrow)

source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: cfps_harmonized\n")
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "cfps")
wave_files <- sort(list.files(output_dir,
                              pattern = "^master_w[0-9]{4}\\.rds$",
                              full.names = TRUE))

if (length(wave_files) == 0) {
  stop("No master files found in outputs/cfps/. Run 2_harmonize_all.R first.")
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

for (wave_name in names(wave_list)) {
  year_val <- as.integer(gsub("w", "", wave_name))
  wave_list[[wave_name]]$country <- "CHN"
  wave_list[[wave_name]]$year    <- year_val
  cat(sprintf("  %s → country=CHN, year=%d\n", wave_name, year_val))
}

# ==============================================================================
# COMBINE WAVES
# ==============================================================================

cat("\nCombining waves...\n")
cfps_combined <- bind_rows(wave_list)

# wave column: calendar year integer
cfps_combined <- cfps_combined %>%
  mutate(wave = as.integer(gsub("w", "", wave)))

cat(sprintf("  Combined: %s rows, %d columns\n",
            format(nrow(cfps_combined), big.mark = ","),
            ncol(cfps_combined)))

# ==============================================================================
# CLEAN UP
# ==============================================================================

cfps_harmonized <- cfps_combined %>%
  select(-row_id)

# Zap any remaining haven labels
cfps_harmonized <- cfps_harmonized %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")),
                ~ as.numeric(haven::zap_labels(.x))))

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

wave_summary <- cfps_harmonized %>%
  group_by(wave, year) %>%
  summarise(n = n(), n_pid = n_distinct(pid), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s person-waves, %s distinct pid\n",
            format(nrow(cfps_harmonized), big.mark = ","),
            format(n_distinct(cfps_harmonized$pid), big.mark = ",")))

var_names <- setdiff(names(cfps_harmonized), c("wave", "year", "country"))
cat(sprintf("\n%d harmonized variables:\n", length(var_names)))
cat(paste0("  ", var_names, collapse = "\n"), "\n")

# ==============================================================================
# SAVE
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)

rds_path     <- here("data", "processed", "cfps_harmonized.rds")
parquet_path <- here("data", "processed", "cfps_harmonized.parquet")

saveRDS(cfps_harmonized, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

arrow::write_parquet(cfps_harmonized, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

saveRDS(cfps_harmonized, here("outputs", "cfps", "cfps_harmonized.rds"))

cat(sprintf("\n✅ cfps_harmonized saved: %s rows, %d columns\n",
            format(nrow(cfps_harmonized), big.mark = ","),
            ncol(cfps_harmonized)))
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# RUN MANIFEST
# ==============================================================================

manifest_inputs <- c(
  here("data", "cfps", "raw", "unzipped", "cfps2010_stata_chinese",
       "[CFPS Public Data] CFPS 2010 in Stata (Chinese)", "cfps2010adult_202008.dta"),
  here("data", "cfps", "raw", "unzipped", "cfps2014_sas_chinese",
       "[CFPS Public Data] CFPS2014 in SAS (Chinese)", "cfps2014adult_201906.sas7bdat")
)
manifest_outputs <- c(
  rds_path,
  parquet_path,
  here("outputs", "cfps", "cfps_harmonized.rds")
)

write_manifest(
  survey      = "cfps",
  inputs      = manifest_inputs,
  specs       = list_survey_specs("cfps"),
  outputs     = manifest_outputs,
  output_path = here("outputs", "cfps", "manifest.json")
)

cat("Manifest written: ", here("outputs", "cfps", "manifest.json"), "\n", sep = "")

# ==============================================================================
# OUTPUT INVARIANTS
# ==============================================================================
source(here("src", "r", "data_prep_modules", "2.5_validate_harmonization.R"))
results <- tryCatch(
  run_validation(survey = "cfps", save_report = TRUE, verbose = FALSE),
  error = function(e) { message("validation step failed: ", e$message); NULL }
)
if (!is.null(results)) {
  cat(sprintf(
    "Invariants: ok=%d warn=%d error=%d skip=%d (total=%d)\n",
    results$counts$ok, results$counts$warn,
    results$counts$error, results$counts$skip,
    nrow(results$summary)
  ))
}

# ==============================================================================
# LAYER-4 DIRECTION GATE
# ==============================================================================
source(here::here("src", "r", "audit", "99_post_harmonize_gate.R"))
run_post_harmonize_gate("cfps", quiet_checks = TRUE)
