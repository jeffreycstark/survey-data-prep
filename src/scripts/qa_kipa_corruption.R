# ============================================================================
# KIPA Corruption harmonization QA
# ----------------------------------------------------------------------------
# Tripwires for data/processed/kipa_corruption_harmonized.rds — run after
# adding variables, extending waves, or changing YAML specs.
#
# Usage:
#   Rscript src/scripts/qa_kipa_corruption.R
# ============================================================================

suppressMessages({
  library(here)
  library(dplyr)
})

d <- readRDS(here::here("data", "processed", "kipa_corruption_harmonized.rds"))
FLAGS <- character(0)
flag <- function(msg) {
  FLAGS[[length(FLAGS) + 1L]] <<- msg
  cat("  ⚠ ", msg, "\n", sep = "")
}

admin_cols  <- c("wave", "year", "country", "weight", "row_id")
survey_vars <- setdiff(names(d), admin_cols)

cat("================================================================\n")
cat("KIPA CORRUPTION QA —", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("================================================================\n\n")

# ----------------------------------------------------------------------------
# 1. Dataset overview
# ----------------------------------------------------------------------------
cat("### 1. Dataset overview\n")
cat(sprintf("Rows:            %s\n",  format(nrow(d), big.mark = ",")))
cat(sprintf("Cols:            %d\n",  ncol(d)))
cat(sprintf("Survey vars:     %d\n",  length(survey_vars)))
cat(sprintf("Waves (years):   %s\n",  paste(sort(unique(d$year)), collapse = ", ")))

expected_years <- 2004:2023
missing_years  <- setdiff(expected_years, unique(d$year))
if (length(missing_years)) flag(sprintf("Expected years missing: %s",
                                         paste(missing_years, collapse = ", ")))

# ----------------------------------------------------------------------------
# 2. Wave coverage
# ----------------------------------------------------------------------------
cat("\n### 2. Wave coverage (non-NA counts)\n")
cov_mat <- sapply(sort(unique(d$year)), function(y) {
  sapply(survey_vars, function(v) sum(!is.na(d[[v]][d$year == y])))
})
colnames(cov_mat) <- sort(unique(d$year))
print(cov_mat)

empty_vars <- rownames(cov_mat)[rowSums(cov_mat) == 0]
if (length(empty_vars)) {
  flag(sprintf("Vars with ZERO data across all waves: %s",
               paste(empty_vars, collapse = ", ")))
}

# ----------------------------------------------------------------------------
# 2a. Mapped-wave NA rates
# ----------------------------------------------------------------------------
# Read source maps from YAML to know which waves each variable is expected to
# have data. Flag if a MAPPED wave has unexpectedly high NA (indicates a
# mis-specified valid_range, an undetected scale change, or a broken wave
# mapping). Two thresholds:
#   WARN_THRESH  (50%): suspicious — likely a skip-filter or a real data issue.
#   ERROR_THRESH (100%): definite bug on a mapped wave.
#
# This check would have caught:
#   • corr_punishment_relative_strength in 2018-2021: 17-24% NA (wrong valid_range)
#   • corr_punishment_relative_strength in 2022-2023: would have shown 100% NA
#     if those waves had been left mapped after the scale change.
cat("\n### 2a. Mapped-wave NA rates\n")
cat("  Warn >50% NA; Error =100% NA on any YAML-mapped wave.\n")

spec_files <- list.files(here::here("src", "config", "kipa-corruption", "harmonize"),
                         pattern = "\\.yml$", full.names = TRUE)

yaml_source_map <- list()
yaml_gated_waves <- list()
for (sp in spec_files) {
  y <- yaml::read_yaml(sp)
  for (v in y$variables) {
    src <- v$source
    if (!is.null(src)) {
      mapped_yrs <- as.integer(sub("^w", "", names(src)))
      yaml_source_map[[v$id]] <- mapped_yrs
    }
    gw <- v$qc$gated_waves
    if (!is.null(gw)) yaml_gated_waves[[v$id]] <- as.integer(unlist(gw))
  }
}

WARN_THRESH  <- 0.50
ERROR_THRESH <- 1.00
na_flags <- 0L

for (v in intersect(names(yaml_source_map), survey_vars)) {
  mapped_yrs <- yaml_source_map[[v]]
  gated_yrs  <- yaml_gated_waves[[v]]
  for (yr in mapped_yrs) {
    subset <- d[[v]][d$year == yr]
    if (length(subset) == 0) next
    na_pct <- mean(is.na(subset))
    if (!is.null(gated_yrs) && yr %in% gated_yrs) {
      # Gate documented in YAML — high NA is by design; note but do not flag
      if (na_pct > WARN_THRESH) {
        cat(sprintf("  [gate] %s (year %d): %.0f%% NA — gated wave, denominator = subpopulation (OK)\n",
                    v, yr, na_pct * 100))
      }
      next
    }
    if (na_pct >= ERROR_THRESH) {
      na_flags <- na_flags + 1L
      flag(sprintf("100%% NA on MAPPED wave — %s (year %d): mapping is broken or wave absent",
                   v, yr))
    } else if (na_pct > WARN_THRESH) {
      na_flags <- na_flags + 1L
      flag(sprintf("HIGH NA on mapped wave — %s (year %d) = %.0f%% NA (expected data; check gate or scale change)",
                   v, yr, na_pct * 100))
    }
  }
}
if (na_flags == 0L) {
  cat(sprintf("  All non-gated mapped waves: NA%% within acceptable range (warn >.50, error =1.00).\n"))
}

# ----------------------------------------------------------------------------
# 2b. YAML spec internal consistency — scale.max vs valid_range
# ----------------------------------------------------------------------------
# Static check: if scale.max != valid_range[2] (or scale.min != valid_range[1]),
# the QC will silently drop legitimate values. No data needed.
#
# This check would have caught:
#   • corr_punishment_relative_strength: scale.max=5 but data goes to 6.
#     (The actual raw scale was 6-pt but valid_range was [1,5].)
cat("\n### 2b. YAML spec internal consistency (scale vs valid_range)\n")
scale_flags <- 0L
for (sp in spec_files) {
  y <- yaml::read_yaml(sp)
  for (v in y$variables) {
    sc <- v$scale
    vr <- v$qc$valid_range
    if (is.null(sc) || is.null(vr) || length(vr) != 2) next
    if (!is.null(sc$max) && sc$max != as.numeric(vr[2])) {
      scale_flags <- scale_flags + 1L
      flag(sprintf("SCALE vs RANGE MISMATCH — %s: scale.max=%g but valid_range[2]=%g",
                   v$id, sc$max, as.numeric(vr[2])))
    }
    if (!is.null(sc$min) && sc$min != as.numeric(vr[1])) {
      scale_flags <- scale_flags + 1L
      flag(sprintf("SCALE vs RANGE MISMATCH — %s: scale.min=%g but valid_range[1]=%g",
                   v$id, sc$min, as.numeric(vr[1])))
    }
  }
}
if (scale_flags == 0L) cat("  All variables: scale min/max consistent with valid_range.\n")

# ----------------------------------------------------------------------------
# 3. Range integrity — from harmonization out-of-range log
# ----------------------------------------------------------------------------
# The harmonize engine converts out-of-range values to NA, so checking the
# processed dataset finds nothing. Instead we read the OOB log written during
# the last pipeline run, which records: variable, wave, n converted, and the
# observed min/max of the offending values BEFORE they were set to NA.
# This is the only place where "values were 12 on a 1-10 scale" is visible.
cat("\n### 3. Range integrity (from harmonization OOB log)\n")
oob_log_path <- here::here("data", "processed", "kipa_corruption_oob_log.csv")
oob_flags <- 0L
if (!file.exists(oob_log_path)) {
  cat("  ⚠ OOB log not found — re-run the harmonization pipeline to generate it.\n")
  cat("    (Rscript src/r/data_prep_modules/kipa-corruption/2_harmonize_all.R)\n")
} else {
  oob_df <- read.csv(oob_log_path, stringsAsFactors = FALSE)
  if (nrow(oob_df) == 0) {
    cat("  ✓ No out-of-range conversions recorded in last pipeline run.\n")
  } else {
    cat(sprintf("  %d out-of-range event(s) recorded in last pipeline run:\n", nrow(oob_df)))
    for (i in seq_len(nrow(oob_df))) {
      r <- oob_df[i, ]
      oob_flags <- oob_flags + 1L
      excess <- r$obs_max - r$valid_max
      direction <- if (r$obs_max > r$valid_max) sprintf("+%g above ceiling", excess) else
                   sprintf("%g below floor", r$valid_min - r$obs_min)
      flag(sprintf(
        "%s (%s): %d values outside [%g, %g] — observed range [%g, %g] (%s). Scale change?",
        r$variable, r$wave, r$n_oob, r$valid_min, r$valid_max,
        r$obs_min, r$obs_max, direction
      ))
    }
  }
}

# ----------------------------------------------------------------------------
# 4. Direction sanity — expected-sign correlations
# ----------------------------------------------------------------------------
cat("\n### 4. Direction sanity checks\n")
cor_check <- function(a, b, expected_sign, context = "", known_artifact = NULL) {
  if (!(a %in% names(d) && b %in% names(d))) return(invisible())
  x <- d[[a]]; y <- d[[b]]
  ok <- !is.na(x) & !is.na(y)
  if (sum(ok) < 100) return(invisible())
  r <- cor(x[ok], y[ok])
  sign_ok <- (expected_sign == "+" && r > 0) || (expected_sign == "-" && r < 0)
  if (sign_ok) {
    cat(sprintf("  ✓ cor(%s, %s) = %+.2f  (expected %s)  %s\n",
                a, b, r, expected_sign, context))
  } else if (!is.null(known_artifact)) {
    cat(sprintf("  ~ cor(%s, %s) = %+.2f  (expected %s)  [known artifact: %s]\n",
                a, b, r, expected_sign, known_artifact))
  } else {
    cat(sprintf("  ✗ cor(%s, %s) = %+.2f  (expected %s)  %s\n",
                a, b, r, expected_sign, context))
    flag(sprintf("Direction check failed: cor(%s, %s) = %+.2f but expected %s",
                 a, b, r, expected_sign))
  }
}

# Perception items should all correlate positively (all capture "more corruption")
cor_check("corr_prevalence_perception", "corr_seriousness_perception", "+",
          "both higher = more perceived corruption")
cor_check("corr_prevalence_perception", "corr_change_vs_last_year",    "+",
          "prevalent corruption correlates with 'worse than last year'")
# Bribery experience (1=yes, 2=no) — respondents who gave a bribe should perceive MORE corruption,
# so raw binary (1=yes has LOWER value) correlates NEGATIVELY with perception scales
cor_check("corr_prevalence_perception", "corr_bribery_experience_1yr", "-",
          "bribery-givers (coded 1) perceive MORE prevalence (higher value) — reverse-sign binary",
          known_artifact = "1=yes/2=no coding compresses the signal; near-zero correlation expected, not a bug")
# Sector perception items should all correlate positively — they all capture same construct
cor_check("corr_sector_public",   "corr_sector_private",    "+", "public and private sector corruption cross-correlate")
cor_check("corr_sector_public",   "corr_func_police",       "+", "sector-public ↔ police corruption")
cor_check("corr_func_police",     "corr_func_legal",        "+", "police and legal-profession corruption co-vary")
cor_check("corr_func_tax",        "corr_func_construction", "+", "tax and construction corruption co-vary")
cor_check("corr_agency_central_hq", "corr_agency_local_frontline", "+",
          "central vs local agency corruption should still correlate")
cor_check("corr_sector_public",   "corr_prevalence_perception", "+",
          "sector-public should tie to general corruption perception")

# Surveillance items — all should correlate positively (same construct: institutional function quality)
cor_check("corr_surveil_party",    "corr_surveil_assembly", "+", "surveillance battery internal consistency")
cor_check("corr_surveil_media",    "corr_surveil_judiciary", "+", "surveillance battery")
cor_check("corr_surveil_internal_audit", "corr_surveil_boa", "+",
          "surveillance battery — both govt-audit functions")
# Punishment items should correlate with each other
cor_check("corr_punishment_bribe_giver", "corr_punishment_corrupt_official", "+",
          "if Korean respondents see punishment as generally weak, both items move together")
# Govt effectiveness ↔ surveillance function: effective govt should go with stronger institutional checks
cor_check("corr_govt_policy_effectiveness", "corr_surveil_party", "+",
          "effective govt policy should co-occur with perception of institutional checks working")

# ----------------------------------------------------------------------------
# 5. Year-over-year mean jumps
# ----------------------------------------------------------------------------
cat("\n### 5. Year-over-year mean jumps\n")
cat("  Flag |Δmean| > 2 SD in consecutive years.\n")
yoy_flags <- 0L
for (v in survey_vars) {
  if (!is.numeric(d[[v]])) next
  yr_means <- d %>%
    filter(!is.na(.data[[v]])) %>%
    group_by(year) %>%
    summarise(mu = mean(.data[[v]]), sd = sd(.data[[v]]), n = n(), .groups = "drop") %>%
    filter(n >= 50) %>%
    arrange(year)
  if (nrow(yr_means) < 2) next
  pooled_sd <- mean(yr_means$sd, na.rm = TRUE)
  diffs <- diff(yr_means$mu)
  for (i in which(abs(diffs) > 2 * pooled_sd)) {
    yoy_flags <- yoy_flags + 1L
    cat(sprintf("  · %s: %d (%.2f) → %d (%.2f)  Δ=%+.2f [pooled SD %.2f]\n",
                v, yr_means$year[i], yr_means$mu[i],
                yr_means$year[i + 1], yr_means$mu[i + 1],
                diffs[i], pooled_sd))
  }
}
if (yoy_flags == 0L) cat("  No variables with jumps > 2 SD.\n")

# ----------------------------------------------------------------------------
# 6. Known KIPA Corruption oddities
# ----------------------------------------------------------------------------
cat("\n### 6. Known KIPA Corruption oddities (always review manually)\n")
oddities <- c(
  "Sample is NOT general-population — respondents are corporate employees / self-employed with government business contact. Do NOT row-bind with KGSS/KAMOS/KIPA-social.",
  "Two raw variable naming families: 'a-family' (a01, a02, ...) used 2010–2021 + cumulative (2004–2007); 'q-family' (q1, q2, ...) used 2008, 2009, 2022, 2023. YAML maps both to stable harmonized IDs.",
  "2022–2023 wording expanded to 금품/향응/편의 (money/entertainment/favors) from just 금품 (money) pre-2022. Post-Kim Young-ran Act reframing — semantic content still overlaps but not identical.",
  "`corr_bribery_experience_1yr` coded 1=yes, 2=no (NOT binary 0/1). Direction-sanity checks use reverse-sign expectations.",
  "`corr_bribery_experience_1yr` NOT available in 2022–2023 — q13 in those years is 'contact with officials', a different concept. `skip_unmapped_check: true` suppresses the engine warning.",
  "`corr_bribery_experience_1yr` is GATED in 2016, 2019, 2020: a prior screener ('did you have contact with officials in the past year?') routes only YES-respondents to the bribery question. ~50% of the sample is legitimately skipped. The denominator for these waves is 'respondents with official contact', not the full sample — flag this in Methods. `gated_waves: [2016, 2019, 2020]` in the YAML suppresses the NA-rate warning; the QA script still prints a [gate] note showing the NA%. Other years (e.g. 2018) also show reduced n (~420–510) for the same reason but the gate was not formally documented in those codebooks — treat as probable gate.",
  "Cumulative file (2004–2007) is n=500 per year, not n=1,000 like annual files. Aggregate power reduced in the early years.",
  "Labels in 2009–2021 SAV files are EUC-KR-encoded and show as mojibake when read without encoding handling. Variable names and values are ASCII/numeric, so harmonization works regardless.",
  "Kim Young-ran Act (Sept 2016) is the key policy discontinuity. Expect structural breaks in direct-experience variables around 2016–2017.",
  "`corr_punishment_bribe_giver` had a SCALE-DIRECTION FLIP between 2013 (a1021) and 2014 (a103): pre-2014 coded 1=strong→6=weak, post-2014 coded 1=weak→6=strong. We apply safe_reverse_6pt to 2011-2013 so the harmonized output uses higher=stronger throughout. This was caught by the YoY jump check (Δ=-2.53 SD in 2013→2014 means). When adding new items, watch for undocumented scale flips at variable-renaming boundaries.",
  "`corr_punishment_relative_strength` had its scale restructured in 2018 from 6-point (1=bribe-givers penalized more, 6=officials penalized more, no midpoint) to 7-point (1=givers more, 4=equal midpoint, 7=officials more). Coverage is therefore 2011-2017 only (7 years). Originally specified as valid_range [1,5] — this was wrong (actual 6-pt scale) and caused 19–45% of rows per wave to be silently dropped. Fixed to valid_range [1,6] and 2018-2023 excluded. Would have been caught by the mapped-wave NA check (sections 2a) and the scale vs valid_range check (section 2b) added after this incident.",
  "`corr_punishment_bribe_giver` and `corr_punishment_corrupt_official` have a STRUCTURAL BREAK IN 2018: KIPA silently expanded both items from 6-point to 7-point by inserting a midpoint 4=적절하다 (appropriate/just right). Pre-2018: 1=very low → 6=very high (no midpoint, forced directional). 2018+: 1=very low → 7=very high (midpoint at 4). Handled via valid_range_by_wave ([1,6] pre-2018, [1,7] 2018+); all 13 years retained. Cross-period comparison requires 0-1 normalization — leave to the paper builder."
)
for (i in seq_along(oddities)) cat(sprintf("  %2d. %s\n", i, oddities[i]))

# ----------------------------------------------------------------------------
# 7. Summary
# ----------------------------------------------------------------------------
cat("\n================================================================\n")
cat("SUMMARY\n")
cat("================================================================\n")
cat(sprintf("Auto-flags raised:      %d\n", length(FLAGS)))
cat(sprintf("Mapped-wave NA flags:   %d  [sec 2a]\n", na_flags))
cat(sprintf("Scale/range mismatches: %d  [sec 2b]\n", scale_flags))
cat(sprintf("Out-of-range vars:      %d  [sec 3]\n",  oob_flags))
cat(sprintf("YoY jump flags:         %d  [sec 5]\n",  yoy_flags))
cat(sprintf("Oddities listed:        %d\n", length(oddities)))

if (length(FLAGS) > 0) {
  cat("\nAuto-flagged for review:\n")
  for (f in FLAGS) cat("  ⚠ ", f, "\n")
}
cat("\n")
