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
compute_means <- function(data) {
  data %>%
    select(country, wave, all_of(vars)) %>%
    pivot_longer(cols = all_of(vars), names_to = "variable", values_to = "value") %>%
    group_by(country, wave, variable) %>%
    summarise(
      mean_value = mean(value, na.rm = TRUE),
      sd_value   = sd(value, na.rm = TRUE),
      n          = sum(!is.na(value)),
      .groups    = "drop"
    ) %>%
    rename(wave_num = wave) %>%
    filter(!is.nan(mean_value))
}

# Long response-frequency table (parallels compute_means) for Pass C2 bimodality:
# same pivot to respondent-level `value`; drop missing; count per response code.
compute_freqs <- function(data) {
  data %>%
    select(country, wave, all_of(vars)) %>%
    pivot_longer(cols = all_of(vars), names_to = "variable", values_to = "value") %>%
    filter(!is.na(value)) %>%
    group_by(country, wave, variable, value) %>%
    summarise(count = n(), .groups = "drop") %>%
    rename(wave_num = wave)
}
means_long <- compute_means(d)

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
FLAT_THRESHOLD      <- 0.05   # shared by the prospector and polarization detection
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

# ── 6. SORTING (subgroup-gap) DETECTION — education cleavage ──────────────────
cat("\n── Sorting detection (high- vs low-education gap widening) ──\n")
if ("education_5cat" %in% names(d)) {
  m_hi <- compute_means(d %>% filter(education_5cat %in% c(4, 5)))   # post-secondary+
  m_lo <- compute_means(d %>% filter(education_5cat %in% c(1, 2)))   # none/primary
  gaps <- inner_join(m_hi, m_lo, by = c("country", "wave_num", "variable"),
                     suffix = c("_hi", "_lo")) %>%
    mutate(gap = mean_value_hi - mean_value_lo, n = pmin(n_hi, n_lo)) %>%
    filter(!str_detect(variable, "^education"))   # cleavage-on-itself is trivial
  srt <- detect_sorting(gaps, out_dir = OUTPUT_DIR, min_waves = MIN_WAVES,
                        flat_threshold = FLAT_THRESHOLD)
  print(as.data.frame(count(srt, pattern)))
  cat(sprintf("── Saved: %s/sorting.csv ──\n", OUTPUT_DIR))
} else {
  cat("(education_5cat absent — skipping sorting)\n")
}

# ── PASS C2: bimodality / two-camp split (van der Eijk A) ──────────────────────
cat("\n── Bimodality detection (two-camp split vs uniform spread) ──\n")
frq <- compute_freqs(d)
bim <- detect_bimodality(frq, out_dir = OUTPUT_DIR, min_waves = MIN_WAVES,
                         flat_threshold = FLAT_THRESHOLD, bimodal_A_max = 0.5)
cat(sprintf("bimodality.csv: %d POLARIZING_BIMODAL, %d CONVERGING_UNIMODAL, %d OTHER\n",
            sum(bim$pattern == "POLARIZING_BIMODAL"),
            sum(bim$pattern == "CONVERGING_UNIMODAL"),
            sum(bim$pattern == "OTHER")))

cat("\nDone. Results in:", OUTPUT_DIR, "\n")
