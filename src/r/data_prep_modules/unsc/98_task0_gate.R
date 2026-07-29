# UNSC / UNGA: paper-bank 24 TASK 0 feasibility gate
#
# Answers DATA-REQUEST §4 acceptance criteria 1 and 2. Both depend only on
# deliverables 2.1 (unga_idealpoints) and 2.3 (unsc_membership_terms), so the
# gate can be settled before the aid table exists.
#
#   criterion 1 — ideal-point coverage END YEAR
#   criterion 2 — exit events by post-exit window completeness
#   criterion 3 — aid coverage overlap        [BLOCKED: deliverable 2.4]
#   criterion 4 — crosswalk unmatched rows    [BLOCKED: §3 crosswalk]
#
# Gate condition, from the request:
#   >= 100 exits with a COMPLETE +5-year post-exit ideal-point window
#   >=  60 exits with a COMPLETE +10-year window
#   If +10 fails but +5 holds, the design TRUNCATES to +5 rather than dying.
#
# Event definition: an EXIT is the end of a non-permanent term. Terms are two
# calendar years beginning 1 January, so a 2010–2011 term exits at end-2011 and
# its +5 window is 2012–2016. The window is the k years STRICTLY AFTER
# term_end_year, and is "complete" only if the state has a non-NA ideal point in
# EVERY one of those years — not merely some.

library(here)
suppressPackageStartupMessages({
  library(dplyr)
})

ip <- readRDS(here("data", "processed", "unga_idealpoints.rds"))
tm <- readRDS(here("data", "processed", "unsc_membership_terms.rds"))

cat("\n══ paper-bank 24 — TASK 0 gate ══\n")

## criterion 1 ---------------------------------------------------------------
usable <- ip %>% filter(!is.na(ideal_point))
end_year <- max(usable$year)

cat("\n[1] ideal-point coverage\n")
cat(sprintf("    usable rows : %s | states: %d\n",
            format(nrow(usable), big.mark = ","), n_distinct(usable$country_text_id)))
cat(sprintf("    coverage    : %d–%d   <- END YEAR = %d\n",
            min(usable$year), end_year, end_year))
cat(sprintf("    SE present  : %.1f%% (ideal_point_se_derived)\n",
            100 * mean(!is.na(usable$ideal_point_se_derived))))
tail_cov <- usable %>% filter(year >= end_year - 3) %>% count(year)
cat("    tail density:",
    paste(sprintf("%d:%d", tail_cov$year, tail_cov$n), collapse = "  "), "\n")

## criterion 2 ---------------------------------------------------------------
have <- usable %>% distinct(country_text_id, year)

window_complete <- function(k) {
  tm %>%
    filter(term_end_year + k <= end_year) %>%
    rowwise() %>%
    mutate(n_have = sum(have$country_text_id == country_text_id &
                        have$year >  term_end_year &
                        have$year <= term_end_year + k)) %>%
    ungroup() %>%
    mutate(complete = n_have == k)
}

cat(sprintf("\n[2] post-exit window completeness (terms in file: %d, exits 1970–%d)\n",
            nrow(tm), max(tm$term_end_year)))

w5  <- window_complete(5)
w10 <- window_complete(10)
for (x in list(list(5, w5), list(10, w10))) {
  k <- x[[1]]; w <- x[[2]]
  cat(sprintf("    +%2d : %3d exits fit coverage | %3d COMPLETE | %d incomplete\n",
              k, nrow(w), sum(w$complete), sum(!w$complete)))
}

n5  <- sum(w5$complete)
n10 <- sum(w10$complete)

verdict <-
  if (n5 >= 100 && n10 >= 60) "PASS — full +10 design viable" else
  if (n5 >= 100)              "PASS (TRUNCATED) — run +5; +10 underpowered" else
                              "FAIL — post-exit windows too sparse"

cat("\n    GATE\n")
cat(sprintf("      +5  complete: %3d  (need >=100)  %s\n", n5,  ifelse(n5  >= 100, "PASS", "FAIL")))
cat(sprintf("      +10 complete: %3d  (need >= 60)  %s\n", n10, ifelse(n10 >=  60, "PASS", "FAIL")))
cat(sprintf("      => %s\n", verdict))

# Incompleteness here is REAL HISTORY, not missing data — but not all of it is
# dissolution, and the distinction matters because only one of the three is a
# state that stopped existing:
#
#   East Germany 1980–81   8/10  merged into DEU in 1990 — genuine state death
#   SFR Yugoslavia 1988–89 3/10  FRY SUSPENDED from the UNGA 1992–2000; the
#                                state persisted but cast no recorded votes
#   Guinea-Bissau 1996–97  8/10  still extant through 2025; lost 2000–01 to the
#                                civil war and 1999 coup (2002 has 3 votes)
#
# Named rather than counted so the paper drops them knowingly. Guinea-Bissau in
# particular must NOT be read as dissolution.
bad <- w10 %>% filter(!complete)
if (nrow(bad)) {
  cat(sprintf("\n    incomplete +10 windows (%d) — real history, not data gaps:\n", nrow(bad)))
  print(as.data.frame(bad %>% select(country_name, term_start_year, term_end_year, n_have)),
        row.names = FALSE)
}

cat(sprintf("\n    successor-state terms: %d | split terms: %d\n",
            sum(!is.na(tm$successor_state) & tm$successor_state != ""),
            sum(tm$split_term, na.rm = TRUE)))

# Partial credit on criterion 4. The full crosswalk (§3) also has to reconcile
# OECD DAC codes, but the join that the GATE depends on is UNSC terms -> UNGA
# ideal points, and that one can be checked now. The request warns that a silent
# NA here can truncate a post-exit window and make a complete event look
# incomplete — so a clean result here is what licenses reading the 253/227 above
# as real rather than as crosswalk attrition.
unmatched <- setdiff(unique(tm$country_text_id), unique(ip$country_text_id))
cat(sprintf("\n    [4a] UNSC term IDs absent from ideal points: %d %s\n",
            length(unmatched),
            if (length(unmatched)) paste0("(", paste(unmatched, collapse = ", "), ")") else "— clean"))
if (length(unmatched)) {
  cat("         ⚠️ window counts above are UNDERSTATED by crosswalk attrition.\n")
}

## criterion 2b — the SECOND outcome has a SHORTER window ---------------------
#
# The gate above is computed on ideal points, which run to 2025. But the paper's
# second outcome is an agreement rate on important votes, built from
# unga_votes — and the roll-call file ends in 2022. Its post-exit windows are
# therefore ~3 years shorter, and an event that is complete for the ideal-point
# outcome can be incomplete for the agreement-rate outcome.
#
# Reported separately rather than folded in, because if the two outcomes are
# co-primary the paper's usable N is the SMALLER of the two, not the headline.
vt <- readRDS(here("data", "processed", "unga_votes.rds"))
v_end <- max(vt$year, na.rm = TRUE)

# ⚠️ 88 rows (0.007%) carry NO country identity at all — country_text_id,
# country_name and COWcode are all NA. Left in, they turn every `==` comparison
# below into NA and the completeness counts silently become NA rather than
# wrong, which is at least loud. Dropped here; reported so the defect is not
# laundered by this script.
n_orphan <- sum(is.na(vt$country_text_id))
have_v <- vt %>% filter(!is.na(country_text_id), !is.na(year)) %>%
  distinct(country_text_id, year)

window_complete_votes <- function(k) {
  tm %>%
    filter(term_end_year + k <= v_end) %>%
    rowwise() %>%
    mutate(n_have = sum(have_v$country_text_id == country_text_id &
                        have_v$year >  term_end_year &
                        have_v$year <= term_end_year + k)) %>%
    ungroup() %>%
    mutate(complete = n_have == k)
}

v5  <- window_complete_votes(5)
v10 <- window_complete_votes(10)

cat(sprintf("\n[2b] SECOND outcome (agreement rate) — roll-call coverage ends %d, not %d\n",
            v_end, end_year))
cat(sprintf("     (dropped %d vote rows with no country identity — %.4f%% of file)\n",
            n_orphan, 100 * n_orphan / nrow(vt)))
cat(sprintf("     +5  complete: %3d   (ideal-point outcome: %3d, delta %+d)\n",
            sum(v5$complete),  n5,  sum(v5$complete)  - n5))
cat(sprintf("     +10 complete: %3d   (ideal-point outcome: %3d, delta %+d)\n",
            sum(v10$complete), n10, sum(v10$complete) - n10))
cat("     If both outcomes are co-primary, the binding N is the smaller figure.\n")

## criterion 3 — aid coverage overlap -----------------------------------------
# "Does the aid series cover the same country-year windows, and from what year
#  does it become dense rather than patchy?"
#
# Density is measured on BILATERAL donor -> BILATERAL recipient flows only.
# Aggregate rows (ALLD, DAC, G7, …) are sums of other rows and would inflate any
# count several times over.
aid_path <- here("data", "processed", "dac_aid_bilateral.rds")
if (!file.exists(aid_path)) {
  cat("\n[3] aid coverage overlap — BLOCKED, deliverable 2.4 not built\n")
} else {
  aid <- readRDS(aid_path) %>%
    filter(donor_type == "bilateral", recipient_type == "bilateral",
           flow_type == "disbursement")

  cat(sprintf("\n[3] aid coverage (DAC2a bilateral disbursements, %d–%d)\n",
              min(aid$year), max(aid$year)))

  # recipients receiving from >=1 donor in a year = "covered"
  dens <- aid %>%
    filter(!is.na(oda_usd_current)) %>%
    group_by(year) %>%
    summarise(recipients = n_distinct(recipient_iso3),
              donors     = n_distinct(donor_iso3), .groups = "drop")
  first_dense <- dens %>% filter(recipients >= 100) %>% slice_min(year, n = 1) %>% pull(year)
  cat(sprintf("    recipients covered: %d (%d) -> %d (%d)\n",
              dens$recipients[1], dens$year[1],
              dens$recipients[nrow(dens)], dens$year[nrow(dens)]))
  cat(sprintf("    becomes DENSE (>=100 recipients/yr) from: %s\n",
              ifelse(length(first_dense), as.character(first_dense), "never")))

  # overlap with the events the gate actually rests on
  aid_cy <- aid %>% filter(!is.na(oda_usd_current)) %>% distinct(recipient_iso3, year)
  ov <- tm %>%
    filter(term_end_year + 5 <= min(end_year, max(aid$year))) %>%
    rowwise() %>%
    mutate(n_aid = sum(aid_cy$recipient_iso3 == country_text_id &
                       aid_cy$year >  term_end_year &
                       aid_cy$year <= term_end_year + 5)) %>%
    ungroup()
  cat(sprintf("    exits with a COMPLETE +5 AID window : %d of %d\n",
              sum(ov$n_aid == 5), nrow(ov)))
  cat(sprintf("    exits with NO post-exit aid at all  : %d\n", sum(ov$n_aid == 0)))
  cat("    (states with zero aid rows are typically DONORS, not recipients —\n")
  cat("     a UNSC member that never received ODA is a real category, not a gap.)\n")
}

cat("\n[4] crosswalk unmatched rows — BLOCKED, §3 crosswalk not built\n\n")
