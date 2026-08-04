# CFPS: Create final combined dataset
#
# Loads per-wave master files from outputs/cfps/, adds country/year/wave
# identifiers, stacks into a LONG person-wave panel (the same pid recurs across
# waves — that is the point), derives the exact birth date, and saves
# cfps_harmonized.rds / .parquet.
#
# WAVE -> YEAR MAP: CFPS waves ARE years. y2010, y2012, y2014, y2016, y2018, y2020.
#
# STATUS: SCAFFOLD — depends on YAML specs that do not yet carry resolved
# source-variable names. Run 00_probe_variables.R first.

library(here)
library(dplyr)
library(arrow)

source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))
source(here::here("src", "r", "utils", "education.R"))

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: cfps_harmonized\n")
cat(strrep("=", 70), "\n\n")

YEAR_MAP <- c(y2010 = 2010, y2012 = 2012, y2014 = 2014,
              y2016 = 2016, y2018 = 2018, y2020 = 2020)

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "cfps")
wave_files <- sort(list.files(output_dir, pattern = "^master_y[0-9]{4}\\.rds$",
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
  df$country <- "CHN"
  df$year    <- YEAR_MAP[[wave_name]]
  df$wave    <- YEAR_MAP[[wave_name]]   # CFPS waves are years; wave == year by design
  wave_list[[wave_name]] <- df
}

# ==============================================================================
# COMBINE WAVES
# ==============================================================================

cat("\nCombining waves...\n")
cfps <- bind_rows(wave_list)
if ("row_id" %in% names(cfps)) cfps <- cfps %>% select(-row_id)

cat(sprintf("  Combined: %s person-wave rows, %d columns\n",
            format(nrow(cfps), big.mark = ","), ncol(cfps)))

# ==============================================================================
# CLEAN UP
# ==============================================================================

cfps <- cfps %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")),
                ~ as.numeric(haven::zap_labels(.x))))

# ==============================================================================
# DERIVED: exact birth date
# ==============================================================================
# The whole reason this survey is here. Downstream (paper 26) builds a
# days-from-lunar-boundary running variable off birth_date, so this column is
# load-bearing for an RD — a silently malformed date is worse than a missing
# one, because it still estimates.
#
# ⚠ CALENDAR TYPE: if the probe found a solar/lunar (阳历/农历) flag, it MUST be
# carried through as birth_calendar and respected here. A lunar-reported date
# treated as solar corrupts the running variable in a way that correlates with
# treatment. Do NOT quietly construct birth_date across mixed calendar types.

has_ymd <- all(c("birth_year", "birth_month", "birth_day") %in% names(cfps))

if (has_ymd) {

  if ("birth_calendar" %in% names(cfps)) {
    tab <- table(cfps$birth_calendar, useNA = "ifany")
    cat("\nbirth_calendar distribution:\n"); print(tab)
    cat("→ Construct birth_date ONLY for solar-reported rows; lunar-reported rows\n")
    cat("  need conversion (lunardate::lunar_to_solar) before they are comparable.\n")
  } else {
    warning(
      "No birth_calendar column. CFPS birth dates may mix solar and lunar ",
      "reporting; constructing birth_date as if all dates are solar is an ",
      "ASSUMPTION, not a fact. Document it and flag it to the consuming paper."
    )
  }

  cfps <- cfps %>%
    mutate(
      birth_date = suppressWarnings(as.Date(sprintf(
        "%04d-%02d-%02d", birth_year, birth_month, birth_day))),
      birth_date_exact = as.integer(!is.na(birth_date))
    )

  n_exact <- sum(cfps$birth_date_exact == 1, na.rm = TRUE)
  cat(sprintf("\nDerived birth_date: %s of %s person-waves have an exact date (%.1f%%)\n",
              format(n_exact, big.mark = ","),
              format(nrow(cfps), big.mark = ","),
              100 * n_exact / nrow(cfps)))
  cat("→ This percentage IS the RD's usable-sample ceiling. Report it in the paper body.\n")

} else {
  cat("\nbirth_year/birth_month/birth_day not all present -- birth_date NOT derived.\n")
  cat("→ Without an exact birth date the lunar-boundary RD is not identified.\n")
}

# ==============================================================================
# DERIVED: shared 5-category education (guarded)
# ==============================================================================
if ("education" %in% names(cfps) && exists("edu5_from_cfps")) {
  cfps <- cfps %>%
    mutate(
      education_5cat    = edu5_from_cfps(education),
      education_5cat_01 = edu5_to_01(education_5cat)
    )
  cat("Derived education_5cat/education_5cat_01 via edu5_from_cfps().\n")
} else {
  cat("edu5_from_cfps() not defined -- education_5cat NOT derived (CFPS stays on native ladder).\n")
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

wave_summary <- cfps %>%
  group_by(wave, year) %>%
  summarise(n = n(), .groups = "drop")
print(as.data.frame(wave_summary))

if ("pid" %in% names(cfps)) {
  cat(sprintf("\nTotal: %s person-waves, %d distinct pid\n",
              format(nrow(cfps), big.mark = ","),
              dplyr::n_distinct(cfps$pid)))
}

var_names <- setdiff(names(cfps), c("wave", "year", "country", "weight", "pid"))
cat(sprintf("\n%d harmonized/derived variables:\n", length(var_names)))
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

saveRDS(cfps, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

arrow::write_parquet(cfps, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

saveRDS(cfps, here("outputs", "cfps", "cfps_harmonized.rds"))

cat(sprintf("\n✅ cfps_harmonized saved: %s rows, %d columns\n",
            format(nrow(cfps), big.mark = ","), ncol(cfps)))
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# RUN MANIFEST (freshness -- Layer 6d)
# ==============================================================================

manifest_inputs <- unlist(lapply(CFPS_WAVES, function(y) {
  tryCatch(find_cfps_wave_file(y), error = function(e) NULL)
}))

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
# OUTPUT INVARIANTS (audit ticket E2)
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
# LAYER-4 DIRECTION GATE (harmonization auditor Phase 5)
# ==============================================================================
source(here::here("src", "r", "audit", "99_post_harmonize_gate.R"))
run_post_harmonize_gate("cfps", quiet_checks = TRUE)
