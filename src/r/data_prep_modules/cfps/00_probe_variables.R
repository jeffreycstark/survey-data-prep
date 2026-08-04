# src/r/data_prep_modules/cfps/00_probe_variables.R
# CFPS discovery pass — run this FIRST, before writing any YAML spec.
#
# Consumer: paper-bank paper 26 ("Dragon Babies and Democratic Confidence"),
# a lunar-boundary RD on zodiac birth cohorts. That design needs three things
# this repo cannot yet confirm, and every one of them can kill the paper:
#
#   1. an EXACT birth date (year + month + day), not just birth year
#   2. which waves carry a political trust / efficacy battery (not guaranteed)
#   3. whether the reported birth date is SOLAR or LUNAR   <-- see below
#
# ⚠ THE CALENDAR-TYPE QUESTION IS THE BIG ONE
# Chinese respondents commonly report birthdays in the lunar calendar (农历),
# especially older cohorts — exactly the 1976 and 1988 cohorts this design
# leans on. The RD running variable is "days from Lunar New Year," so a
# lunar-reported date that is treated as solar does not produce noise, it
# produces a systematically wrong running variable, and it is wrong in a way
# that CORRELATES WITH THE TREATMENT (dates near the new year are precisely
# where the two calendars diverge most in the reporting population).
# If CFPS carries a 阳历/农历 flag, find it. If it does not, that is a
# first-order threat to identification and the paper needs to know before
# drafting, not after.
#
# This script asserts nothing about CFPS variable names — it SEARCHES, dumps
# what it finds, and leaves a resolved map for a human to confirm. Nothing here
# should be promoted into YAML until a person has read the output.
#
# Run:
#   Rscript src/r/data_prep_modules/cfps/00_probe_variables.R 2>&1 \
#     | tee outputs/cfps/probe_console.txt

suppressMessages({
  library(haven); library(dplyr); library(here); library(purrr); library(tidyr)
})

source(here::here("src", "r", "data_prep_modules", "cfps", "0_load_waves.R"))

out_dir <- here("outputs", "cfps")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ==============================================================================
# METADATA-ONLY SCAN (cheap — no row data read)
# ==============================================================================

wave_files <- map(CFPS_WAVES, find_cfps_wave_file) |> set_names(sprintf("y%d", CFPS_WAVES))
wave_files <- compact(wave_files)

if (length(wave_files) == 0) {
  stop("No CFPS files found in data/cfps/raw/. Nothing to probe.\n",
       "  CFPS requires a data-use application: https://cfpsdata.pku.edu.cn\n",
       "  See docs/surveys/cfps.md.")
}

cat("\nProbing waves:", paste(names(wave_files), collapse = ", "), "\n")

meta <- map(wave_files, ~ read_dta(.x, n_max = 0))

var_tab <- imap_dfr(meta, function(d, wv) {
  tibble(
    wave  = wv,
    var   = names(d),
    label = map_chr(d, ~ { l <- attr(.x, "label"); if (is.null(l)) "" else as.character(l) })
  )
})

cat(sprintf("Metadata loaded: %d wave(s), %s total variable-wave rows\n",
            length(meta), format(nrow(var_tab), big.mark = ",")))

# value labels for one var in one wave
vlabs <- function(wv, v) {
  d <- meta[[wv]]
  if (is.null(d) || !v %in% names(d)) return("(absent)")
  l <- attr(d[[v]], "labels")
  if (is.null(l)) "(none)" else paste(sprintf("%s=%s", l, names(l)), collapse = " | ")
}

#' Search variable names AND labels for a regex, across all waves.
probe <- function(pattern, title, max_show = 40) {
  cat("\n", strrep("=", 78), "\n", sep = "")
  cat("PROBE: ", title, "\n", sep = "")
  cat("  /", pattern, "/\n", sep = "")
  cat(strrep("=", 78), "\n")

  hits <- var_tab |>
    filter(grepl(pattern, var, ignore.case = TRUE) |
           grepl(pattern, label, ignore.case = TRUE))

  if (nrow(hits) == 0) {
    cat("  ✖ NO MATCHES in any wave.\n")
    return(invisible(hits))
  }

  # collapse to var × which-waves, so a stable variable prints once
  summary_tab <- hits |>
    group_by(var, label) |>
    summarise(waves = paste(sort(unique(wave)), collapse = ","), .groups = "drop") |>
    arrange(var)

  cat(sprintf("  %d distinct variable name(s) matched\n\n", nrow(summary_tab)))
  print(as.data.frame(head(summary_tab, max_show)), right = FALSE)
  if (nrow(summary_tab) > max_show) {
    cat(sprintf("  ... %d more suppressed\n", nrow(summary_tab) - max_show))
  }
  invisible(hits)
}

# ==============================================================================
# PART A — TARGETED PROBES
# ==============================================================================
# Patterns cover English AND Chinese label text: CFPS ships both, and which one
# is populated depends on the release. Do not narrow these to English only.

birth_hits <- probe(
  "birth|birthday|date of birth|出生|生日|诞",
  "Birth date — year / month / day (design item B1)"
)

calendar_hits <- probe(
  "lunar|solar|calendar|农历|阴历|阳历|公历|旧历|新历",
  "⚠ CALENDAR TYPE — is the birth date lunar or solar? (identification-critical)"
)

zodiac_hits <- probe(
  "zodiac|animal sign|生肖|属相|十二生肖",
  "Chinese zodiac field (CFPS-computed; cross-check against our own assignment)"
)

trust_hits <- probe(
  "trust|confiden|信任|信赖",
  "Political / institutional trust battery"
)

efficacy_hits <- probe(
  "efficacy|influence|have a say|political participation|政治|效能|影响力|官员",
  "Political efficacy / participation"
)

govt_hits <- probe(
  "government|official|cadre|party|政府|干部|官员|党",
  "Government evaluation items (adjacent outcomes / controls)",
  max_show = 25
)

ses_hits <- probe(
  "educ|income|earning|wage|schooling|教育|收入|工资|学历",
  "Adult SES — education and income (H1-vs-H2 channel split)",
  max_show = 25
)

demog_hits <- probe(
  "hukou|urban|rural|ethnic|nationality|province|户口|城乡|民族|省",
  "Boundary-balance covariates — hukou, urbanicity, ethnicity, region",
  max_show = 25
)

parent_hits <- probe(
  "father|mother|parent|父|母|家长",
  "Parental characteristics (balance tests + the H1 investment channel)",
  max_show = 25
)

# ==============================================================================
# PART B — MISSING-CODE UNIVERSE
# ==============================================================================
# The design brief reports that CFPS marks an unknown birth month/day with a
# CTRL-D style code when only age is known. Resolve the ACTUAL code set here
# rather than assuming — the harmonized file must keep "date not asked / not
# known" distinguishable from ordinary refusal, because the RD sample is
# defined by exactly that selection.

cat("\n", strrep("=", 78), "\n", sep = "")
cat("MISSING-CODE UNIVERSE (scanned from value-label text, all waves)\n")
cat(strrep("=", 78), "\n")

neg_codes <- list()
for (wv in names(meta)) {
  d <- meta[[wv]]
  for (v in names(d)) {
    l <- attr(d[[v]], "labels")
    if (is.null(l)) next
    idx <- grepl("don'?t know|refus|not applicable|missing|inapplic|不知道|拒绝|不适用|缺失",
                 names(l), ignore.case = TRUE)
    if (any(idx)) {
      neg_codes[[length(neg_codes) + 1]] <- tibble(
        wave = wv, code = as.numeric(l[idx]), label = names(l)[idx]
      )
    }
  }
}

if (length(neg_codes) > 0) {
  codes_tab <- bind_rows(neg_codes) |>
    count(code, label, sort = TRUE)
  print(as.data.frame(head(codes_tab, 30)), right = FALSE)
  write.csv(codes_tab, file.path(out_dir, "missing_code_universe.csv"), row.names = FALSE)
  cat(sprintf("\nWrote %s\n", file.path(out_dir, "missing_code_universe.csv")))
  cat("\n→ Put the resolved set into every CFPS spec's missing_conventions.treat_as_na.\n")
  cat("→ Keep the birth-date 'not asked' code SEPARATE from refusal if they differ:\n")
  cat("   collapsing them makes the RD sample selection unmeasurable.\n")
} else {
  cat("  No missing-code labels matched. Inspect a wave by hand before writing YAML.\n")
}

# ==============================================================================
# PART C — REAL-DATA CHECKS
# ==============================================================================
# Everything above is metadata. These require actually reading rows, and they
# are the numbers that decide whether the paper is feasible.
#
# The variable names below are NOT known yet — fill them in from Part A's output
# and re-run. Left deliberately empty rather than guessed: a wrong guess here
# produces a confident, wrong feasibility number.

BIRTH_YEAR_VAR  <- NULL   # TODO from Part A, e.g. c(y2010 = "...", y2012 = "...")
BIRTH_MONTH_VAR <- NULL   # TODO
BIRTH_DAY_VAR   <- NULL   # TODO
CALENDAR_VAR    <- NULL   # TODO — the 阳历/农历 flag, if one exists

if (is.null(BIRTH_YEAR_VAR)) {
  cat("\n", strrep("=", 78), "\n", sep = "")
  cat("PART C SKIPPED — birth-date variable names not yet resolved.\n")
  cat(strrep("=", 78), "\n")
  cat("Read Part A's output, set BIRTH_YEAR_VAR / BIRTH_MONTH_VAR / BIRTH_DAY_VAR\n")
  cat("(and CALENDAR_VAR if a lunar/solar flag exists) at the top of Part C, re-run.\n")
  cat("\nPart C then reports the three go/no-go numbers:\n")
  cat("  1. exact-birth-date completeness by wave\n")
  cat("  2. whether date-complete respondents differ from date-missing ones\n")
  cat("  3. N inside +/-30 / 60 / 90 days of each dragon lunar boundary\n")
} else {

  # --- C1. Exact birth-date completeness by wave -----------------------------
  cat("\n", strrep("=", 78), "\n", sep = "")
  cat("C1. EXACT BIRTH-DATE COMPLETENESS (sets usable N)\n")
  cat(strrep("=", 78), "\n")

  completeness <- imap_dfr(wave_files, function(f, wv) {
    cols <- c(BIRTH_YEAR_VAR[[wv]], BIRTH_MONTH_VAR[[wv]], BIRTH_DAY_VAR[[wv]])
    cols <- cols[!is.na(cols)]
    if (length(cols) < 3) return(tibble(wave = wv, n = NA_integer_, exact = NA_integer_))
    d <- read_dta(f, col_select = all_of(cols))
    names(d) <- c("by", "bm", "bd")
    d <- d |> mutate(across(everything(), ~ as.numeric(zap_labels(.x))))
    # negative sentinel codes are missing, not dates
    d <- d |> mutate(across(everything(), ~ if_else(.x < 0, NA_real_, .x)))
    tibble(
      wave      = wv,
      n         = nrow(d),
      has_year  = sum(!is.na(d$by)),
      has_month = sum(!is.na(d$bm)),
      has_day   = sum(!is.na(d$bd)),
      exact     = sum(!is.na(d$by) & !is.na(d$bm) & !is.na(d$bd)),
      pct_exact = round(100 * exact / nrow(d), 1)
    )
  })
  print(as.data.frame(completeness), right = FALSE)
  write.csv(completeness, file.path(out_dir, "birthdate_completeness.csv"), row.names = FALSE)

  # --- C2. Boundary-window N -------------------------------------------------
  # Dragon-year Lunar New Year boundaries. Verified 2026-08-04 against two
  # independent sources; canonical copy lives in the consuming paper at
  # paper-bank-26-dragon/papers/26-dragon/data/lunar_boundaries.csv.
  # Duplicated here so this repo's probe has no cross-repo dependency —
  # if one is corrected, correct both.
  DRAGON_BOUNDARIES <- as.Date(c("1976-01-31", "1988-02-17",
                                 "2000-02-05", "2012-01-23"))

  cat("\n", strrep("=", 78), "\n", sep = "")
  cat("C2. BOUNDARY-WINDOW N — THE GO/NO-GO NUMBER\n")
  cat(strrep("=", 78), "\n")
  cat("NB: the 2012 cohort cannot carry political attitudes in any released\n")
  cat("    wave (age ~8 in 2020). Expect it to contribute 0 usable respondents.\n\n")

  # TODO: once birth_date is constructed, compute for each boundary and each
  # bandwidth in c(30, 60, 90):
  #   n_left  = births in [boundary - bw, boundary)
  #   n_right = births in [boundary, boundary + bw)
  # restricted to respondents who ALSO have a non-missing trust/efficacy answer.
  # Report per-cohort and pooled. If pooled N at +/-60 is small, say so loudly.
  cat("  TODO: implement once birth-date construction is confirmed (see C1).\n")
}

# ==============================================================================
# PART D — RESOLVED VARIABLE MAP (fill in after reading Part A)
# ==============================================================================
# Mirrors outputs/klosa/variable_map.csv. Written empty on the first run so the
# file exists with the right shape; populate it from Part A's output.

variable_map <- tibble(
  concept    = character(),
  target_id  = character(),
  y2010 = character(), y2012 = character(), y2014 = character(),
  y2016 = character(), y2018 = character(), y2020 = character(),
  coding     = character(),
  notes      = character()
)

write.csv(variable_map, file.path(out_dir, "variable_map.csv"), row.names = FALSE)

cat("\n", strrep("=", 78), "\n", sep = "")
cat("PROBE COMPLETE\n")
cat(strrep("=", 78), "\n")
cat(sprintf("Wrote %s (EMPTY — populate from Part A).\n",
            file.path(out_dir, "variable_map.csv")))
cat("\nNext: resolve names → fill Part C → fill the map → write YAML in\n")
cat("      src/config/cfps/harmonize/ → run 2_harmonize_all.R\n\n")
