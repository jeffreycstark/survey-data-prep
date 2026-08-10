# KLoSA: Create final combined dataset
#
# Loads per-wave master files from outputs/klosa/, adds country/year/wave
# identifiers, stacks into a LONG person-wave panel (same pid recurs across
# waves -- this is the point, it enables clustering + panel robustness
# downstream), derives the participation indices, and saves
# klosa_harmonized.rds / .parquet.
#
# WAVE -> YEAR MAP:
#   w1=2006, w2=2008, w3=2010, w4=2012, w5=2014, w6=2016,
#   w7=2018, w8=2020, w9=2022

library(here)
library(dplyr)
library(arrow)

source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "keys.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))
source(here::here("src", "r", "utils", "education.R"))

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: klosa_harmonized\n")
cat(strrep("=", 70), "\n\n")

YEAR_MAP <- c(w1 = 2006, w2 = 2008, w3 = 2010, w4 = 2012, w5 = 2014,
              w6 = 2016, w7 = 2018, w8 = 2020, w9 = 2022)

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "klosa")
wave_files <- sort(list.files(output_dir, pattern = "^master_w[1-9]\\.rds$",
                               full.names = TRUE))

if (length(wave_files) == 0) {
  stop("No master files found in outputs/klosa/. Run 2_harmonize_all.R first.")
}

cat("Loading master wave files...\n")
wave_list <- list()

for (f in wave_files) {
  wave_name <- gsub("master_|\\.rds", "", basename(f))
  cat(sprintf("  %s: %s ... ", wave_name, basename(f)))
  df <- readRDS(f)
  cat(sprintf("%s rows, %d cols\n", format(nrow(df), big.mark = ","), ncol(df)))
  df$country <- "KOR"
  df$year    <- YEAR_MAP[[wave_name]]
  df$wave    <- as.integer(gsub("w", "", wave_name))
  wave_list[[wave_name]] <- df
}

# ==============================================================================
# COMBINE WAVES
# ==============================================================================

cat("\nCombining waves...\n")
klosa <- bind_rows(wave_list)

cat(sprintf("  Combined: %s person-wave rows, %d columns\n",
            format(nrow(klosa), big.mark = ","), ncol(klosa)))

# ==============================================================================
# CLEAN UP
# ==============================================================================

# Zap any remaining haven labels
klosa <- klosa %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")),
                ~ as.numeric(haven::zap_labels(.x))))

# ==============================================================================
# DERIVED: participation indices
# ==============================================================================
# Count of the 6 substantive group memberships (excludes part_none, which is
# a "no memberships" flag rather than a membership itself).

memb <- intersect(
  c("part_religious", "part_social_club", "part_leisure",
    "part_alumni", "part_volunteer", "part_civic"),
  names(klosa)
)

if (length(memb) > 0) {
  klosa <- klosa %>%
    mutate(
      participation_count = rowSums(across(all_of(memb)), na.rm = TRUE),
      participation_any   = as.integer(participation_count > 0)
    )
  cat(sprintf("\nDerived participation_count/participation_any from %d membership vars: %s\n",
              length(memb), paste(memb, collapse = ", ")))
} else {
  cat("\nNo participation membership variables found -- skipping derivation.\n")
}

# ==============================================================================
# DERIVED: shared 5-category education (guarded -- not yet mapped for KLoSA)
# ==============================================================================
# NOTE: add an edu5_from_klosa() mapping in src/r/utils/education.R keyed to
# the KLoSA education codes resolved in Task 2 before enabling this block.
# KLoSA stays on its native 4-level ladder until that mapping exists.
if ("education" %in% names(klosa) && exists("edu5_from_klosa")) {
  klosa <- klosa %>%
    mutate(
      education_5cat    = edu5_from_klosa(education),
      education_5cat_01 = edu5_to_01(education_5cat)
    )
  cat("Derived education_5cat/education_5cat_01 via edu5_from_klosa().\n")
} else {
  cat("edu5_from_klosa() not defined -- education_5cat NOT derived (KLoSA stays on native ladder).\n")
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

wave_summary <- klosa %>%
  group_by(wave, year) %>%
  summarise(n = n(), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s person-waves, %d distinct pid\n",
            format(nrow(klosa), big.mark = ","),
            dplyr::n_distinct(klosa$pid)))

var_names <- setdiff(names(klosa), c("wave", "year", "country", "weight", "pid"))
cat(sprintf("\n%d harmonized/derived variables:\n", length(var_names)))
cat(paste0("  ", var_names, collapse = "\n"), "\n")

# ==============================================================================
# SAVE
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)

rds_path     <- here("data", "processed", "klosa_harmonized.rds")
parquet_path <- here("data", "processed", "klosa_harmonized.parquet")

assert_row_uid(klosa, "klosa")

saveRDS(klosa, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

arrow::write_parquet(klosa, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

saveRDS(klosa, here("outputs", "klosa", "klosa_harmonized.rds"))

cat(sprintf("\n✅ klosa_harmonized saved: %s rows, %d columns\n",
            format(nrow(klosa), big.mark = ","), ncol(klosa)))
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# RUN MANIFEST (freshness -- Layer 6d)
# ==============================================================================

manifest_inputs  <- here("data", "klosa", "raw", sprintf("w0%d_e.sav", 1:9))
manifest_outputs <- c(
  rds_path,
  parquet_path,
  here("outputs", "klosa", "klosa_harmonized.rds")
)

write_manifest(
  survey      = "klosa",
  inputs      = manifest_inputs,
  specs       = list_survey_specs("klosa"),
  outputs     = manifest_outputs,
  output_path = here("outputs", "klosa", "manifest.json")
)

cat("Manifest written: ", here("outputs", "klosa", "manifest.json"), "\n", sep = "")

# ==============================================================================
# OUTPUT INVARIANTS (audit ticket E2)
# ==============================================================================
source(here("src", "r", "data_prep_modules", "2.5_validate_harmonization.R"))
results <- tryCatch(
  run_validation(survey = "klosa", save_report = TRUE, verbose = FALSE),
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
# LAYER-4 DIRECTION GATE (harmonization auditor Phase 5)
# ==============================================================================
# Deterministic direction checks on the freshly built output: label
# reconciliation (hard), battery coherence + anchor coverage (soft).
# REPORT-ONLY by default: prints findings, never stops this script. Set
# HARMONIZE_AUDIT_GATE=block to make label-reconciliation errors fail the
# pipeline.
source(here::here("src", "r", "audit", "99_post_harmonize_gate.R"))
run_post_harmonize_gate("klosa", quiet_checks = TRUE)
