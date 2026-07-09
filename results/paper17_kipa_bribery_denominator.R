# paper17_kipa_bribery_denominator.R
# -----------------------------------------------------------------------------
# KIPA Corruption first-person bribery item (a13 / q13, "corr_bribery_experience_1yr"):
# conditional vs. unconditional yes-rate per wave, 2004-2021.
#
# WHY: from 2016 on, the item is gated behind a prior official-contact screener.
# ~50% of respondents are routed out (coded -1 = 비해당 "not applicable").
# The harmonized RDS drops -1/refuse to NA, so its rate is CONDITIONAL on official
# contact from 2016 onward, which (a) inflates 2016-2021 levels ~2x and (b) creates
# a spurious uptick at the 2015->2016 boundary. ABS witnessed corruption is a full-
# population measure, so the apples-to-apples comparison is the UNCONDITIONAL rate
# (routed-out treated as structural zeros: no official contact => no bribe possible).
#
# Reads raw KOSSDA .sav directly (the harmonized RDS cannot distinguish 비해당 from
# refusal). Run from repo root.
#
# For a reusable accessor that returns the conditional + unconditional rates from
# the harmonized RDS (no raw SPSS needed), use src/r/lookups/kipa_bribery_series().
# This script is its raw-data provenance companion: it additionally splits the
# routed-out (비해당) cases from genuine refusals, which the harmonized file
# collapses together into NA.
# -----------------------------------------------------------------------------
suppressMessages({library(haven); library(here)})

B <- here("data", "kipa-corruption", "raw", "unzipped")
rd <- function(f) suppressWarnings(read_sav(file.path(B, f), user_na = TRUE))

# Strip haven's value-label / user-missing attributes so 비해당(-1) and refuse(3/9)
# survive as plain numbers instead of being coerced to NA.
getraw <- function(d, cands = c("a13", "q13")) {
  vn <- names(d)[tolower(names(d)) %in% cands]
  if (!length(vn)) stop("bribery var not found")
  v <- d[[vn[1]]]
  attr(v, "labels") <- NULL; attr(v, "na_values") <- NULL; attr(v, "na_range") <- NULL
  as.numeric(v)
}

row_for <- function(year, v) {
  n      <- length(v)
  yes    <- sum(v == 1, na.rm = TRUE)
  no     <- sum(v == 2, na.rm = TRUE)
  refuse <- sum(v %in% c(3, 9), na.rm = TRUE)   # 응답거부 / 무응답
  routed <- n - yes - no - refuse               # 비해당 (no official contact) + blanks
  data.frame(
    year = year, n = n, yes = yes, no = no, routed_out = routed, refuse = refuse,
    cond_pct   = round(100 * yes / (yes + no), 2),  # among answerers (= harmonized RDS)
    uncond_pct = round(100 * yes / (n - refuse), 2) # full sample, routed-out = structural no
  )
}

rows <- list()

# 2004-2007: pooled cumulative file, year column valued 1..4
dc <- rd("13081/kor_data_cum0009.sav")
yc <- as.integer(zap_labels(dc[["year"]])); vc <- getraw(dc)
for (k in 1:4) rows[[length(rows) + 1]] <- row_for(2003 + k, vc[yc == k])

# 2008-2021: one annual file each (KOSSDA handle -> file)
ann <- c(
  "2008" = "13988/kor_data_20080065.sav", "2009" = "15387/kor_data_20090159.sav",
  "2010" = "15386/kor_data_20100192.sav", "2011" = "15356/kor_data_20110177.SAV",
  "2012" = "15788/kor_data_20120254.SAV", "2013" = "23278/kor_data_20130182.sav",
  "2014" = "23277/kor_data_20140202.sav", "2015" = "23276/kor_data_20150127.sav",
  "2016" = "23275/kor_data_20160072.sav", "2017" = "23266/kor_data_20170057.sav",
  "2018" = "24741/kor_data_20180110.sav", "2019" = "24742/kor_data_20190062.sav",
  "2020" = "24743/kor_data_20200035.sav", "2021" = "25785/kor_data_20210092.sav"
)
for (yr in names(ann)) rows[[length(rows) + 1]] <- row_for(as.integer(yr), getraw(rd(ann[[yr]])))

kipa_bribery_rates <- do.call(rbind, rows)
print(kipa_bribery_rates, row.names = FALSE)

# Headline decline (relative), 2004 -> 2021:
#   unconditional 13.80% -> 0.60% = -95.7%  (matches the project's "fell ~95%" note)
#   conditional   13.80% -> 1.17% = -91.5%  (bumpy; +1.5pp 2016 gate artifact)
