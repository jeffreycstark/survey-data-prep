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
# 3. Range integrity
# ----------------------------------------------------------------------------
cat("\n### 3. Range integrity\n")
spec_files <- list.files(here::here("src", "config", "kipa-corruption", "harmonize"),
                         pattern = "\\.yml$", full.names = TRUE)
range_map <- list()
for (sp in spec_files) {
  y <- yaml::read_yaml(sp)
  for (v in y$variables) {
    vr <- v$qc$valid_range
    if (!is.null(vr) && length(vr) == 2) range_map[[v$id]] <- as.numeric(vr)
  }
}
oob_flags <- 0L
for (v in intersect(names(range_map), survey_vars)) {
  vr <- range_map[[v]]
  x <- d[[v]]
  bad <- !is.na(x) & (x < vr[1] | x > vr[2])
  if (any(bad)) {
    oob_flags <- oob_flags + 1L
    flag(sprintf("%s: %d values outside [%g, %g]",
                 v, sum(bad), vr[1], vr[2]))
  }
}
if (oob_flags == 0L) cat(sprintf("  All %d variables within declared ranges.\n",
                                  length(range_map)))

# ----------------------------------------------------------------------------
# 4. Direction sanity — expected-sign correlations
# ----------------------------------------------------------------------------
cat("\n### 4. Direction sanity checks\n")
cor_check <- function(a, b, expected_sign, context = "") {
  if (!(a %in% names(d) && b %in% names(d))) return(invisible())
  x <- d[[a]]; y <- d[[b]]
  ok <- !is.na(x) & !is.na(y)
  if (sum(ok) < 100) return(invisible())
  r <- cor(x[ok], y[ok])
  sign_ok <- (expected_sign == "+" && r > 0) || (expected_sign == "-" && r < 0)
  sym <- if (sign_ok) "✓" else "✗"
  cat(sprintf("  %s cor(%s, %s) = %+.2f  (expected %s)  %s\n",
              sym, a, b, r, expected_sign, context))
  if (!sign_ok) {
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
          "bribery-givers (coded 1) perceive MORE prevalence (higher value) — reverse-sign binary")
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
  "2018–2020 show low n on `corr_bribery_experience_1yr` (~420–510 rather than 1,000) because a skip-filter restricts the question to respondents who recently contacted officials.",
  "Cumulative file (2004–2007) is n=500 per year, not n=1,000 like annual files. Aggregate power reduced in the early years.",
  "Labels in 2009–2021 SAV files are EUC-KR-encoded and show as mojibake when read without encoding handling. Variable names and values are ASCII/numeric, so harmonization works regardless.",
  "Kim Young-ran Act (Sept 2016) is the key policy discontinuity. Expect structural breaks in direct-experience variables around 2016–2017.",
  "`corr_punishment_bribe_giver` had a SCALE-DIRECTION FLIP between 2013 (a1021) and 2014 (a103): pre-2014 coded 1=strong→6=weak, post-2014 coded 1=weak→6=strong. We apply safe_reverse_6pt to 2011-2013 so the harmonized output uses higher=stronger throughout. This was caught by the YoY jump check (Δ=-2.53 SD in 2013→2014 means). When adding new items, watch for undocumented scale flips at variable-renaming boundaries."
)
for (i in seq_along(oddities)) cat(sprintf("  %2d. %s\n", i, oddities[i]))

# ----------------------------------------------------------------------------
# 7. Summary
# ----------------------------------------------------------------------------
cat("\n================================================================\n")
cat("SUMMARY\n")
cat("================================================================\n")
cat(sprintf("Auto-flags raised: %d\n", length(FLAGS)))
cat(sprintf("Out-of-range vars: %d\n", oob_flags))
cat(sprintf("YoY jump flags:    %d\n", yoy_flags))
cat(sprintf("Oddities listed:   %d\n", length(oddities)))

if (length(FLAGS) > 0) {
  cat("\nAuto-flagged for review:\n")
  for (f in FLAGS) cat("  ⚠ ", f, "\n")
}
cat("\n")
