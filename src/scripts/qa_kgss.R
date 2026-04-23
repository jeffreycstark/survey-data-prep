# ============================================================================
# KGSS harmonization QA
# ----------------------------------------------------------------------------
# Runs a battery of checks on data/processed/kgss_harmonized.rds and flags
# oddities that need manual review. Not a pass/fail test suite — a set of
# tripwires to run after adding variables or extending waves.
#
# Usage:
#   Rscript src/scripts/qa_kgss.R
#
# The script prints sections to stdout and collects FLAGS into a final summary.
# Each flag starts with `⚠` and is preceded by the check that produced it.
# ============================================================================

suppressMessages({
  library(here)
  library(dplyr)
  library(tidyr)
})

d <- readRDS(here::here("data", "processed", "kgss_harmonized.rds"))
FLAGS <- character(0)
flag <- function(msg) {
  FLAGS[[length(FLAGS) + 1L]] <<- msg
  cat("  ⚠ ", msg, "\n", sep = "")
}

admin_cols  <- c("wave", "year", "country", "weight", "row_id",
                 "resp_id", "yr_resp_id", "questionnaire_form")
survey_vars <- setdiff(names(d), admin_cols)

cat("================================================================\n")
cat("KGSS HARMONIZATION QA —", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("================================================================\n\n")

# ----------------------------------------------------------------------------
# 1. Dataset overview
# ----------------------------------------------------------------------------
cat("### 1. Dataset overview\n")
cat(sprintf("Rows:            %s\n",  format(nrow(d), big.mark = ",")))
cat(sprintf("Cols:            %d\n",  ncol(d)))
cat(sprintf("Survey vars:     %d\n",  length(survey_vars)))
cat(sprintf("Waves (years):   %s\n",  paste(sort(unique(d$year)), collapse = ", ")))

expected_years <- c(2003:2014, 2016, 2018, 2021, 2023, 2025)
missing_years  <- setdiff(expected_years, unique(d$year))
if (length(missing_years)) flag(sprintf("Expected years missing from data: %s",
                                         paste(missing_years, collapse = ", ")))

# ----------------------------------------------------------------------------
# 2. Wave coverage — variables with NO data in any wave they claim to cover
# ----------------------------------------------------------------------------
cat("\n### 2. Wave coverage\n")
cov_mat <- sapply(sort(unique(d$year)), function(y) {
  sapply(survey_vars, function(v) sum(!is.na(d[[v]][d$year == y])))
})
colnames(cov_mat) <- sort(unique(d$year))

# Flag any survey var that is empty in ALL waves (broken harmonization)
empty_vars <- rownames(cov_mat)[rowSums(cov_mat) == 0]
if (length(empty_vars)) {
  flag(sprintf("Variables with ZERO data across all waves: %s",
               paste(empty_vars, collapse = ", ")))
}

# Flag variables with suspiciously low coverage in a wave where they appear
low_cov_rows <- c()
for (v in survey_vars) {
  nonzero_waves <- as.integer(colnames(cov_mat))[cov_mat[v, ] > 0]
  for (y in nonzero_waves) {
    wave_n <- sum(d$year == y)
    ratio <- cov_mat[v, as.character(y)] / wave_n
    # Skip nominal vars (party_id, voted_*) where partial coverage is expected
    if (grepl("^party_|^voted_|_pref$|^admin_", v)) next
    if (ratio < 0.40) {
      low_cov_rows <- c(low_cov_rows,
                        sprintf("%s (%d): n=%d / %d (%.0f%%)",
                                v, y, cov_mat[v, as.character(y)],
                                wave_n, ratio * 100))
    }
  }
}
if (length(low_cov_rows)) {
  cat("  Variable-wave cells with <40% coverage (may warrant review):\n")
  for (r in head(low_cov_rows, 30)) cat("    ·", r, "\n")
  if (length(low_cov_rows) > 30) cat(sprintf("    (%d more — full list via running interactively)\n",
                                             length(low_cov_rows) - 30))
}

# ----------------------------------------------------------------------------
# 3. Range integrity — values outside declared valid_range
# ----------------------------------------------------------------------------
cat("\n### 3. Range integrity\n")
# Load YAML specs to read valid_range for each var
spec_files <- list.files(here::here("src", "config", "kgss", "harmonize"),
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
    flag(sprintf("%s: %d values outside declared range [%g, %g]",
                 v, sum(bad), vr[1], vr[2]))
  }
}
if (oob_flags == 0L) cat("  All", length(range_map),
                         "variables with valid_range checked — no out-of-range values.\n")

# ----------------------------------------------------------------------------
# 4. Direction sanity — key correlations that should have an expected sign
# ----------------------------------------------------------------------------
cat("\n### 4. Direction sanity checks (expected-sign correlations)\n")
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

# Trust battery — NOTE: trust_generalized is scaled OPPOSITE to the other two
# (raw CANTRUST 1=high trust → 4=low trust, kept as identity).
# Expectations reflect current data reality, not wishful consistency.
cor_check("trust_fair", "trust_generalized", "-", "trust_generalized direction inverted — see oddity #15")
cor_check("trust_fair", "trust_reliable",    "+")
cor_check("trust_generalized", "trust_reliable", "-", "trust_generalized direction inverted")

# Institutional confidence — sample pairs should correlate positively
cor_check("conf_govt_national", "conf_legislature", "+")
cor_check("conf_press",         "conf_television",  "+")
cor_check("conf_judiciary",     "conf_prosecutors", "+")

# Democracy assessment vs pride in democracy
cor_check("dem_now", "pride_democracy", "+", "more perceived democracy ↔ more pride in it")

# National-pride battery internal consistency
cor_check("natid_kr_better_than_most", "natid_world_like_kr", "+")
cor_check("natid_korean_over_other",   "natid_kr_better_than_most", "+")
# Shame is inversely valenced — should correlate NEGATIVELY with pride items
cor_check("natid_shame", "natid_kr_better_than_most", "-", "shame item is inversely valenced")
cor_check("natid_shame", "pride_democracy",           "-")

# Immigration attitudes — pro/anti should oppose each other
cor_check("imm_help_econ",        "imm_take_jobs",     "-", "pro vs anti-immigrant economic")
cor_check("imm_cultural_contrib", "imm_crime",         "-", "pro vs anti-immigrant cultural")
cor_check("imm_help_econ",        "imm_limit_number", "-", "wanting more immigrants ↔ pro-econ view")
cor_check("imm_crime",            "imm_limit_number", "+",
          "both capture restrictive sentiment (imm_limit_number is identity-coded)")

# Government-spending signs (should hang together: more-spending people want more everywhere)
cor_check("gov_spend_health",    "gov_spend_education",    "+")
cor_check("gov_spend_pension",   "gov_spend_unemployment", "+")

# Political behavior / economic satisfaction
cor_check("pol_satisfaction",      "econ_hh_satisfaction", "+",
          "political and economic satisfaction usually co-move")

# Corruption — perception items all go the same direction (high=corrupt)
cor_check("corr_politicians",       "corr_officials",        "+",
          "both perception-of-corruption items on same scale")
cor_check("corr_cant_succeed_without", "corr_bribe_success", "+",
          "both capture cynical view of corruption-success link")
# Officials corruption perception should correlate with admin_corruption (earlier module)
cor_check("corr_officials",         "admin_corruption",      "+",
          "two different perception-of-official-corruption items")
# Govt performance items reversed — should correlate with each other positively
cor_check("corr_anticorrupt_policy", "corr_tax_fairness_policy", "+",
          "both evaluate govt performance (reversed — high=good)")

# ----------------------------------------------------------------------------
# 5. Missingness patterns — variables with oddly high NA in specific years
# ----------------------------------------------------------------------------
cat("\n### 5. Missingness patterns\n")
# For each variable, compute the max missingness gap across years where it
# should have data (based on having ANY data in that year)
odd_miss <- c()
for (v in survey_vars) {
  rates <- sapply(sort(unique(d$year)), function(y) {
    sub <- d[[v]][d$year == y]
    if (length(sub) == 0) return(NA_real_)
    mean(is.na(sub))
  })
  # Find years with partial data (0 < rate < 1) — these are real fieldings
  active <- !is.na(rates) & rates < 1 & rates > 0
  if (sum(active) >= 2) {
    spread <- max(rates[active]) - min(rates[active])
    if (spread > 0.30) {
      odd_miss <- c(odd_miss, sprintf("%s: missingness ranges %.0f%% to %.0f%% across active years",
                                       v, 100*min(rates[active]), 100*max(rates[active])))
    }
  }
}
if (length(odd_miss) == 0) cat("  No variables with >30pp spread in missingness across active years.\n")
for (m in head(odd_miss, 15)) cat("  ·", m, "\n")
if (length(odd_miss) > 15) cat(sprintf("  (%d more)\n", length(odd_miss) - 15))

# ----------------------------------------------------------------------------
# 6. Year-over-year mean jumps — possible recoding errors or real events
# ----------------------------------------------------------------------------
cat("\n### 6. Year-over-year mean jumps\n")
cat("  Flagging |change| > 2 SD in consecutive active years (review as possible recoding slip).\n\n")
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
    cat(sprintf("  · %s: %d (mean %.2f) → %d (mean %.2f)  Δ = %+.2f  [pooled SD %.2f]\n",
                v, yr_means$year[i], yr_means$mu[i],
                yr_means$year[i + 1], yr_means$mu[i + 1],
                diffs[i], pooled_sd))
  }
}
if (yoy_flags == 0) cat("  No variables with jumps > 2 SD.\n")

# ----------------------------------------------------------------------------
# 7. Known KGSS oddities — always reviewed manually, not auto-flagged
# ----------------------------------------------------------------------------
cat("\n### 7. Known KGSS oddities (always review manually)\n")
oddities <- c(
  "`conf_*` vars are 1–3 scale (not 1–4 like ABS/WVS/LBS trust) — rescale before cross-survey comparison",
  "`trust_reliable` is 0–10 continuous; `trust_fair` is 1–3; `trust_generalized` is 1–4",
  "`party_id` and `party_pref` are NOMINAL year-specific raw codes — NOT comparable across waves without manual camp mapping",
  "`voted_presidential/general/local` coded 1=voted, 2=did NOT vote (not binary 0/1)",
  "`natid_shame` is INVERSELY valenced vs other pride items — high = more shame",
  "`imm_limit_number` uses identity (not reversal) — high = want FEWER immigrants; scale direction differs from other imm_* items",
  "`admin_corruption` is NOT reversed — high = more perceived corruption (intuitive direction)",
  "Citizenship virtues/rights are 1–7 scale, but efficacy items are 1–5 and democracy assessment is 0–10 — do not conflate",
  "`pol_govt_eval` (CURGOV) dropped after 2023 — NA for w2025",
  "`subjective_class_6pt` is sparse: only 2003–2005 (CLASS) and 2006–2008 (CLASS06) — use `subjective_rank_10pt` for broader coverage",
  "`questionnaire_form` (A/B split-ballot) only populated from 2016 onward",
  "`weight` (FINALWT) is mean=1 per wave but range varies across waves (0.29–5.29 in 2025, tighter in earlier waves)",
  "KGSS has NO interview date variable — year is the only temporal identifier",
  "The raw SPSS file `kor_data_CUM0074.sav` uses Korean value labels; variable names are stable but don't rely on label matching",
  "⚠ DIRECTION INCONSISTENCY in trust battery: `trust_generalized` (CANTRUST) is identity-coded so higher=LESS trust, while `trust_fair` and `trust_reliable` go the other way (higher=more trust). CLAUDE.md currently claims all three are 'higher=more trust' — that's wrong for trust_generalized. Decide: (a) reverse trust_generalized to match, or (b) update docs to reflect current behavior. Until resolved, be careful in any analysis combining the three."
)
for (i in seq_along(oddities)) cat(sprintf("  %2d. %s\n", i, oddities[i]))

# ----------------------------------------------------------------------------
# 8. Summary
# ----------------------------------------------------------------------------
cat("\n================================================================\n")
cat("SUMMARY\n")
cat("================================================================\n")
cat(sprintf("Auto-flags raised:  %d\n", length(FLAGS)))
cat(sprintf("Out-of-range vars:  %d\n", oob_flags))
cat(sprintf("YoY jump flags:     %d\n", yoy_flags))
cat(sprintf("Oddities listed:    %d (always-review)\n", length(oddities)))

if (length(FLAGS) > 0) {
  cat("\nAuto-flagged for review:\n")
  for (f in FLAGS) cat("  ⚠ ", f, "\n")
}
cat("\n")
