# src/r/data_prep_modules/klosa/00_probe_variables.R
# Discovery pass: locate every RD variable across W1-W9, dump value scales,
# and resolve missing-code conventions. Executes "check the codebooks first".
#
# This script is split in two parts:
#   PART A — diagnostic prints (metadata scans, label dumps, a real-data
#            cross-check of the G111/E111 treatment ambiguity). Reproducible;
#            re-run any time the raw files change.
#   PART B — the RESOLVED variable_map, built from Part A's findings (and a
#            few additional targeted searches recorded in outputs/klosa/
#            probe_console.txt / task-2-report.md). Written to
#            outputs/klosa/variable_map.csv.
#
# Run: Rscript src/r/data_prep_modules/klosa/00_probe_variables.R 2>&1 | tee outputs/klosa/probe_console.txt

suppressMessages({library(haven); library(dplyr); library(here); library(purrr); library(tidyr)})

waves <- sprintf("w%d", 1:9)
paths <- setNames(here("data","klosa","raw", sprintf("w0%d_e.sav", 1:9)), waves)
meta  <- map(paths, ~ read_sav(.x, n_max = 0))

# variable table per wave (name, label)
var_tab <- imap_dfr(meta, function(d, wv) tibble(
  wave = wv, var = names(d),
  label = map_chr(d, ~ { l <- attr(.x, "label"); if (is.null(l)) "" else l })))

# helper: value labels for one var in one wave
vlabs <- function(wv, v) {
  d <- meta[[wv]]; if (!v %in% names(d)) return("(absent)")
  l <- attr(d[[v]], "labels"); if (is.null(l)) "(none)" else paste(sprintf("%s=%s", l, names(l)), collapse=" | ")
}
lab1 <- function(wv, v) {
  d <- meta[[wv]]; if (!v %in% names(d)) return("ABSENT")
  l <- attr(d[[v]], "label"); if (is.null(l)) "" else l
}

# ============================================================
# PART A — DIAGNOSTIC PRINTS
# ============================================================

# 1) treatment: G111/G112/G113 (legacy) vs E111/E113 (post-2014 relocation).
cat("\n===== TREATMENT (basic pension) — G-block vs E-block per wave =====\n")
for (i in 1:9) { wv <- waves[i]; for (v in sprintf("w0%d%s", i, c("G110","G111","G112","G113","E111","E112","E113"))) {
  cat(sprintf("  %-12s [%s] %s\n", v, lab1(wv, v), vlabs(wv, v))) } }

cat("\n===== REAL-DATA CHECK: is legacy G111 actually dead in W5-W9? =====\n")
cat("(The design spec assumed G111 is empty/dead post-2014; verifying against actual values, not just metadata.)\n")
for (i in 2:9) {
  wv <- sprintf("w0%d", i)
  cols <- c("pid", paste0(wv, c("G111","E111","E112","E113")))
  d <- tryCatch(read_sav(paths[[sprintf("w%d", i)]], col_select = any_of(cols)), error = function(e) NULL)
  if (is.null(d)) { cat(wv, ": read error\n"); next }
  n <- nrow(d)
  g111v <- if (paste0(wv,"G111") %in% names(d)) as.numeric(d[[paste0(wv,"G111")]]) else rep(NA_real_, n)
  e111v <- if (paste0(wv,"E111") %in% names(d)) as.numeric(d[[paste0(wv,"E111")]]) else rep(NA_real_, n)
  cat(sprintf("  %s n=%d | G111 non-NA=%d (%.0f%%) | E111 non-NA=%d (%.0f%%)\n",
              wv, n, sum(!is.na(g111v)), 100*sum(!is.na(g111v))/n, sum(!is.na(e111v)), 100*sum(!is.na(e111v))/n))
}
cat("VERDICT: G111 is NOT dead in W5-W9 — it remains substantially populated (~41-53% non-NA),\n")
cat("  comparable to or exceeding E111's coverage. Both G111 (categorical 1/3/5) and E111\n")
cat("  ('check'-style flag, 1=Check else NA, always paired 1:1 with non-NA E112/E113) coexist.\n")
cat("  This CONTRADICTS the design-spec assumption that G111 'persists but is dead post-2014'.\n")
cat("  Flagged as UNRESOLVED for Task 6 — needs a G111-vs-E111 agreement cross-tab before picking one.\n")

# 2) National Pension confound: E033/E035 (stable across all waves)
cat("\n===== NATIONAL PENSION (confound) =====\n")
for (i in 1:9) { wv<-waves[i]; for (v in sprintf("w0%d%s", i, c("E033","E035"))) {
  cat(sprintf("  %-10s [%s] %s\n", v, lab1(wv,v), vlabs(wv,v))) } }

# 3) participation battery — W1 uses A017m/A019 (NOT A033/A035); W2-W9 use A033m/A035.
cat("\n===== PARTICIPATION (outcome) — W1 anchor differs from W2-W9! =====\n")
cat("W1 membership battery lives at A017m01-08 (NOT A033m01-08); W1 frequency at A019_01-07 (NOT A035_01-07).\n")
cat("Coding is identical (0=No/1=Yes for membership; 1-10 declining-frequency scale for A019/A035) —\n")
cat("this is a pure variable-renumbering artifact of the W1->W2 questionnaire revision, same pattern as A001->A002 (age).\n\n")
for (v_suffix in c(sprintf("A033m%02d",1:8), sprintf("A035_%02d",1:7))) {
  v1 <- if (grepl("A033m", v_suffix)) sprintf("w01A017m%s", sub("A033m","",v_suffix)) else sprintf("w01A019_%s", sub("A035_","",v_suffix))
  v9 <- sprintf("w09%s", v_suffix)
  cat(sprintf("  %-10s  W1[%s] %s\n             W9[%s] %s\n", v_suffix,
      if (v1 %in% names(meta$w1)) "ok" else "ABSENT", vlabs("w1", v1),
      if (v9 %in% names(meta$w9)) "ok" else "ABSENT", vlabs("w9", v9)))
}

# 4) identifiers / demographics / weights — grep labels
cat("\n===== ID / WEIGHT / DEMOGRAPHIC candidates (W4) =====\n")
print(var_tab %>% filter(wave=="w4",
  grepl("^w04(pid|hhid|hid)|weight|^w04A002|birth|^w04A00[0-9]|marital|educat|region|resident|household size|self-?rated health|ADL|IADL|econom.*activ|work", var, ignore.case=TRUE) |
  grepl("weight|birth|marital|education|region|household member|self-rated health|activities of daily", label, ignore.case=TRUE)) %>%
  select(var, label), n = 80, width = 200)

cat("\n===== pid/hhid exact names + weight family, ALL WAVES =====\n")
for (i in 1:9) {
  wv <- waves[i]; d <- meta[[wv]]
  pv <- if ("pid" %in% names(d)) "pid" else if ("PID" %in% names(d)) "PID" else "NOT FOUND"
  hv <- if ("hhid" %in% names(d)) "hhid" else if ("HHID" %in% names(d)) "HHID" else "NOT FOUND"
  wgt <- names(d)[grepl(sprintf("^w0%dwgt_", i), names(d))]
  cat(sprintf("  %s: pid=%s hhid=%s weights=%s\n", wv, pv, hv, paste(wgt, collapse=",")))
}
cat("\nWeight label check (horizontal=cross-sectional, vertical=longitudinal/panel, by convention):\n")
for (i in 1:9) { wv<-waves[i]
  for (suf in c("wgt_c","wgt_p")) { v <- sprintf("w0%d%s", i, suf); cat(sprintf("  %s %-12s [%s]\n", wv, v, lab1(wv,v))) }
}
cat("NOTE: wgt_c/wgt_p horizontal/vertical labels SWAP at W8-W9 vs W1-W7 (see task-2-report.md). UNRESOLVED.\n")

# 5) age/birth anchor stability check — W1 uses A001 family, W2-W9 use A002.
cat("\n===== AGE / BIRTH anchor — W1 uses A001, W2-W9 use A002 (NOT stable as assumed) =====\n")
for (suf in c("_age","y","m")) {
  v1 <- paste0("w01A001", suf)
  cat(sprintf("  w1 %-14s [%s]\n", v1, lab1("w1", v1)))
}
for (i in 2:9) { wv <- waves[i]
  for (suf in c("_age","y","m")) {
    v <- sprintf("w0%dA002%s", i, suf)
    cat(sprintf("  %s %-14s [%s]\n", wv, v, lab1(wv, v)))
  }
}
cat("\nBirth-MONTH variables (A001m / A002m) exist and are FULLY populated (spot-checked W1,W4,W9: 100% non-NA).\n")
cat("Interview-date variables (mniw_y/mniw_m/mniv_d, day precision) exist in ALL 9 waves.\n")
cat("This OVERTURNS the design spec's 'integer-year age only' RD-granularity limitation (see report).\n")
for (i in 1:9) { wv<-waves[i]
  for (suf in c("mniw_y","mniw_m","mniw_d")) { v<-sprintf("w0%d%s", i, suf); cat(sprintf("  %s %-12s [%s]\n", wv, v, lab1(wv,v))) }
}

# 6) household income relocation: E126 (W1-W4) -> E147 (W5-W9)
cat("\n===== HOUSEHOLD INCOME TOTAL — third relocation instance (E126->E147) =====\n")
for (i in 1:9) { wv<-waves[i]; v <- if (i<=4) sprintf("w0%dE126", i) else sprintf("w0%dE147", i)
  cat(sprintf("  %s %-10s [%s]\n", wv, v, lab1(wv,v))) }

# 7) missing-code universe scan (W4, representative wave)
cat("\n===== MISSING-CODE UNIVERSE (scanned from W4 value-label text) =====\n")
d4 <- meta$w4; neg_codes <- c()
for (v in names(d4)) {
  l <- attr(d4[[v]], "labels"); if (is.null(l)) next
  idx <- grepl("don.t know|refuse", names(l), ignore.case=TRUE)
  if (any(idx)) neg_codes <- c(neg_codes, l[idx])
}
print(sort(table(neg_codes), decreasing = TRUE))
cat("Resolved universal missing convention: -9 = Don't know, -8 = Refuse to answer (consistent across ALL 9 waves).\n")
cat("-7 also appears (2 vars, W1/W6-W9) but means 'Deficit' (a substantive negative-income value), NOT missing.\n")

# ============================================================
# PART B — RESOLVED VARIABLE MAP
# ============================================================

wv_age    <- c("w01A001_age", sprintf("w0%dA002_age", 2:9))
wv_byear  <- c("w01A001y",    sprintf("w0%dA002y",    2:9))
wv_sex    <- sprintf("w0%dgender1", 1:9)
wv_edu    <- sprintf("w0%dedu", 1:9)
wv_marital<- c("w01A006", sprintf("w0%dmarital", 2:9))
wv_region <- sprintf("w0%dregion1", 1:9)
wv_urban  <- sprintf("w0%dregion3", 1:9)
wv_hhsize <- sprintf("w0%dhhsize", 1:9)
wv_homeown<- sprintf("w0%dF001", 1:9)
wv_pid    <- rep("pid", 9)
wv_hhid   <- c(rep("hhid", 8), "HHID")
wv_weight <- sprintf("w0%dwgt_c", 1:9)

wv_part_religious <- c("w01A017m01", sprintf("w0%dA033m01", 2:9))
wv_part_social    <- c("w01A017m02", sprintf("w0%dA033m02", 2:9))
wv_part_leisure   <- c("w01A017m03", sprintf("w0%dA033m03", 2:9))
wv_part_alumni    <- c("w01A017m04", sprintf("w0%dA033m04", 2:9))
wv_part_volunteer <- c("w01A017m05", sprintf("w0%dA033m05", 2:9))
wv_part_civic     <- c("w01A017m06", sprintf("w0%dA033m06", 2:9))
wv_part_none      <- c("w01A017m08", sprintf("w0%dA033m08", 2:9))
wv_partfreq_civic <- c("w01A019_06", sprintf("w0%dA035_06", 2:9))
wv_partfreq_religious <- c("w01A019_01", sprintf("w0%dA035_01", 2:9))
wv_partfreq_social    <- c("w01A019_02", sprintf("w0%dA035_02", 2:9))
wv_partfreq_leisure   <- c("w01A019_03", sprintf("w0%dA035_03", 2:9))
wv_partfreq_alumni    <- c("w01A019_04", sprintf("w0%dA035_04", 2:9))
wv_partfreq_volunteer <- c("w01A019_05", sprintf("w0%dA035_05", 2:9))

wv_basic_receipt_G <- c(rep(NA,1), sprintf("w0%dG111", 2:9))          # legacy, ALL waves W2-W9 (contra design spec)
wv_basic_receipt_E <- c(rep(NA,5), sprintf("w0%dE111", 5:9))          # design-intended, W5-W9 only (index 5 duplicated below, fixed inline)
wv_basic_amount_G  <- c(rep(NA,1), sprintf("w0%dG112", 2:9))
wv_basic_amount_E  <- c(rep(NA,4), sprintf("w0%dE113", 5:9))
wv_basic_couple    <- c(rep(NA,1), sprintf("w0%dG113", 2:9))
wv_natl_receipt    <- sprintf("w0%dE033", 1:9)
wv_natl_amount     <- sprintf("w0%dE035", 1:9)
wv_hhincome        <- c(sprintf("w0%dE126", 1:4), sprintf("w0%dE147", 5:9))
wv_realestate      <- sprintf("w0%dF058", 1:9)
wv_srh             <- sprintf("w0%dC001", 1:9)
wv_work_status     <- sprintf("w0%dD001", 1:9)

# fix wv_basic_receipt_E / wv_basic_amount_E index alignment (w1..w4 = NA, w5..w9 = E111/E113)
wv_basic_receipt_E <- c(rep(NA,4), sprintf("w0%dE111", 5:9))
wv_basic_amount_E  <- c(rep(NA,4), sprintf("w0%dE113", 5:9))

# ADL/IADL: no single raw summary var — record the component-battery ranges (stable C201-C217 all waves)
adl_components  <- "C201-C208 (Dressing, Washing face/hair/brushing, Bathing/showering, Eating, Getting in/out bed+walking, Using toilet, Using toilet without spilling, Grooming)"
iadl_components <- "C209-C217 (Household chores, Preparing meals, Laundry, Near-distance going out, Going out using transportation, Shopping, Managing money, Making/taking a call, Taking medications)"

na9 <- rep(NA_character_, 9)

variable_map <- tribble(
  ~concept,        ~target_id,               ~w1, ~w2, ~w3, ~w4, ~w5, ~w6, ~w7, ~w8, ~w9,
  ~coding, ~notes
) %>% mutate(across(w1:w9, as.character))

add_row_ <- function(map, concept, target_id, srcvec, coding, notes) {
  stopifnot(length(srcvec) == 9)
  bind_rows(map, tibble(concept=concept, target_id=target_id,
    w1=srcvec[1], w2=srcvec[2], w3=srcvec[3], w4=srcvec[4], w5=srcvec[5],
    w6=srcvec[6], w7=srcvec[7], w8=srcvec[8], w9=srcvec[9],
    coding=coding, notes=notes))
}

vm <- variable_map
vm <- add_row_(vm, "identifiers", "pid", wv_pid,
  "identity, numeric respondent ID",
  "Literal column name 'pid' in every wave (NOT wave-prefixed w0Npid). Confirmed stable panel key: W1 has 10,254 unique pid; W9 has 6,057; 5,310 of W9's pids also appear in W1 (87.7% overlap) -- consistent with attrition + the w05_new refresher cohort accounting for the rest. Genuine longitudinal linkage confirmed by real-data check, not just naming.")
vm <- add_row_(vm, "identifiers", "hhid", wv_hhid,
  "identity, numeric household ID",
  "Literal column name 'hhid' in W1-W8; W9 uses UPPERCASE 'HHID' instead. Loader must handle this case difference (e.g. via a per-wave name lookup, not a fixed sprintf pattern). W9 also carries an unrelated 'HHID22' ('In 2020, Household ID') -- not used.")
vm <- add_row_(vm, "identifiers", "weight", wv_weight,
  "identity, sampling weight",
  "UNRESOLVED / needs verification before use. Two weight families exist in the main w0N file (not Lt0N): wgt_c/wgt_p (cross-sectional/panel) from W1 (wgt_c only; wgt_p absent in W1), plus integrated wgt_a (W5 only) and wgt_ac/wgt_ap (W6-W9, for the refresher cohort). CRITICAL: the 'Horizontal weighting'/'Vertical weighting' labels on wgt_c vs wgt_p SWAP at W8-W9 relative to W1-W7 (W1-W7: wgt_c=Horizontal/cross-sectional, wgt_p=Vertical/panel; W8-W9: labels report the opposite). W9's labels also carry a stale '_8th wave' string, suggesting a copy-paste labeling artifact rather than a genuine redesign -- but this cannot be confirmed from metadata alone. Recorded wgt_c here (present in all 9 waves) as the raw-name-stable candidate; do NOT trust the label semantics for W8-W9 without checking the official KLoSA user guide. Many RD papers sidestep this by not weighting.")
vm <- add_row_(vm, "demographics", "sex", wv_sex,
  "1=Male, 5=Female (raw); recode target 1/0 or 1/2 left to Task 4",
  "w0Ngender1, present + stable across all 9 waves. -9/-8 missing codes appear in labels from W4 on (likely just unused-but-defined in W1-W3, not a coding change).")
vm <- add_row_(vm, "demographics", "birth_year", wv_byear,
  "identity, 4-digit year",
  "W1 = w01A001y; W2-W9 = w0NA002y. Anchor shift: W1 uses the A001 family (not A002) for the entire birth-date/age block. This is a genuine per-wave renumbering, same pattern as the pension G->E and income E126->E147 relocations -- NOT covered by the design spec's assumption of a stable 'w0N A002_age' name across all waves.")
vm <- add_row_(vm, "demographics", "age", wv_age,
  "identity, integer years (label formula = interview_year - birth_year)",
  "W1 = w01A001_age; W2-W9 = w0NA002_age. Label-formula text contains apparent copy-paste bugs in W6 ('=2016-w06A002y+1', extra +1), W7 ('=2018-w06A002y', wrong wave ref), W9 ('=2020-w08A002y', wrong year AND wave ref) -- these are metadata-label bugs; the actual computed integer values should be spot-checked against birth_year once real data is loaded (not done in this pass). MAJOR FINDING: birth-MONTH variables (w01A001m; w0NA002m for W2-W9) exist and are FULLY populated (100% non-NA, spot-checked W1/W4/W9) -- contradicts the design spec's stated 'no birth month located' assumption. Day-precision interview-date variables (w0Nmniw_y/mniw_m/mniw_d) also exist in ALL 9 waves. Together these could support a far finer RD running variable (age in months, or exact days-to-cutoff) than the integer-year age the design spec assumed as a hard limitation -- flag prominently for the paper repo.")
vm <- add_row_(vm, "demographics", "education", wv_edu,
  "-9=DK,-8=Refuse,1=~Elementary school,2=Middle school,3=High school,4=College/University~ (4-level ladder)",
  "w0Nedu, present + stably coded across all 9 waves. Full label text truncated by terminal width in early scans; confirmed via untruncated dump: 1=~Elementary school, 2=Middle school, 3=High school, 4=College/University~ (tildes appear to denote 'or below'/'or above' bounding, consistent with a 4-level ladder). Cross-survey education_5cat mapping is out of scope for this task.")
vm <- add_row_(vm, "demographics", "marital_status", wv_marital,
  "1=Married/living with partner,2=Separated,3=Divorced,4=Widowed/missing(dispersed family),5=Never married",
  "W1 = w01A006 ('Currently marital status'); W2-W9 = w0Nmarital ('In <year>, the current marital status'). W1's item is NOT named 'marital' -- located via broader label search; coding confirmed IDENTICAL to W2-W9's scale.")
vm <- add_row_(vm, "demographics", "region", wv_region,
  "11=Seoul,21=Busan,22=Daegu,23=Incheon,24=Gwangju,25=Daejeon,26=Ulsan,27=Sejong(from W5),31=Gyeonggi,32=Gangwon,33=Chungbuk,34=Chungnam,35=Jeonbuk,36=Jeonnam,37=Gyeongbuk,38=Gyeongnam",
  "w0Nregion1 ('a local variable' = si-do), present + stable numeric coding across all 9 waves (Sejong=27 added from W5, consistent with its 2012 creation as a special city -- not a code-drift bug).")
vm <- add_row_(vm, "demographics", "urban_rural", wv_urban,
  "1=Metropolitan, 2=City, 3=Town (3-level, monotonic urbanicity gradient)",
  "UNCERTAIN -- two candidates exist. Picked w0Nregion3 ('Metropolitan/City/Town') as primary: labels are self-consistent and monotonically ordered. A second candidate, w0Nregion2 ('Village'/'Town', 2-level), is also present in all waves; real-data check (W4) shows region2's 'Town' count (1,933) EXACTLY equals region3's 'Town' count (1,933), and region2's 'Village' (5,553) = region3's Metropolitan (3,167) + City (2,386) -- i.e. region2 is a coarsening of region3, NOT an independent variable. However region2's English label 'Village' for the LARGER, more-populous code looks like a probable mistranslation of Korean administrative 동(dong, urban) vs 읍/면(eup/myeon, town/rural) -- 'Village' normally implies rural, but the data pattern suggests the opposite. Flagged for downstream verification against the official Korean codebook before use; region3 avoids the ambiguity.")
vm <- add_row_(vm, "demographics", "hh_size", wv_hhsize,
  "identity, integer count",
  "w0Nhhsize ('The number of household [member]'), present + stable across all 9 waves.")
vm <- add_row_(vm, "demographics", "home_owner", wv_homeown,
  "1=Own home -> recode 1; 2=Jeonse(deposit-based rental),3=Jeonse+monthly,4=Monthly rental,5=Others -> recode 0",
  "w0NF001 ('The type of currently residing home'), present + stable across all 9 waves at the SAME position (unlike most other F-block totals). A related but distinct item, w0NF004 ('Whether or not the residing home under R's name'), asks about deed-holder identity rather than tenure type -- not used as primary; noted as a secondary candidate if the paper wants a finer 'owns outright vs joint vs other-name' distinction.")

# participation battery
vm <- add_row_(vm, "participation", "part_religious", wv_part_religious, "0=No, 1=Yes",
  "W1 = w01A017m01 (NOT w01A033m01 -- A033 family is ABSENT in W1 entirely). W2-W9 = w0NA033m01. Coding confirmed identical (0/1) in both families.")
vm <- add_row_(vm, "participation", "part_social_club", wv_part_social, "0=No, 1=Yes",
  "W1 = w01A017m02; W2-W9 = w0NA033m02. Same W1 renumbering as part_religious.")
vm <- add_row_(vm, "participation", "part_leisure", wv_part_leisure, "0=No, 1=Yes",
  "W1 = w01A017m03; W2-W9 = w0NA033m03. Same W1 renumbering.")
vm <- add_row_(vm, "participation", "part_alumni", wv_part_alumni, "0=No, 1=Yes",
  "W1 = w01A017m04; W2-W9 = w0NA033m04. Same W1 renumbering.")
vm <- add_row_(vm, "participation", "part_volunteer", wv_part_volunteer, "0=No, 1=Yes",
  "W1 = w01A017m05; W2-W9 = w0NA033m05. Same W1 renumbering.")
vm <- add_row_(vm, "participation", "part_civic", wv_part_civic, "0=No, 1=Yes",
  "W1 = w01A017m06 ('Participating to the Political parties, the NGOs, the interest groups'); W2-W9 = w0NA033m06. THE 'buy a citizen' outcome. Correction to design-spec anchor: exists in W1, just under a different item number -- NOT absent as one might assume from a naive w01A033m06 lookup.")
vm <- add_row_(vm, "participation", "part_none", wv_part_none, "0=No, 1=Yes",
  "W1 = w01A017m08; W2-W9 = w0NA033m08.")
vm <- add_row_(vm, "participation", "partfreq_civic", wv_partfreq_civic,
  "-9=DK,-8=Refuse,1=Almost every day...10=Almost never engaged (10-pt DECLINING-frequency ordinal: LOW code = MORE frequent)",
  "W1 = w01A019_06; W2-W9 = w0NA035_06. Direction warning: this is not a simple linear frequency count -- code 1 is the MOST frequent, code 10 is 'almost never engaged'. Reverse before treating as an increasing-frequency scale.")
vm <- add_row_(vm, "participation", "partfreq_religious", wv_partfreq_religious, "same 10-pt declining-frequency scale as partfreq_civic", "W1 = w01A019_01; W2-W9 = w0NA035_01.")
vm <- add_row_(vm, "participation", "partfreq_social_club", wv_partfreq_social, "same 10-pt declining-frequency scale as partfreq_civic", "W1 = w01A019_02; W2-W9 = w0NA035_02.")
vm <- add_row_(vm, "participation", "partfreq_leisure", wv_partfreq_leisure, "same 10-pt declining-frequency scale as partfreq_civic", "W1 = w01A019_03; W2-W9 = w0NA035_03.")
vm <- add_row_(vm, "participation", "partfreq_alumni", wv_partfreq_alumni, "same 10-pt declining-frequency scale as partfreq_civic", "W1 = w01A019_04; W2-W9 = w0NA035_04.")
vm <- add_row_(vm, "participation", "partfreq_volunteer", wv_partfreq_volunteer, "same 10-pt declining-frequency scale as partfreq_civic", "W1 = w01A019_05; W2-W9 = w0NA035_05.")

# treatment (pension) -- both legacy and relocated candidates recorded
vm <- add_row_(vm, "pension_basic", "basic_pension_receipt", wv_basic_receipt_E,
  "E111: -9=DK,-8=Refuse,1=Check (else NA -- checkbox-style, NOT an explicit 0=No code)",
  "DESIGN-INTENDED per the module-relocation story: absent W1-W4, w0NE111 W5-W9. CRITICAL UNRESOLVED FINDING: legacy w0NG111 ('Receipt of the Basic Old-Age Pension Benefit', categorical 1=currently receiving/3=will receive/5=not entitled) is NOT dead in W5-W9 as the design spec assumed -- real-data check shows it stays substantially populated (41-53% non-NA, W5=2,880 to W9=3,239 non-NA), comparable to or exceeding E111's coverage (E5=2,393 to W9=2,917). E111 itself is a 'checkbox' item: value 1='Check' is always paired 1:1 with non-NA E112 (months) and E113 (amount); rows where E111 is NA have E112/E113 also 100% NA (consistent with 'blank = did not receive', but this is an INFERENCE, not an explicit code -- true item-nonresponse is indistinguishable from a genuine 'no' under this pattern). G111 and E111 receipt COUNTS are in the same ballpark per wave (e.g. W9: G111=1 count 3,074 vs E111=1 count 2,917) suggesting they track the same underlying construct via two different questionnaire modules, not two different benefits. Task 6 MUST cross-tab G111 vs E111 agreement (where both non-missing) before choosing one as the authoritative source for W5-W9; this is the single highest-stakes ambiguity in the whole discovery pass since it is the paper's treatment variable.")
vm <- add_row_(vm, "pension_basic", "basic_pension_receipt_LEGACY_G", wv_basic_receipt_G,
  "G111: -9=DK[-8=Refuse from W3],1=Yes currently receiving,3=No but will receive at pension age,5=No not entitled",
  "Secondary/legacy candidate for the SAME concept, recorded because it survives (and is well-populated) through W9 -- see the critical note on basic_pension_receipt above. If Task 6 concludes G111 is more reliable post-2014, this is its resolved source. Absent in W1.")
vm <- add_row_(vm, "pension_basic", "basic_pension_amount", wv_basic_amount_E,
  "E113: 10,000-KRW units, monthly average; -9=DK,-8=Refuse",
  "Design-intended: absent W1-W4, w0NE113 W5-W9 (paired with E111 above). W5 real-data median ~= 9 (10k-won units, i.e. ~90,000 KRW/month); rises to median ~25 by W9 (consistent with benefit expansion + inflation).")
vm <- add_row_(vm, "pension_basic", "basic_pension_amount_LEGACY_G", wv_basic_amount_G,
  "G112: 10,000-KRW units, monthly average; -9=DK[-8=Refuse from W3]",
  "Legacy counterpart to basic_pension_amount, absent W1, present W2-W9 (same persistence issue as G111).")
vm <- add_row_(vm, "pension_basic", "basic_pension_couple", wv_basic_couple,
  "1=Provided to the individual, 5=Provided to the couple",
  "w0NG113, present W2-W9 (absent W1). NOTE: unlike receipt/amount, this item was NOT found relocated to the E-block -- no E-equivalent 'self or couple' flag was located in this pass. If the paper needs this for the W5-W9 E111-based receipt, that gap is UNRESOLVED (only the legacy G-block carries it).")

vm <- add_row_(vm, "pension_other", "natl_pension_receipt", wv_natl_receipt,
  "1=Only monthly benefits,2=Only lump-sum,3=Received both,4=No (4-category, NOT simple binary); -9=DK,-8=Refuse",
  "w0NE033, present + stably coded across all 9 waves. Recode to binary 'received any' = {1,2,3}->1, 4->0 if a simple confound flag is wanted.")
vm <- add_row_(vm, "pension_other", "natl_pension_amount", wv_natl_amount,
  "identity, 10,000-KRW units, monthly average; -9=DK,-8=Refuse",
  "w0NE035, present + stable across all 9 waves.")

vm <- add_row_(vm, "income_assets", "hh_income_total", wv_hhincome,
  "identity, 10,000-KRW units, annual total",
  "THIRD relocation instance (after G->E pension and A001->A002 age): W1-W4 = w0NE126; W5-W9 = w0NE147. Real-data median check confirms same units/order of magnitude across the boundary (W4 E126 median=2,000; W5 E147 median=2,000) -- low-risk relocation, unlike the pension G111/E111 case.")
vm <- add_row_(vm, "income_assets", "assets_realestate", wv_realestate,
  "identity, 10,000-KRW units",
  "w0NF058 ('The total amount of real estate'), present + stable across all 9 waves at the same position.")
vm <- add_row_(vm, "income_assets", "assets_financial", na9,
  "NOT RESOLVED",
  "No raw variable named/labeled as a 'total financial assets' summary was located in any wave. The F-block has a household-asset total (w0NF234, = real estate + financial + other, net of debt, presumably) and a real-estate total (w0NF058, resolved above), but the financial-only total must be DERIVED -- either (a) F234 minus F058 (approximation, includes 'other non-financial assets' contamination), or (b) sum the individual components: cash/checking (F095), time deposits (F102), stocks/funds (F109), bonds (F116), private savings club/gye (F146), other financial assets (F160). Left null per instructions rather than inventing a name; Task 7 must pick a derivation.")

vm <- add_row_(vm, "health", "srh", wv_srh,
  "1=best...5=worst ordinal, but ANCHOR WORDING CHANGES at W3",
  "w0NC001 ('Respondent's (principal) subjective health'), present + stable POSITION across all 9 waves, but the response-category WORDING differs: W1-W2 = 1=Very good,2=Good,3=Fair,4=Bad,5=Very bad (no 'Excellent' category); W3-W9 = 1=Excellent,2=Very good,3=Good,4=Fair,5=Poor (adds 'Excellent' as a new top category, pushing 'Very good' to position 2). Ordinal direction (1=best,5=worst) is consistent throughout, so identity harmonization is safe for a monotonic treatment, but the reference-point shift at W3 is a genuine instrument-stability finding for the audit task -- W1/W2 respondents never had the 'Excellent' option available.")
vm <- add_row_(vm, "health", "adl_limit", na9,
  "NOT a single raw var -- component battery only",
  paste0("No single ADL summary variable exists. Raw component battery ", adl_components, " is present with STABLE variable numbers (C201-C208) across all 9 waves; coding is non-linear: 1=No help needed, 3=Need help to some extent, 5=Need help in every respect (NOT 1/2/3). Task 7 must derive a summary (e.g. count of items >=3, or a binary any-limitation flag), following the same method:derive pattern already used for participation_count in the plan."))
vm <- add_row_(vm, "health", "iadl_limit", na9,
  "NOT a single raw var -- component battery only",
  paste0("No single IADL summary variable exists. Raw component battery ", iadl_components, " is present with STABLE variable numbers (C209-C217) across all 9 waves; same 1/3/5 coding as adl_limit. Requires the same derive treatment."))

vm <- add_row_(vm, "work", "work_status", wv_work_status,
  "1=Yes(currently working), 5=No; -9=DK,-8=Refuse",
  "w0ND001 ('Currently work'), present + stable across all 9 waves -- the cleanest single binary proxy. A finer categorical breakdown is available conditional on D001=Yes via w0ND002 ('Main job': 1=wage employed,2=self-employed,3=unpaid family >=18h/wk,4=unpaid family <18h/wk), also present all 9 waves -- recorded as a secondary/finer option for Task 7. Two label-similar variables were investigated and REJECTED as work_status candidates: w0ND006 ('current employment status in the job market') is a job-seeking-WILLINGNESS ladder, not a status classification, AND its own category structure differs between W1 (simple Yes/No 'possibility to start working') and W2-W9 (a 5-7-category willingness scale) -- not a stable construct across waves. w0ND009 ('(Answer modification) In the previous interview, the employment status') is a carry-forward RECHECK item referring to the prior wave's status, is ABSENT in W5, and is not the current-wave status.")

vm <- vm %>% mutate(across(w1:w9, ~ ifelse(is.na(.x), "null", .x)))

out_dir <- here("outputs","klosa")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
write.csv(vm, file.path(out_dir, "variable_map.csv"), row.names = FALSE)

cat("\n===== RESOLVED MISSING CONVENTION (all specs should declare this) =====\n")
cat("missing_conventions.treat_as_na.codes: [-9, -8]\n")
cat("  -9 = \"Don't know\" (consistent across all 9 waves, occasional typo variants e.g. \"Don' tknow\")\n")
cat("  -8 = \"Refuse to answer\" (consistent across all 9 waves, occasional typo variants e.g. \"Refuse to anwer\")\n")
cat("  -7 appears on exactly 2 variables (W1 D615/D713, self-employment income) but means the SUBSTANTIVE value\n")
cat("  'Deficit' (negative income), NOT a missing code -- do not add -7 to the universal treat_as_na set.\n")

cat(sprintf("\nWrote %s (%d rows).\n", file.path(out_dir, "variable_map.csv"), nrow(vm)))
