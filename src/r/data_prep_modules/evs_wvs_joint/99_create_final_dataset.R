# Joint EVS/WVS 2017-2022: Create final dataset
#
# Single pooled cross-section (one "wave", 92 country-surveys, 2017-2023).
# country and year are per-row VARIABLES (harmonized from cntry_AN / year),
# never injected as constants. Country-level controls (V-Dem polyarchy,
# GDP pc) join at paper time on country+year from vdem_harmonized.

library(here)
library(dplyr)
library(arrow)

source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "keys.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))

cat("\n", strrep("=", 70), "\n", sep = "")
cat("CREATING FINAL DATASET: evs_wvs_joint_harmonized\n")
cat(strrep("=", 70), "\n\n")

f <- here("outputs", "evs_wvs_joint", "master_joint2017_2022.rds")
if (!file.exists(f)) stop("Run 2_harmonize_all.R first: missing ", f)
d <- readRDS(f)

d <- d %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")),
                ~ as.numeric(haven::zap_labels(.x))))

cat(sprintf("  %s rows, %d cols | studies: %s | countries: %d | years: %s-%s\n",
            format(nrow(d), big.mark = ","), ncol(d),
            paste(names(table(d$study)), table(d$study), sep = "=", collapse = " "),
            dplyr::n_distinct(d$country),
            min(d$year, na.rm = TRUE), max(d$year, na.rm = TRUE)))

assert_row_uid(d, "evs_wvs_joint")

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)
rds_path <- here("data", "processed", "evs_wvs_joint_harmonized.rds")
pq_path  <- here("data", "processed", "evs_wvs_joint_harmonized.parquet")
saveRDS(d, rds_path)
arrow::write_parquet(d, pq_path)
saveRDS(d, here("outputs", "evs_wvs_joint", "evs_wvs_joint_harmonized.rds"))
cat("  Saved:", rds_path, "\n")

write_manifest(
  survey      = "evs_wvs_joint",
  inputs      = c(here("data", "wvs", "raw", "evs_wvs_joint", "EVS_WVS_Joint_Spss_v5_0.sav")),
  specs       = list_survey_specs("evs_wvs_joint"),
  outputs     = c(rds_path, pq_path,
                  here("outputs", "evs_wvs_joint", "evs_wvs_joint_harmonized.rds")),
  output_path = here("outputs", "evs_wvs_joint", "manifest.json")
)
cat("Manifest written\n")

source(here("src", "r", "data_prep_modules", "2.5_validate_harmonization.R"))
results <- tryCatch(
  run_validation(survey = "evs_wvs_joint", save_report = TRUE, verbose = FALSE),
  error = function(e) { message("validation step failed: ", e$message); NULL })
if (!is.null(results)) {
  cat(sprintf("Invariants: ok=%d warn=%d error=%d skip=%d\n",
              results$counts$ok, results$counts$warn,
              results$counts$error, results$counts$skip))
}

source(here::here("src", "r", "audit", "99_post_harmonize_gate.R"))
run_post_harmonize_gate("evs_wvs_joint", quiet_checks = TRUE)
