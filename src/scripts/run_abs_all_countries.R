## ============================================================================
## run_abs_all_countries.R
## Run slope_prospector on ABS data — ALL countries, full concept group analysis
##
## Output: outputs/prospecting/abs_all/
## ============================================================================

library(here)
library(tidyverse)

# ── 1. LOAD HARMONIZED ABS DATA ───────────────────────────────────────────────

cat("Loading ABS harmonized data...\n")
d <- readRDS(here("data", "processed", "abs_harmonized.rds"))
cat(sprintf("  %s rows, %d vars, waves %s\n",
            format(nrow(d), big.mark = ","), ncol(d),
            paste(sort(unique(d$wave)), collapse = ",")))

# ── 2. SELECT VARIABLES FOR ANALYSIS ─────────────────────────────────────────

nominal_vars <- c(
  "religion", "problem_most_important", "problem_govt_will_solve",
  "employment_type", "marital_status", "intl_development_model"
)

system_vars <- c(
  "wave", "country", "row_id", "idnumber",
  "weight", "weight_cross",
  "int_month", "int_year", "int_date"
)

raw_wave_cols <- grep("_w[1-6]$", names(d), value = TRUE)

exclude  <- c(system_vars, nominal_vars, raw_wave_cols)
numeric_vars <- names(d)[sapply(d, is.numeric)]
candidate_vars <- setdiff(numeric_vars, exclude)

# Drop vars with implausibly large values
var_maxabs <- sapply(candidate_vars, function(v) max(abs(d[[v]]), na.rm = TRUE))
vars <- candidate_vars[var_maxabs <= 100]

cat(sprintf("  Variables included in analysis: %d\n", length(vars)))

# ── 3. COMPUTE COUNTRY x WAVE MEANS ──────────────────────────────────────────

cat("Computing country-wave means...\n")
means_long <- d %>%
  select(country, wave, all_of(vars)) %>%
  pivot_longer(
    cols      = all_of(vars),
    names_to  = "variable",
    values_to = "value"
  ) %>%
  group_by(country, wave, variable) %>%
  summarise(
    mean_value = mean(value, na.rm = TRUE),
    sd_value   = sd(value, na.rm = TRUE),
    n          = sum(!is.na(value)),
    .groups    = "drop"
  ) %>%
  rename(wave_num = wave) %>%
  filter(!is.nan(mean_value))

cat(sprintf("  Means table: %s rows (%d countries x %d variables x waves)\n",
            format(nrow(means_long), big.mark = ","),
            n_distinct(means_long$country),
            n_distinct(means_long$variable)))

# Save means for reproducibility
means_csv <- here("outputs", "prospecting", "abs_all", "abs_all_means.csv")
dir.create(dirname(means_csv), recursive = TRUE, showWarnings = FALSE)
write_csv(means_long, means_csv)
cat(sprintf("  Saved means to: %s\n", means_csv))

# ── 4. CONFIGURE AND RUN PROSPECTOR ──────────────────────────────────────────

INPUT_PATH          <- means_csv
OUTPUT_DIR          <- here("outputs", "prospecting", "abs_all")
MIN_WAVES           <- 3
Z_THRESHOLD         <- 2.0
CONCEPT_GROUPS_PATH <- here("src", "scripts", "concept_groups.yml")
USE_WEIGHTED_SLOPES <- TRUE
DO_CLUSTERING       <- TRUE
DO_NARRATIVE        <- TRUE
DO_DASHBOARDS       <- TRUE
TITLE               <- "ABS All Countries (Waves 1-6)"

cat(sprintf("\nRunning prospector -> %s\n\n", OUTPUT_DIR))
source(here("src", "scripts", "slope_prospector.R"))

# ── 5. POLARIZATION (dispersion) DETECTION ───────────────────────────────────
cat("\n── Polarization detection (mean stable vs dispersion moving) ──\n")
source(here("src", "scripts", "prospector", "polarization.R"))
pol <- detect_polarization(means_long, out_dir = OUTPUT_DIR,
                           min_waves = MIN_WAVES, flat_threshold = FLAT_THRESHOLD)
pol_summary <- pol %>% count(pattern)
print(as.data.frame(pol_summary))
cat(sprintf("── Saved: %s/polarization.csv ──\n", OUTPUT_DIR))

cat("\nDone. Results in:", OUTPUT_DIR, "\n")
