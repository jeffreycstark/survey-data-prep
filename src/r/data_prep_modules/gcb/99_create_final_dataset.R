# GCB: Create final combined dataset
#
# Loads per-edition master files from outputs/gcb/, adds a `region` label,
# stacks them, and writes data/processed/gcb_harmonized.rds / .parquet.
#
# country / respondent_id / weights / fieldwork_year are already per-row
# harmonized columns (see src/config/gcb/harmonize/gcb_identifiers.yml), so this
# script only adds the edition-level `region` label and combines.

library(here)
library(dplyr)
library(arrow)

source(here::here("src", "r", "data_prep_modules", "gcb", "0_load_waves.R"))

cat("\n", strrep("=", 70), "\n", sep = "")
cat("CREATING FINAL DATASET: gcb_harmonized\n")
cat(strrep("=", 70), "\n\n")

output_dir <- here("outputs", "gcb")
wave_files <- sort(list.files(output_dir, pattern = "^master_.*\\.rds$",
                              full.names = TRUE))
if (length(wave_files) == 0) {
  stop("No master files found in outputs/gcb/. Run 2_harmonize_all.R first.")
}

cat("Loading master edition files...\n")
pieces <- list()
for (f in wave_files) {
  wave_name <- gsub("master_|\\.rds", "", basename(f))
  df <- readRDS(f)
  df$region <- unname(GCB_EDITION_REGION[wave_name])
  cat(sprintf("  %-10s %s rows, %d cols (region=%s)\n",
              wave_name, format(nrow(df), big.mark = ","), ncol(df), df$region[1]))
  pieces[[wave_name]] <- df
}

gcb_harmonized <- bind_rows(pieces) %>%
  relocate(wave, region, row_id)

out_rds <- here("data", "processed", "gcb_harmonized.rds")
out_pq  <- here("data", "processed", "gcb_harmonized.parquet")
dir.create(dirname(out_rds), showWarnings = FALSE, recursive = TRUE)
saveRDS(gcb_harmonized, out_rds)
arrow::write_parquet(gcb_harmonized, out_pq)

cat(sprintf("\n✅ Saved %s rows, %d cols across %d edition(s)\n",
            format(nrow(gcb_harmonized), big.mark = ","),
            ncol(gcb_harmonized), length(pieces)))
cat(sprintf("   %s\n   %s\n", out_rds, out_pq))

# Quick country x edition coverage
cat("\nRespondents by edition:\n")
print(table(gcb_harmonized$wave))

# ==============================================================================
# LAYER-4 DIRECTION GATE (harmonization auditor Phase 5)
# ==============================================================================
# Deterministic direction checks on the freshly built output: label
# reconciliation (hard), battery coherence + anchor coverage (soft).
# REPORT-ONLY by default: prints findings, never stops this script. Set
# HARMONIZE_AUDIT_GATE=block to make label-reconciliation errors fail the
# pipeline (flip once the label-recon backlog is cleared).
source(here::here("src", "r", "audit", "99_post_harmonize_gate.R"))
run_post_harmonize_gate("gcb", quiet_checks = TRUE)
