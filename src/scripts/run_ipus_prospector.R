## ============================================================================
## run_ipus_prospector.R
## Run slope_prospector on IPUS harmonized data (Korea, 2007-2024)
##
## Output: outputs/prospecting/ipus/
##
## NOTE: IPUS is single-country (KOR). Country clustering is disabled.
## IPUS provides 18 annual waves — the longest Korean unification opinion
## series in our pipeline (KGSS 17 waves, KINU 13 fielding waves).
## ============================================================================

library(here)
library(tidyverse)

# ── 1. LOAD HARMONIZED IPUS DATA ──────────────────────────────────────────────

cat("Loading IPUS harmonized data...\n")
d <- readRDS(here("data", "processed", "ipus_harmonized.rds"))
cat(sprintf("  %s rows, %d vars, %d waves\n",
            format(nrow(d), big.mark = ","), ncol(d),
            n_distinct(d$wave)))

# ── 2. SELECT VARIABLES FOR ANALYSIS ─────────────────────────────────────────

system_vars <- c("wave", "year", "country", "row_id")

# Exclude nominal/categorical (IPUS-specific)
nominal_vars <- c("religion", "uni_view", "uni_timing", "nk_sk_relations")

exclude <- c(system_vars, nominal_vars)

numeric_vars <- names(d)[sapply(d, is.numeric)]
candidate_vars <- setdiff(numeric_vars, exclude)

# Drop vars with implausibly large values
var_maxabs <- sapply(candidate_vars, function(v) max(abs(d[[v]]), na.rm = TRUE))
vars <- candidate_vars[is.finite(var_maxabs) & var_maxabs <= 1000]

cat(sprintf("  Variables included in analysis: %d\n", length(vars)))
cat(sprintf("  Variables: %s\n", paste(vars, collapse = ", ")))

# ── 3. COMPUTE PER-WAVE MEANS ────────────────────────────────────────────────

cat("Computing per-wave means...\n")
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

output_dir <- here("outputs", "prospecting", "ipus")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
means_csv <- file.path(output_dir, "ipus_means.csv")
write_csv(means_long, means_csv)
cat(sprintf("  Saved means to: %s\n", means_csv))

# ── 4. CONFIGURE AND RUN PROSPECTOR ──────────────────────────────────────────

INPUT_PATH          <- means_csv
OUTPUT_DIR          <- output_dir
MIN_WAVES           <- 3
Z_THRESHOLD         <- 2.0
CONCEPT_GROUPS_PATH <- here("src", "scripts", "concept_groups_ipus.yml")  # may not exist; gracefully skipped
USE_WEIGHTED_SLOPES <- TRUE
DO_CLUSTERING       <- FALSE
DO_NARRATIVE        <- TRUE
DO_DASHBOARDS       <- TRUE
TITLE               <- "IPUS Unification Survey (Korea, 2007-2024)"

cat(sprintf("\nRunning prospector -> %s\n\n", OUTPUT_DIR))
source(here("src", "scripts", "slope_prospector.R"))

cat("\nDone. Results in:", OUTPUT_DIR, "\n")
