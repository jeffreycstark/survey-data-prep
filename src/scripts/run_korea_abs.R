## ============================================================================
## run_korea_abs.R
## Run slope_prospector on ABS data — South Korea paper prospecting
##
## Purpose: Identify anomalous trend patterns in South Korea relative to
## all other ABS countries. Outliers here are puzzles, not conclusions —
## each finding needs a political timeline check + methodology check before
## it becomes a paper.
##
## Output: outputs/prospecting/korea_abs/
##   - outlier_slopes.csv      country-variable pairs with |z| > 2
##   - structural_breaks.csv   stable-then-broke patterns (p < .05)
##   - divergent_pairs.csv     variables moving in opposite directions
##   - acceleration.csv        early vs late period slope changes
##   - heatmap_slopes.png      full country × variable heatmap
##   - outlier_dotplot.png     ranked outlier dot plot
##   - profile_korea.png       Korea deep-dive trend profile
##   - prospecting_report.md   summary of findings
## ============================================================================

library(here)
library(tidyverse)
library(arrow)

# ── 1. LOAD HARMONIZED ABS DATA ───────────────────────────────────────────────

cat("Loading ABS harmonized data...\n")
d <- readRDS(here("data", "processed", "abs_harmonized.rds"))
cat(sprintf("  %s rows, %d vars, waves %s\n",
            format(nrow(d), big.mark = ","), ncol(d),
            paste(sort(unique(d$wave)), collapse = ",")))

# ── 2. SELECT VARIABLES FOR ANALYSIS ─────────────────────────────────────────
#
# Exclude:
#   (a) System / identifier columns
#   (b) Named nominal-coded variables whose means are meaningless
#       (e.g., religion codes go to 9990, party codes are arbitrary integers)
#   (c) Per-wave raw columns (e.g., trust_military_w1)
#   (d) Any variable where max(|value|) > 100 — almost certainly an
#       uncollapsed categorical code that slipped through

nominal_vars <- c(
  "religion",                  # codes up to ~9990 (denomination labels)
  "problem_most_important",    # nominal issue/party codes
  "problem_govt_will_solve",   # nominal codes
  "employment_type",           # categorical occupation codes
  "marital_status",            # categorical
  "intl_development_model"     # nominal country codes (1=China, 2=USA, ...)
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

# ── 3. COMPUTE COUNTRY × WAVE MEANS ──────────────────────────────────────────

cat("Computing country-wave means...\n")
means_long <- d %>%
  select(country, wave, all_of(vars)) %>%
  pivot_longer(
    cols      = all_of(vars),
    names_to  = "variable",
    values_to = "value"
  ) %>%
  group_by(country, wave, variable) %>%
  summarise(mean_value = mean(value, na.rm = TRUE), .groups = "drop") %>%
  rename(wave_num = wave) %>%
  filter(!is.nan(mean_value))

cat(sprintf("  Means table: %s rows (%d countries × %d variables × waves)\n",
            format(nrow(means_long), big.mark = ","),
            n_distinct(means_long$country),
            n_distinct(means_long$variable)))

# ── 4. WRITE MEANS TO TEMP CSV ────────────────────────────────────────────────

tmp_csv <- tempfile(fileext = ".csv")
write_csv(means_long, tmp_csv)

# ── 5. CONFIGURE AND RUN PROSPECTOR ──────────────────────────────────────────

INPUT_PATH       <- tmp_csv
OUTPUT_DIR       <- here("outputs", "prospecting", "korea_abs")
MIN_WAVES        <- 3
Z_THRESHOLD      <- 2.0
VARS_OF_INTEREST <- NULL   # all vars

cat(sprintf("\nRunning prospector → %s\n\n", OUTPUT_DIR))
source(here("src", "scripts", "slope_prospector.R"))

# ── 6. FORCE KOREA PROFILE ────────────────────────────────────────────────────
# The prospector generates profiles for all outlier countries;
# explicitly force Korea even if it has no outliers itself.

cat("\n── Generating Korea deep-dive profile ──\n")
plot_country_profile(harmonized_data, "Korea")

# ── 7. CLEAN UP ───────────────────────────────────────────────────────────────

unlink(tmp_csv)
cat("\nDone. Results in:", OUTPUT_DIR, "\n")
