# V-Dem: Create analysis-ready dataset
#
# Loads V-Dem v15, selects a core set of commonly used indices,
# and saves vdem_core.rds / .parquet to data/processed/.
#
# This is a SCAFFOLD — expand the variable list as needed for specific papers.
# For paper-specific subsets, filter by year range and country set in the
# consuming analysis script rather than here.
#
# UNIT: country-year (not individual respondents)
# COVERAGE: 202 countries, 1789–2024 (contemporary coverage from ~1900)
#
# KEY INDICES (all on 0–1 scale, higher = more democratic unless noted):
#   v2x_polyarchy    Electoral Democracy Index
#   v2x_libdem       Liberal Democracy Index
#   v2x_partipdem    Participatory Democracy Index
#   v2x_delibdem     Deliberative Democracy Index
#   v2x_egaldem      Egalitarian Democracy Index
#   v2x_corr         Political Corruption Index (higher = more corrupt)
#   v2x_accountability Accountability Index
#   v2x_freespeech   Freedom of Expression Index

library(here)
library(dplyr)
library(arrow)

source(here("src", "r", "data_prep_modules", "vdem", "0_load_vdem.R"))

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING V-Dem CORE DATASET\n")
cat(strrep("=", 70), "\n\n")

vdem_raw <- load_vdem()

# ==============================================================================
# SELECT CORE VARIABLES
# ==============================================================================
# Expand this list as papers require additional indices.
# Full codebook: data/v-dem/raw/v15/codebook.pdf

core_vars <- c(
  # Identifiers
  "country_name", "country_text_id", "country_id", "COWcode", "year",

  # High-level democracy indices (0-1)
  "v2x_polyarchy",    # Electoral Democracy Index
  "v2xel_frefair",    # Clean elections index (paper-28 electrust external validation)
  "e_gdppc",          # GDP per capita (Maddison-based; ⚠️ series ends 2019 —
                      # for 2020+ country-years join World Bank WDI at paper time)
  "v2x_libdem",       # Liberal Democracy Index
  "v2x_partipdem",    # Participatory Democracy Index
  "v2x_delibdem",     # Deliberative Democracy Index
  "v2x_egaldem",      # Egalitarian Democracy Index

  # Accountability & rule of law (0-1)
  "v2x_accountability",
  "v2x_rule",         # Rule of Law Index (if present)

  # Corruption (0-1, higher = more corrupt)
  "v2x_corr",

  # Civil liberties & expression (0-1)
  "v2x_freespeech",
  "v2xcl_rol",        # Civil Liberties Rule of Law

  # Regime type classification
  "v2x_regime",       # Regime classification (0=closed autocracy … 3=liberal democracy)
  "v2x_regime_amb"    # Ambiguous regime classification
)

available <- intersect(core_vars, names(vdem_raw))
missing   <- setdiff(core_vars, names(vdem_raw))

cat(sprintf("Core variables: %d available, %d missing\n",
            length(available), length(missing)))
if (length(missing) > 0) {
  cat("  Missing:", paste(missing, collapse = ", "), "\n")
}

vdem_core <- vdem_raw %>% select(all_of(available))

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")
cat(sprintf("  Rows:      %s\n", format(nrow(vdem_core), big.mark = ",")))
cat(sprintf("  Columns:   %d\n", ncol(vdem_core)))
cat(sprintf("  Countries: %d\n", length(unique(vdem_core$country_name))))
cat(sprintf("  Years:     %d–%d\n",
            min(vdem_core$year, na.rm = TRUE),
            max(vdem_core$year, na.rm = TRUE)))

# ==============================================================================
# SAVE
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)

rds_path     <- here("data", "processed", "vdem_core.rds")
parquet_path <- here("data", "processed", "vdem_core.parquet")

saveRDS(vdem_core, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

arrow::write_parquet(vdem_core, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

cat(sprintf("\n✅ vdem_core saved: %s rows, %d columns\n",
            format(nrow(vdem_core), big.mark = ","),
            ncol(vdem_core)))
cat(strrep("=", 70), "\n\n")

# ── Freshness manifest ──────────────────────────────────────────────────────
# specs = character(): V-Dem is a country-year panel, not a survey — no YAML
# harmonize specs, no waves, no questionnaire.
# engine = this module's own scripts, NOT the shared harmonize engine: nothing
# here calls harmonize_all() or recoding.R, so recording those four hashes would
# mark V-Dem STALE on every unrelated recoding.R edit.
source(here("src", "r", "utils", "provenance.R"))
write_manifest(
  survey  = "vdem",
  inputs  = Filter(file.exists,
                   here("data", "v-dem", "raw", "v15",
                        "V-Dem-CY-Full+Others-v15.rds")),
  specs   = character(),
  outputs = Filter(file.exists, c(rds_path, parquet_path)),
  engine  = c("src/r/data_prep_modules/vdem/0_load_vdem.R",
              "src/r/data_prep_modules/vdem/99_create_final_dataset.R")
)
cat("  -> manifest:", here("outputs", "vdem", "manifest.json"), "\n")
