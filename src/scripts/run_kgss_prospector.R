## ============================================================================
## run_kgss_prospector.R
## Run slope_prospector on KGSS harmonized data (Korea, 2003-2025)
##
## Output: outputs/prospecting/kgss/
##
## NOTE: KGSS is single-country (KOR). Country clustering is disabled.
## Wave = calendar year (2003-2025); slopes are expressed per year.
## ============================================================================

library(here)
library(tidyverse)

# ── 1. LOAD HARMONIZED KGSS DATA ──────────────────────────────────────────────

cat("Loading KGSS harmonized data...\n")
d <- readRDS(here("data", "processed", "kgss_harmonized.rds"))
cat(sprintf("  %s rows, %d vars, years %s\n",
            format(nrow(d), big.mark = ","), ncol(d),
            paste(sort(unique(d$wave)), collapse = ", ")))

# ── 2. SELECT VARIABLES FOR ANALYSIS ─────────────────────────────────────────

# Exclude system/identifier/weight variables
system_vars <- c("wave", "country", "row_id", "weight",
                 "resp_id", "yr_resp_id", "questionnaire_form")

# Exclude nominal/categorical variables that are not ordinal scales
nominal_vars <- c(
  "party_id",         # nominal, wave-incompatible party codes
  "party_pref",       # nominal, wave-incompatible party codes
  "ineq_success_factor"  # 3-category forced choice (hard work / luck / equal), not ordinal
)

# Exclude binary electoral participation (1=voted, 2=did not)
# These are binary indicators, not meaningful scales for slope analysis
binary_vars <- c("voted_presidential", "voted_general", "voted_local")

exclude <- c(system_vars, nominal_vars, binary_vars)

numeric_vars <- names(d)[sapply(d, is.numeric)]
candidate_vars <- setdiff(numeric_vars, exclude)

# Drop any vars with implausibly large values (catches raw codes that slipped through)
var_maxabs <- sapply(candidate_vars, function(v) max(abs(d[[v]]), na.rm = TRUE))
vars <- candidate_vars[var_maxabs <= 100]

cat(sprintf("  Variables included in analysis: %d\n", length(vars)))

# ── 3. COMPUTE YEAR MEANS (single country = KOR) ─────────────────────────────

cat("Computing year means...\n")
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
    n          = sum(!is.na(value)),
    .groups    = "drop"
  ) %>%
  rename(wave_num = wave) %>%
  filter(!is.nan(mean_value), n > 0)

cat(sprintf("  Means table: %s rows (%d country x %d variables x %d waves)\n",
            format(nrow(means_long), big.mark = ","),
            n_distinct(means_long$country),
            n_distinct(means_long$variable),
            n_distinct(means_long$wave_num)))

# Save means for reproducibility
output_dir <- here("outputs", "prospecting", "kgss")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
means_csv <- file.path(output_dir, "kgss_means.csv")
write_csv(means_long, means_csv)
cat(sprintf("  Saved means to: %s\n", means_csv))

# ── 4. CONFIGURE AND RUN PROSPECTOR ──────────────────────────────────────────

INPUT_PATH          <- means_csv
OUTPUT_DIR          <- output_dir
MIN_WAVES           <- 3        # drop vars with < 3 survey years
Z_THRESHOLD         <- 2.0      # outlier z-score threshold (across variables, not countries)
CONCEPT_GROUPS_PATH <- here("src", "scripts", "concept_groups_kgss.yml")
USE_WEIGHTED_SLOPES <- TRUE
DO_CLUSTERING       <- FALSE    # meaningless with a single country
DO_NARRATIVE        <- TRUE     # check theoretical signatures in KOR time series
DO_DASHBOARDS       <- TRUE     # main output: concept group trajectories over time
TITLE               <- "KGSS Korea (2003-2025)"

cat(sprintf("\nRunning prospector -> %s\n\n", OUTPUT_DIR))
source(here("src", "scripts", "slope_prospector.R"))

cat("\nDone. Results in:", OUTPUT_DIR, "\n")
