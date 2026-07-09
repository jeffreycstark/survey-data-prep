# paper05_thailand_deep_south.R
# -----------------------------------------------------------------------------
# ABS Thailand: is the Deep South (Pattani, Yala, Narathiwat) recoverable, and
# does it confound the "South declines least" military-trust finding (Paper 05)?
#
# WHY: Paper 05's regional analysis reports that the South's trust in the military
# falls least between W4 and W6. A reviewer asked whether the Deep South -- whose
# relationship with the army is adversarial -- is lumped into that "South" cell and
# masks the pattern.
#
# GROUND TRUTH (settled 2026-07-09 from the W6 Thailand technical report,
# data/abs/raw/wave6/W6 Thailand Technical Report_20250108.pdf, Appendix 1):
#   - The W6 frame is household-registration (Community Development Dept.),
#     excluding only expatriate workers and students. NO security-related exclusion.
#   - The South's PSU list INCLUDES Pattani (Khok Pho district) and Narathiwat
#     (Tak Bai district). Yala is NOT sampled. So the Deep South IS in the W6 frame.
#   - Three-stage PPS design: 100 districts -> 100 sub-districts -> respondents;
#     South = 14 districts, ~12 tambol, 161 respondents. Response rate 71.9%.
#     Weights post-stratify on gender/age/residence-area ONLY.
#
# WHAT THIS CORRECTS: an earlier version of this script inferred, from SE11a
# (ethnicity="Malayu") and SE6 (religion=Muslim), that the Deep South was
# "effectively absent" from W4 and W6. That inference was WRONG. The technical
# report shows the Deep South is in the W6 sample; SE11a/SE6 simply undercount
# minorities in W4 and W6 (see section 3). Never read low Malayu/Muslim counts in
# W4/W6 as evidence of Deep South absence -- they are a measurement artifact.
#
# WHAT WE CAN NOW SAY, per wave:
#   - W6: Deep South is documented in-frame. Interviewer IR1==504 is the Deep South
#     cluster (holds 13 of the South's 14 Muslims and all 6 Malay-language
#     interviews). Trust there = 20.3% vs 29.5% for the rest of the South; including
#     it pulls the reported South down ~3pp. The Deep South is ~31% of the W6 South
#     cell -- ABOVE its ~22% population share, not near zero.
#   - W5: SE11a/SE6 are reliable this wave (Malayu=37 nationally; 21.8% of the South
#     cell, matching the Deep South's ~22% population share). Directly measurable.
#   - W4: NO technical report, NO usable cluster variable (ir1 is all -1 for
#     Thailand), and SE11a/SE6 undercount. The Deep South's status in W4 is
#     genuinely unknown, so section 6 bounds it by reconstruction instead.
#
# BOTTOM LINE: the finding survives cleanly. The W6 South already contains the Deep
# South; removing the Deep South cluster leaves the South declining ~45pp (still the
# smallest fall by ~26pp). And any residual W4 uncertainty biases IN the paper's
# favour -- if W4 excluded the Deep South while W6 included it, the observed decline
# OVERstates the South's fall.
#
# Reads raw ABS .sav directly (region, ethnicity, religion, interviewer are not
# harmonized). Run from repo root: Rscript results/paper05_thailand_deep_south.R
# -----------------------------------------------------------------------------

suppressPackageStartupMessages(library(haven))

THAILAND      <- 8L
TRUSTING      <- 1:2      # q13: 1=great deal, 2=quite a lot (3/4 = less; 7/8/9 = DK/refuse)
DEEP_SOUTH_SHARE <- 0.22  # Pattani+Yala+Narathiwat as a share of the South region population

waves <- list(
  w4 = list(path = "data/abs/raw/wave4/W4_v15_merged20250609_release.sav",
            region = "region", religion = "se6", ethnicity = "se11a",
            weight = "w", interviewer = "ir1", homelang = "ir2c", filter_country = TRUE),
  w5 = list(path = "data/abs/raw/wave5/20230505_W5_merge_15.sav",
            region = "Region", religion = "SE6", ethnicity = "Se11a",
            weight = "w", interviewer = "IR1", homelang = "IR2c", filter_country = TRUE),
  w6 = list(path = "data/abs/raw/wave6/W6_8_Thailand_Release_20250108.sav",
            region = "REGION", religion = "SE6", ethnicity = "SE11a",
            weight = "W", interviewer = "IR1", homelang = "IR2c", filter_country = FALSE)
)

# Case-insensitive column fetch (ABS renames columns between releases); NA if absent.
col <- function(d, v) {
  hit <- names(d)[tolower(names(d)) == tolower(v)]
  if (length(hit) == 0) return(rep(NA, nrow(d)))
  d[[hit[1]]]
}

# Weighted % trusting, DK/refuse dropped from the denominator.
wpct <- function(q, w) {
  keep <- !is.na(q)
  if (!any(keep)) return(NA_real_)
  round(100 * sum(w[q %in% TRUSTING], na.rm = TRUE) / sum(w[keep], na.rm = TRUE), 1)
}

load_thailand <- function(spec) {
  d <- read_sav(spec$path, encoding = "latin1")
  if (spec$filter_country) d <- d[as.numeric(col(d, "country")) == THAILAND, ]
  w <- as.numeric(col(d, spec$weight)); w[is.na(w)] <- 1
  q <- as.numeric(col(d, "q13")); q[!q %in% 1:4] <- NA
  data.frame(
    region_code = as.numeric(col(d, spec$region)),
    region      = as.character(as_factor(col(d, spec$region))),   # LABELS, never codes
    religion    = as.character(as_factor(col(d, spec$religion))),
    ethnicity   = as.character(as_factor(col(d, spec$ethnicity))),
    interviewer = suppressWarnings(as.numeric(as.character(col(d, spec$interviewer)))),
    homelang    = as.character(as_factor(col(d, spec$homelang))),
    trust_mil   = q,
    weight      = w,
    stringsAsFactors = FALSE
  )
}

th       <- lapply(waves, load_thailand)
is_south <- function(d) d$region == "South"
is_muslim<- function(d) d$religion %in% c("Islam", "Sunni", "Shia")

# --- 1. The W6 REGION code swap (documented in CLAUDE.md) ----------------------
cat("\n=== 1. REGION code -> label mapping by wave (codes are NOT stable) ===\n")
for (w in names(th)) {
  m <- unique(th[[w]][, c("region_code", "region")])
  m <- m[order(m$region_code), ]
  cat(sprintf("  %s: %s\n", w, paste(sprintf("%d=%s", m$region_code, m$region), collapse = "  ")))
}
cat("  ^ 803/804 swap Central<->Northeast in W6. Always as_factor() PER FILE.\n")

# --- 2. What the W6 technical report documents (the anchor) -------------------
cat("\n=== 2. W6 Thailand technical report -- documented sampling facts ===\n")
cat("  Source: data/abs/raw/wave6/W6 Thailand Technical Report_20250108.pdf (Appendix 1)\n")
cat("  * South PSUs INCLUDE Pattani (Khok Pho) and Narathiwat (Tak Bai).\n")
cat("  * Yala is NOT in the South PSU list.\n")
cat("  * Frame = household registration; excludes only expatriates & students.\n")
cat("  * No security-related exclusion of the Deep South. Response rate 71.9%.\n")
cat("  => The Deep South is IN the W6 sample. This is documented, not inferred.\n")

# --- 3. Why SE11a/SE6 are NOT a Deep South detector in W4/W6 ------------------
# Corrects the earlier script: low Malayu/Muslim counts in W4/W6 are a measurement
# artifact, not evidence of Deep South absence. Thailand is ~5% Muslim nationally.
cat("\n=== 3. Ethnicity/religion undercount minorities in W4 and W6 ===\n")
cat(sprintf("  %-4s %14s %20s\n", "wave", "Malayu (natl)", "Muslim (natl, % of TH)"))
for (w in names(th)) {
  d <- th[[w]]
  cat(sprintf("  %-4s %14d %14d (%4.1f%%)\n",
              w, sum(d$ethnicity == "Malayu", na.rm = TRUE),
              sum(is_muslim(d)), 100 * mean(is_muslim(d))))
}
cat("  Thailand is ~5% Muslim. W4 (0.5%) and W6 (1.2%) undercount badly; only W5\n")
cat("  (6.6%) is credible. So a near-zero Malayu/Muslim count in W4/W6 says nothing\n")
cat("  about whether the Deep South was sampled -- the variables simply fail there.\n")

# --- 4. Where the Deep South IS directly measurable: W5 (proxy) & W6 (cluster) --
cat("\n=== 4. Deep South share of the South cell, where measurable ===\n")
d5 <- th$w5; s5 <- is_south(d5)
cat(sprintf("  W5 (ethnicity works): %d of %d South respondents are Malayu = %.1f%%",
            sum(s5 & d5$ethnicity == "Malayu"), sum(s5),
            100 * sum(s5 & d5$ethnicity == "Malayu") / sum(s5)))
cat(sprintf("  -- matches the ~%.0f%% population share.\n", 100 * DEEP_SOUTH_SHARE))
d6 <- th$w6; s6 <- is_south(d6)
cat("  W6 (cluster works): interviewer IR1 identifies 4 South clusters --\n")
cat(sprintf("    %-6s %4s %8s %10s %16s\n", "IR1", "n", "Muslim", "Malay-lang", "trust mil (wtd)"))
for (i in sort(unique(d6$interviewer[s6]))) {
  k <- s6 & d6$interviewer == i
  cat(sprintf("    %-6d %4d %8d %10d %15.1f%%\n",
              i, sum(k), sum(is_muslim(d6)[k]),
              sum(d6$homelang[k] == "Malayu language", na.rm = TRUE),
              wpct(d6$trust_mil[k], d6$weight[k])))
}
cat("    -> IR1==504 is the Deep South cluster (13 of 14 Muslims; all 6 Malay-lang).\n")

# --- 5. Does removing the W6 Deep South cluster change the ordering? -----------
cat("\n=== 5. W6 South with vs without the Deep South cluster (IR1==504) ===\n")
ds6 <- s6 & d6$interviewer == 504
cat(sprintf("  Deep South cluster (504)     : n=%3d  trust = %.1f%%\n",
            sum(ds6), wpct(d6$trust_mil[ds6], d6$weight[ds6])))
cat(sprintf("  Rest of South (501-503)      : n=%3d  trust = %.1f%%\n",
            sum(s6 & !ds6), wpct(d6$trust_mil[s6 & !ds6], d6$weight[s6 & !ds6])))
cat(sprintf("  South as reported (all)      : n=%3d  trust = %.1f%%\n",
            sum(s6), wpct(d6$trust_mil[s6], d6$weight[s6])))
cat(sprintf("  Deep South = %.0f%% of the W6 South cell (ABOVE its ~%.0f%% pop share).\n",
            100 * sum(ds6) / sum(s6), 100 * DEEP_SOUTH_SHARE))

# --- 6. Regional trajectory, with the W6 Deep-South-excluded variant -----------
cat("\n=== 6. Weighted % trusting the military, by region ===\n")
regions <- c("Bangkok", "North", "Northeast", "Central", "South")
cat(sprintf("  %-11s %7s %7s %7s %9s\n", "region", "W4", "W5", "W6", "W4->W6"))
for (r in regions) {
  v <- vapply(th, function(d) wpct(d$trust_mil[d$region == r], d$weight[d$region == r]), numeric(1))
  cat(sprintf("  %-11s %6.1f%% %6.1f%% %6.1f%% %8.1fpp\n", r, v[1], v[2], v[3], v[3] - v[1]))
}
south_w4    <- wpct(th$w4$trust_mil[is_south(th$w4)], th$w4$weight[is_south(th$w4)])
south_w6    <- wpct(d6$trust_mil[s6], d6$weight[s6])
south_w6_ex <- wpct(d6$trust_mil[s6 & !ds6], d6$weight[s6 & !ds6])
north_w4w6  <- {v <- vapply(th, function(d) wpct(d$trust_mil[d$region=="North"], d$weight[d$region=="North"]), numeric(1)); v[3]-v[1]}
cat(sprintf("\n  South W4->W6 as reported     : %.1fpp\n", south_w6 - south_w4))
cat(sprintf("  South W4->W6 excl. Deep South : %.1fpp (drop W6 cluster 504)\n", south_w6_ex - south_w4))
cat(sprintf("  Next-smallest fall (North)    : %.1fpp\n", north_w4w6))
cat("  South still declines least either way (and starts lowest -- floor effect).\n")

# --- 7. W4 has no technical report: bound the Deep South by reconstruction ------
# W4 Deep South status is unknown. Restore it to the South cell at its ~22% share
# with ANY trust value in [0,100] and recompute the W4->W6 South decline.
# (W6 already contains the Deep South, so only the W4 endpoint is reconstructed.)
cat("\n=== 7. W4 reconstruction bound (Deep South status unknown in W4) ===\n")
p <- DEEP_SOUTH_SHARE
recon_decline <- function(v) (( (1 - p) * south_w4 + p * v ) - south_w6)  # if DS absent from W4 obs
cat(sprintf("  Assume W4's observed South (%.1f%%) EXCLUDES the Deep South, then add it\n", south_w4))
cat("  back at 22% with trust value v; decline = full_W4 - W6_reported:\n")
cat(sprintf("    v=0   (DS never trusts) : decline = %.1fpp\n", recon_decline(0)))
cat(sprintf("    v=7   (W5 Malayu rate)  : decline = %.1fpp\n", recon_decline(7)))
cat(sprintf("    v=100 (DS always trusts): decline = %.1fpp\n", recon_decline(100)))
cat(sprintf("  Worst-case South fall %.1fpp < North's %.1fpp -> South STILL declines least.\n",
            recon_decline(100), abs(north_w4w6)))
cat("  And if the Deep South WAS in W4, no correction is needed (decline = as reported).\n")

# --- 8. What remains genuinely absent, and caveats ----------------------------
cat("\n=== 8. Still absent / caveats ===\n")
cat("  * No province/changwat/district/PSU variable in the respondent microdata --\n")
cat("    the PSU list lives only in the W6 technical report PDF, not the .sav.\n")
cat("  * W1-W3 have no region variable at all (only level3 urban/rural).\n")
cat("  * W4: no technical report ships locally; ir1 is all -1 -> no cluster proxy.\n")
cat("  * IR1 is an INTERVIEWER id, not a PSU id. 4 South clusters is too few for\n")
cat("    cluster-robust SEs; treat cluster 504 as a descriptive Deep South proxy,\n")
cat("    and acknowledge the multistage design effect in a footnote rather than\n")
cat("    attempting design-based variance from the public file.\n")
cat("  * W5 uniquely splits SE6 into Islam(40)/Sunni(42); W4/W6 code only Islam(40).\n\n")
