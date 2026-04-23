## ============================================================================
## generate_lbs_extended_specs.R
## Generate extended LBS YAML specs and pipeline files from the variable mapping CSV
## Extends from 5 waves (2015-2023) to 24 waves (1995-2024)
## ============================================================================

library(here)
library(tidyverse)

# ── 1. LOAD MAPPING TABLE ────────────────────────────────────────────────────

mapping <- read_csv(here("outputs", "prospecting", "lbs_variable_mapping.csv"),
                    show_col_types = FALSE)

cat(sprintf("Loaded mapping: %d rows, %d concepts, %d years\n",
            nrow(mapping), n_distinct(mapping$concept), n_distinct(mapping$year)))

# All years in order
all_years <- sort(unique(mapping$year))
cat(sprintf("Years: %s\n", paste(all_years, collapse = ", ")))

# Wave key convention: y1995, y1996, ...
wave_keys <- paste0("y", all_years)

# ── 2. PIVOT TO WIDE FORMAT (concept x year -> varname) ──────────────────────

mapping_wide <- mapping %>%
  select(year, concept, variable_name) %>%
  pivot_wider(names_from = year, values_from = variable_name, names_prefix = "y")

cat("\nMapping matrix:\n")
print(as.data.frame(mapping_wide), right = FALSE)

# ── 3. GENERATE YAML: institutional_trust.yml ────────────────────────────────

generate_source_block <- function(concept_name, mapping_wide, indent = "      ") {
  row <- mapping_wide %>% filter(concept == concept_name)
  if (nrow(row) == 0) return("      # NOT FOUND")

  lines <- character()
  for (yr in all_years) {
    key <- paste0("y", yr)
    val <- row[[key]]
    if (is.na(val)) {
      lines <- c(lines, sprintf("%s%s: null", indent, key))
    } else {
      lines <- c(lines, sprintf("%s%s: %s", indent, key, val))
    }
  }
  paste(lines, collapse = "\n")
}

# Trust variables
trust_vars <- list(
  list(id = "trust_churches",
       desc = "Confidence in the Church",
       concept = "trust_churches",
       phrase = "church"),
  list(id = "trust_armed_forces",
       desc = "Confidence in the Armed Forces",
       concept = "trust_armed_forces",
       phrase = "armed forces"),
  list(id = "trust_police",
       desc = "Confidence in the Police",
       concept = "trust_police",
       phrase = "police"),
  list(id = "trust_courts",
       desc = "Confidence in the Judiciary",
       concept = "trust_courts",
       phrase = "judic|court"),
  list(id = "trust_political_parties",
       desc = "Confidence in Political Parties",
       concept = "trust_political_parties",
       phrase = "party|parties"),
  list(id = "trust_parliament",
       desc = "Confidence in National Congress/Parliament",
       concept = "trust_parliament",
       phrase = "congress|parliament")
)

trust_yaml_lines <- c(
  "# LBS Institutional Trust (Confidence in Institutions)",
  sprintf("# Waves: %d years (%d-%d)", length(all_years), min(all_years), max(all_years)),
  "#",
  "# SCALE DIRECTION:",
  "# Raw: 1=A lot, 2=Some, 3=Little, 4=No trust",
  "# Target: 1=No trust, 2=Little, 3=Some, 4=A lot",
  "# All waves need safe_reverse_4pt so higher = more trust",
  "#",
  "# MISSING VALUES:",
  "# All waves: negative values are missing",
  "# -1=Don't know, -2=No answer, -3=Not applicable, -4=Not asked, -5=DK/NA combined",
  "",
  "missing_conventions:",
  "  treat_as_na:",
  "    codes: [-5, -4, -3, -2, -1]",
  "    description: \"LBS standard missing codes\"",
  "",
  "variables:"
)

for (tv in trust_vars) {
  trust_yaml_lines <- c(trust_yaml_lines,
    sprintf("  - id: %s", tv$id),
    "    concept: institutional_trust",
    sprintf("    description: \"%s\"", tv$desc),
    "    type: ordinal",
    "    source:",
    generate_source_block(tv$concept, mapping_wide),
    "    scale:",
    "      min: 1",
    "      max: 4",
    "      labels:",
    "        1: \"No trust\"",
    "        2: \"Little\"",
    "        3: \"Some\"",
    "        4: \"A lot\"",
    "    harmonize:",
    "      default:",
    "        method: r_function",
    "        fn: safe_reverse_4pt",
    "        note: \"All waves coded 1=A lot -> 4=No trust; reverse so high=trust\"",
    "    qc:",
    "      valid_range: [1, 4]",
    "      validate:",
    sprintf("        - waves: [%s]", paste(wave_keys, collapse = ", ")),
    sprintf("          phrase: \"%s\"", tv$phrase),
    ""
  )
}

writeLines(trust_yaml_lines, here("src", "config", "lbs", "harmonize", "institutional_trust.yml"))
cat("\nWrote institutional_trust.yml\n")

# ── 4. GENERATE YAML: social_trust.yml ───────────────────────────────────────

social_trust_yaml <- c(
  "# LBS Social / Interpersonal Trust",
  sprintf("# Waves: %d years (%d-%d)", length(all_years), min(all_years), max(all_years)),
  "#",
  "# SCALE DIRECTION:",
  "# Generalized trust binary:",
  "#   1=Most people can be trusted, 2=One can never be too careful",
  "#   Recode to 1=Trusted, 0=Careful",
  "#",
  "# MISSING VALUES:",
  "# All waves: negative values are missing",
  "",
  "missing_conventions:",
  "  treat_as_na:",
  "    codes: [-5, -4, -3, -2, -1]",
  "    description: \"LBS standard missing codes\"",
  "",
  "variables:",
  "  - id: trust_generalized_binary",
  "    concept: social_trust",
  "    description: \"Most people can be trusted vs. One can never be too careful\"",
  "    type: nominal",
  "    source:",
  generate_source_block("trust_generalized_binary", mapping_wide),
  "    scale:",
  "      min: 0",
  "      max: 1",
  "      labels:",
  "        1: \"Most people can be trusted\"",
  "        0: \"One can never be too careful\"",
  "    harmonize:",
  "      default:",
  "        method: r_function",
  "        fn: recode_binary_yes_no",
  "        note: \"Recode 1=Trusted, 2=Careful to 1=Trusted, 0=Careful\"",
  "    qc:",
  "      valid_range: [0, 1]",
  sprintf("      validate:\n        - waves: [%s]",
          paste(wave_keys[all_years != 1995], collapse = ", ")),
  "          phrase: \"trust.*people|interpersonal\"",
  ""
)

writeLines(social_trust_yaml, here("src", "config", "lbs", "harmonize", "social_trust.yml"))
cat("Wrote social_trust.yml\n")

# ── 5. GENERATE YAML: democratic_attitudes.yml ───────────────────────────────

dem_yaml <- c(
  "# LBS Democratic Attitudes",
  sprintf("# Waves: %d years (%d-%d)", length(all_years), min(all_years), max(all_years)),
  "#",
  "# MISSING VALUES:",
  "# All waves: negative values are missing",
  "",
  "missing_conventions:",
  "  treat_as_na:",
  "    codes: [-5, -4, -3, -2, -1]",
  "    description: \"LBS standard missing codes\"",
  "",
  "variables:",
  "  - id: dem_always_preferable",
  "    concept: democratic_attitudes",
  "    description: \"Support for democracy: Democracy is preferable (1) vs Authoritarian sometimes (2) vs Doesn't matter (3)\"",
  "    type: nominal",
  "    source:",
  generate_source_block("dem_always_preferable", mapping_wide),
  "    scale:",
  "      min: 1",
  "      max: 3",
  "      labels:",
  "        1: \"Democracy is preferable\"",
  "        2: \"Authoritarian sometimes preferable\"",
  "        3: \"Doesn't matter\"",
  "    harmonize:",
  "      default:",
  "        method: identity",
  "        note: \"All waves use same 1-3 coding. Nominal item.\"",
  "    qc:",
  "      valid_range: [1, 3]",
  "",
  "  - id: dem_satisfaction",
  "    concept: democratic_attitudes",
  "    description: \"Satisfaction with democracy (1-4, higher = more satisfied)\"",
  "    type: ordinal",
  "    source:",
  generate_source_block("dem_satisfaction", mapping_wide),
  "    scale:",
  "      min: 1",
  "      max: 4",
  "      labels:",
  "        1: \"Not at all satisfied\"",
  "        2: \"Not very satisfied\"",
  "        3: \"Quite satisfied\"",
  "        4: \"Very satisfied\"",
  "    harmonize:",
  "      default:",
  "        method: r_function",
  "        fn: safe_reverse_4pt",
  "        note: \"All waves coded 1=Very satisfied -> 4=Not at all; reverse so high=satisfied\"",
  "    qc:",
  "      valid_range: [1, 4]",
  ""
)

writeLines(dem_yaml, here("src", "config", "lbs", "harmonize", "democratic_attitudes.yml"))
cat("Wrote democratic_attitudes.yml\n")

# ── 6. GENERATE YAML: weight.yml ────────────────────────────────────────────

weight_yaml <- c(
  "# LBS Survey Weights",
  sprintf("# Waves: %d years (%d-%d)", length(all_years), min(all_years), max(all_years)),
  "",
  "missing_conventions:",
  "  treat_as_na:",
  "    codes: [-5, -4, -3, -2, -1]",
  "    description: \"LBS standard missing codes\"",
  "",
  "variables:",
  "  - id: weight",
  "    concept: weight",
  "    description: \"Survey weight\"",
  "    type: continuous",
  "    source:",
  generate_source_block("weight", mapping_wide),
  "    harmonize:",
  "      default:",
  "        method: identity",
  "    qc:",
  "      valid_range: [0, 100]",
  ""
)

writeLines(weight_yaml, here("src", "config", "lbs", "harmonize", "weight.yml"))
cat("Wrote weight.yml\n")

# ── 7. GENERATE 0_load_waves.R ──────────────────────────────────────────────

# Build file path finder for each year
load_lines <- c(
  "# LBS: Load wave data from .sav files",
  "# Creates wave list ready for harmonization",
  "#",
  sprintf("# %d waves: %s", length(all_years), paste(all_years, collapse = ", ")),
  "",
  "library(haven)",
  "library(here)",
  "",
  "#' Find English .sav file for a given year",
  "#'",
  "#' @param year Integer year",
  "#' @return Path to English .sav file",
  "find_lbs_eng_sav <- function(year) {",
  "  dir_path <- here::here(\"data\", \"lbs\", \"raw\", as.character(year))",
  "  files <- list.files(dir_path, pattern = \"\\\\.sav$\", full.names = TRUE, ignore.case = TRUE)",
  "  eng_files <- files[grepl(\"eng\", files, ignore.case = TRUE)]",
  "  if (length(eng_files) == 0) stop(sprintf(\"No English .sav file found for %d in %s\", year, dir_path))",
  "  eng_files[1]  # take first match",
  "}",
  "",
  "#' Load all LBS wave data",
  "#'",
  "#' Loads all available waves from English .sav files.",
  "#' Returns a named list with keys y1995, y1996, ..., y2024.",
  "#'",
  "#' @return Named list of dataframes",
  "#' @export",
  "load_lbs_waves <- function() {",
  "",
  sprintf("  years <- c(%s)", paste(all_years, collapse = ", ")),
  "  waves <- list()",
  "",
  "  for (yr in years) {",
  "    wave_key <- paste0(\"y\", yr)",
  "    path <- find_lbs_eng_sav(yr)",
  "    cat(sprintf(\"Loading %s from %s ... \", wave_key, basename(path)))",
  "    df <- haven::read_sav(path, encoding = \"latin1\")",
  "    waves[[wave_key]] <- df",
  "    cat(sprintf(\"%s rows, %s cols\\n\", format(nrow(df), big.mark = \",\"), ncol(df)))",
  "  }",
  "",
  "  cat(sprintf(\"\\nLoaded %d LBS waves\\n\", length(waves)))",
  "  waves",
  "}",
  ""
)

writeLines(load_lines, here("src", "r", "data_prep_modules", "lbs", "0_load_waves.R"))
cat("Wrote 0_load_waves.R\n")

# ── 8. GENERATE 99_create_final_dataset.R ────────────────────────────────────

final_lines <- c(
  "# LBS: Create final combined dataset",
  "#",
  "# This script:",
  "# 1. Loads per-wave master files from outputs/lbs/",
  "# 2. Adds country identifier (IDENPA) from raw .sav",
  "# 3. Row-binds waves into a single dataset",
  "# 4. Saves as lbs_harmonized.rds and .parquet",
  "",
  "library(here)",
  "library(dplyr)",
  "library(haven)",
  "library(arrow)",
  "",
  "# Load the wave finder function",
  "source(here::here(\"src/r/data_prep_modules/lbs/0_load_waves.R\"))",
  "",
  "cat(\"\\n\")",
  "cat(strrep(\"=\", 70), \"\\n\")",
  "cat(\"CREATING FINAL DATASET: lbs_harmonized\\n\")",
  "cat(strrep(\"=\", 70), \"\\n\\n\")",
  "",
  "# ==============================================================================",
  "# LOAD MASTER WAVE FILES",
  "# ==============================================================================",
  "",
  "output_dir <- here(\"outputs\", \"lbs\")",
  "wave_files <- sort(list.files(output_dir, pattern = \"^master_y[0-9]+\\\\.rds$\", full.names = TRUE))",
  "",
  "if (length(wave_files) == 0) {",
  "  stop(\"No master files found in outputs/lbs/. Run 2_harmonize_all.R first.\")",
  "}",
  "",
  "cat(\"Loading master wave files...\\n\")",
  "wave_list <- list()",
  "",
  "for (f in wave_files) {",
  "  wave_name <- gsub(\"master_|\\\\.rds\", \"\", basename(f))",
  "  cat(sprintf(\"  %s: %s ... \", wave_name, basename(f)))",
  "  df <- readRDS(f)",
  "  cat(sprintf(\"%s rows, %d cols\\n\", format(nrow(df), big.mark = \",\"), ncol(df)))",
  "  wave_list[[wave_name]] <- df",
  "}",
  "",
  "# ==============================================================================",
  "# ADD COUNTRY IDENTIFIER FROM RAW DATA",
  "# ==============================================================================",
  "",
  "cat(\"\\nAdding country identifiers from raw .sav files...\\n\")",
  "",
  "# LBS country codes (IDENPA) are ISO 3166-1 numeric codes",
  "idenpa_to_iso3 <- c(",
  "  \"32\" = \"ARG\", \"68\" = \"BOL\", \"76\" = \"BRA\", \"152\" = \"CHL\",",
  "  \"170\" = \"COL\", \"188\" = \"CRI\", \"214\" = \"DOM\", \"218\" = \"ECU\",",
  "  \"222\" = \"SLV\", \"320\" = \"GTM\", \"340\" = \"HND\", \"484\" = \"MEX\",",
  "  \"558\" = \"NIC\", \"591\" = \"PAN\", \"600\" = \"PRY\", \"604\" = \"PER\",",
  "  \"724\" = \"ESP\", \"858\" = \"URY\", \"862\" = \"VEN\"",
  ")",
  "",
  "# Country ID variable name differs across waves",
  "# Most waves: IDENPA; some early waves: idenpa or numpais",
  "find_country_var <- function(df) {",
  "  candidates <- c(\"IDENPA\", \"idenpa\", \"Idenpa\", \"numpais\", \"NUMPAIS\")",
  "  for (v in candidates) {",
  "    if (v %in% names(df)) return(v)",
  "  }",
  "  # Fallback: case-insensitive search",
  "  idx <- grep(\"^idenpa$\", names(df), ignore.case = TRUE)",
  "  if (length(idx) > 0) return(names(df)[idx[1]])",
  "  return(NULL)",
  "}",
  "",
  "for (wave_name in names(wave_list)) {",
  "  yr <- as.integer(gsub(\"y\", \"\", wave_name))",
  "  raw_path <- find_lbs_eng_sav(yr)",
  "",
  "  # Read just the country ID column",
  "  raw <- haven::read_sav(raw_path, encoding = \"latin1\")",
  "  cvar <- find_country_var(raw)",
  "",
  "  if (is.null(cvar)) {",
  "    warning(sprintf(\"No country ID variable found for %s\", wave_name))",
  "    wave_list[[wave_name]]$country <- NA_character_",
  "    next",
  "  }",
  "",
  "  country_codes <- as.character(as.integer(raw[[cvar]]))",
  "  country <- idenpa_to_iso3[country_codes]",
  "",
  "  if (length(country) != nrow(wave_list[[wave_name]])) {",
  "    warning(sprintf(\"Row count mismatch for %s: master=%d, raw=%d\",",
  "                    wave_name, nrow(wave_list[[wave_name]]), length(country)))",
  "  } else {",
  "    wave_list[[wave_name]]$country <- country",
  "    n_countries <- length(unique(na.omit(country)))",
  "    cat(sprintf(\"  %s: %d countries\\n\", wave_name, n_countries))",
  "  }",
  "}",
  "",
  "# ==============================================================================",
  "# ADD YEAR VARIABLE",
  "# ==============================================================================",
  "",
  "for (wave_name in names(wave_list)) {",
  "  wave_list[[wave_name]]$year <- as.integer(gsub(\"y\", \"\", wave_name))",
  "}",
  "",
  "# ==============================================================================",
  "# COMBINE WAVES",
  "# ==============================================================================",
  "",
  "cat(\"\\nCombining waves...\\n\")",
  "lbs_combined <- bind_rows(wave_list)",
  "",
  "# Convert wave column from character (\"y1995\") to numeric year",
  "lbs_combined <- lbs_combined %>%",
  "  mutate(wave = as.integer(gsub(\"y\", \"\", wave)))",
  "",
  "cat(sprintf(\"  Combined: %s rows, %d columns\\n\",",
  "            format(nrow(lbs_combined), big.mark = \",\"),",
  "            ncol(lbs_combined)))",
  "",
  "# ==============================================================================",
  "# CLEAN UP",
  "# ==============================================================================",
  "",
  "lbs_harmonized <- lbs_combined %>%",
  "  select(-row_id)",
  "",
  "# Zap any remaining haven labels",
  "lbs_harmonized <- lbs_harmonized %>%",
  "  mutate(across(where(~ inherits(.x, \"haven_labelled\")), ~ as.numeric(haven::zap_labels(.x))))",
  "",
  "# ==============================================================================",
  "# SUMMARY",
  "# ==============================================================================",
  "",
  "cat(\"\\n\", strrep(\"=\", 70), \"\\n\", sep = \"\")",
  "cat(\"DATASET SUMMARY\\n\")",
  "cat(strrep(\"=\", 70), \"\\n\\n\")",
  "",
  "cat(\"Respondents per wave:\\n\")",
  "wave_summary <- lbs_harmonized %>%",
  "  group_by(wave, year) %>%",
  "  summarise(n = n(), countries = n_distinct(country, na.rm = TRUE), .groups = \"drop\")",
  "print(as.data.frame(wave_summary))",
  "",
  "cat(sprintf(\"\\nTotal: %s respondents across %d waves\\n\",",
  "            format(nrow(lbs_harmonized), big.mark = \",\"),",
  "            n_distinct(lbs_harmonized$wave)))",
  "",
  "var_names <- setdiff(names(lbs_harmonized), c(\"wave\", \"year\", \"country\"))",
  "cat(sprintf(\"\\n%d harmonized variables:\\n\", length(var_names)))",
  "cat(paste(\"  \", var_names, collapse = \"\\n\"), \"\\n\")",
  "",
  "# ==============================================================================",
  "# SAVE",
  "# ==============================================================================",
  "",
  "cat(\"\\n\", strrep(\"=\", 70), \"\\n\", sep = \"\")",
  "cat(\"SAVING\\n\")",
  "cat(strrep(\"=\", 70), \"\\n\\n\")",
  "",
  "dir.create(here(\"data\", \"processed\"), showWarnings = FALSE, recursive = TRUE)",
  "",
  "rds_path <- here(\"data\", \"processed\", \"lbs_harmonized.rds\")",
  "saveRDS(lbs_harmonized, rds_path)",
  "cat(sprintf(\"  RDS:     %s\\n\", rds_path))",
  "",
  "parquet_path <- here(\"data\", \"processed\", \"lbs_harmonized.parquet\")",
  "arrow::write_parquet(lbs_harmonized, parquet_path)",
  "cat(sprintf(\"  Parquet: %s\\n\", parquet_path))",
  "",
  "saveRDS(lbs_harmonized, here(\"outputs\", \"lbs\", \"lbs_harmonized.rds\"))",
  "",
  "cat(sprintf(\"\\nlbs_harmonized saved: %s rows, %d columns\\n\",",
  "            format(nrow(lbs_harmonized), big.mark = \",\"),",
  "            ncol(lbs_harmonized)))",
  "cat(strrep(\"=\", 70), \"\\n\\n\")",
  ""
)

writeLines(final_lines, here("src", "r", "data_prep_modules", "lbs", "99_create_final_dataset.R"))
cat("Wrote 99_create_final_dataset.R\n")

cat("\n=== All files generated. Ready to run the pipeline. ===\n")
