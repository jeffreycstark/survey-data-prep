## ============================================================================
## run_lbs_prospector.R
## Run slope_prospector on LBS data — ALL countries, 24 waves (1995-2024)
##
## Output: outputs/prospecting/lbs_all/
## ============================================================================

library(here)
library(tidyverse)

# -- 1. LOAD HARMONIZED LBS DATA -----------------------------------------------

cat("Loading LBS harmonized data...\n")
d <- readRDS(here("data", "processed", "lbs_harmonized.rds"))
cat(sprintf("  %s rows, %d vars, %d waves, %d countries\n",
            format(nrow(d), big.mark = ","), ncol(d),
            n_distinct(d$wave), n_distinct(d$country, na.rm = TRUE)))

# -- 2. SELECT VARIABLES FOR ANALYSIS ------------------------------------------

system_vars <- c("wave", "year", "country", "weight")

# All remaining numeric variables are candidates
numeric_vars <- names(d)[sapply(d, is.numeric)]
vars <- setdiff(numeric_vars, system_vars)

# Drop vars with implausibly large values
var_maxabs <- sapply(vars, function(v) max(abs(d[[v]]), na.rm = TRUE))
vars <- vars[var_maxabs <= 100]

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
means_csv <- here("outputs", "prospecting", "lbs_all", "lbs_all_means.csv")
dir.create(dirname(means_csv), recursive = TRUE, showWarnings = FALSE)
write_csv(means_long, means_csv)
cat(sprintf("  Saved means to: %s\n", means_csv))

# -- 4. CONFIGURE AND RUN PROSPECTOR -------------------------------------------

INPUT_PATH          <- means_csv
OUTPUT_DIR          <- here("outputs", "prospecting", "lbs_all")
MIN_WAVES           <- 3
Z_THRESHOLD         <- 2.0
CONCEPT_GROUPS_PATH <- here("src", "scripts", "concept_groups_lbs.yml")
USE_WEIGHTED_SLOPES <- TRUE
DO_CLUSTERING       <- TRUE
DO_NARRATIVE        <- TRUE
DO_DASHBOARDS       <- TRUE
TITLE               <- "LBS All Countries (24 waves, 1995-2024)"

cat(sprintf("\nRunning prospector -> %s\n\n", OUTPUT_DIR))
source(here("src", "scripts", "slope_prospector.R"))

cat("\nDone. Results in:", OUTPUT_DIR, "\n")
