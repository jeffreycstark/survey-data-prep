## ============================================================================
## run_afro_prospector.R
## Run slope_prospector on Afrobarometer data — ALL countries, 9 rounds
##
## Output: outputs/prospecting/afro_all/
## ============================================================================

library(here)
library(tidyverse)

# -- 1. LOAD HARMONIZED AFRO DATA ----------------------------------------------

cat("Loading Afrobarometer harmonized data...\n")
d <- readRDS(here("data", "processed", "afro_harmonized.rds"))
cat(sprintf("  %s rows, %d vars, %d waves, %d countries\n",
            format(nrow(d), big.mark = ","), ncol(d),
            n_distinct(d$wave), n_distinct(d$country, na.rm = TRUE)))

# -- 2. SELECT VARIABLES FOR ANALYSIS ------------------------------------------

system_vars <- c("wave", "year", "country", "weight",
                 "int_month", "int_year", "int_date")

# All remaining numeric variables are candidates
numeric_vars <- names(d)[sapply(d, is.numeric)]
vars <- setdiff(numeric_vars, system_vars)

# Drop vars with implausibly large values or all-NA
var_maxabs <- sapply(vars, function(v) {
  vals <- d[[v]][!is.na(d[[v]])]
  if (length(vals) == 0) return(Inf)
  max(abs(vals))
})
vars <- vars[var_maxabs <= 100 & !is.infinite(var_maxabs)]

cat(sprintf("  Variables included in analysis: %d\n", length(vars)))
cat(sprintf("  Variables: %s\n", paste(vars, collapse = ", ")))

# -- 3. COMPUTE COUNTRY x WAVE MEANS -------------------------------------------

cat("Computing country-wave means...\n")
means_long <- d %>%
  select(country, wave, all_of(vars)) %>%
  filter(!is.na(country)) %>%
  pivot_longer(
    cols      = all_of(vars),
    names_to  = "variable",
    values_to = "value"
  ) %>%
  group_by(country, wave, variable) %>%
  summarise(
    mean_value = mean(value, na.rm = TRUE),
    n          = sum(!is.na(value)),
    .groups    = "drop"
  ) %>%
  rename(wave_num = wave) %>%
  filter(!is.nan(mean_value))

cat(sprintf("  Means table: %s rows (%d countries x %d variables x waves)\n",
            format(nrow(means_long), big.mark = ","),
            n_distinct(means_long$country),
            n_distinct(means_long$variable)))

# Save means
means_csv <- here("outputs", "prospecting", "afro_all", "afro_all_means.csv")
dir.create(dirname(means_csv), recursive = TRUE, showWarnings = FALSE)
write_csv(means_long, means_csv)
cat(sprintf("  Saved means to: %s\n", means_csv))

# -- 4. CONFIGURE AND RUN PROSPECTOR -------------------------------------------

INPUT_PATH          <- means_csv
OUTPUT_DIR          <- here("outputs", "prospecting", "afro_all")
MIN_WAVES           <- 3
Z_THRESHOLD         <- 2.0
CONCEPT_GROUPS_PATH <- here("src", "scripts", "concept_groups_afro.yml")
USE_WEIGHTED_SLOPES <- TRUE
DO_CLUSTERING       <- TRUE
DO_NARRATIVE        <- TRUE
DO_DASHBOARDS       <- TRUE
TITLE               <- "Afrobarometer All Countries (Rounds 1-9, 1999-2022)"

cat(sprintf("\nRunning prospector -> %s\n\n", OUTPUT_DIR))
source(here("src", "scripts", "slope_prospector.R"))

cat("\nDone. Results in:", OUTPUT_DIR, "\n")
