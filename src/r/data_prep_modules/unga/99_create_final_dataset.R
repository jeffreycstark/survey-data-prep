# UNGA: Bailey-Strezhnev-Voeten ideal points + roll-call votes
#
# Deliverables 2.1 and 2.2 of paper-bank 24 (papers/24-unsc/DATA-REQUEST.md).
# Country-year / vote-level MACRO panels — NOT surveys. No YAML harmonize spec,
# no verbatim question dictionary. Follows the V-Dem precedent.
#
# Output:
#   data/processed/unga_idealpoints.{rds,parquet}   country × year
#   data/processed/unga_votes.{rds,parquet}         country × roll-call
#
# ─────────────────────────────────────────────────────────────────────────────
# ⚠️ PROVENANCE: the two files come from DIFFERENT VERSIONS of one deposit
# ─────────────────────────────────────────────────────────────────────────────
# DOI 10.7910/DVN/LEJUQZ ("United Nations General Assembly Ideal Points") is
# VERIFIED as the right deposit — but the request's §2.2 assumption that
# roll-call data ships in the *same* deposit version is no longer true:
#
#   ideal points -> v38.0 (2026-04-03), Idealpointestimates1946-2025.tab
#   roll-calls   -> v33.0 (2024-06-24), UNVotes-1.RData
#
# The UNVotes file was present in versions 31-33 and was REMOVED by v38. There
# is no current-version roll-call file. The paper must cite both versions.
#
# Coverage consequence: ideal points run to 2025, roll-calls only to 2022.
# Any outcome built from votes is censored 3 years earlier than one built from
# ideal points. This is NOT a bug to fix downstream — it is a property of the
# source and must be reported.

library(here)
suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
})

IDEALPOINT_VERSION <- "doi:10.7910/DVN/LEJUQZ v38.0 (2026-04-03)"
VOTES_VERSION      <- "doi:10.7910/DVN/LEJUQZ v33.0 (2024-06-24), UNVotes-1.RData"

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)

# ── 2.1 Ideal points ────────────────────────────────────────────────────────
ip_raw <- read.delim(
  here("data", "unga", "raw", "dvn_lejuqz_v38", "Idealpointestimates1946-2025.tab"),
  sep = "\t", stringsAsFactors = FALSE, check.names = FALSE)

# ⚠️ The release ships posterior QUANTILES, not a standard error. The request
# (§2.1) explicitly asked us to say so rather than silently drop it. We keep all
# five quantiles AND derive a normal-approximation SE from the central 90%
# interval: for an approximately normal posterior, sd ~= (Q95 - Q5)/(2*1.645).
# It is named _derived so nobody mistakes it for a shipped posterior SD.
ip <- ip_raw %>%
  transmute(
    country_text_id = iso3c,
    COWcode         = as.integer(ccode),
    country_name    = Countryname,
    year            = as.integer(year),
    ideal_point     = as.numeric(IdealPointFP),
    ideal_point_q5  = as.numeric(`Q5%FP`),
    ideal_point_q10 = as.numeric(`Q10%FP`),
    ideal_point_q50 = as.numeric(`Q50%FP`),
    ideal_point_q90 = as.numeric(`Q90%FP`),
    ideal_point_q95 = as.numeric(`Q95%FP`),
    ideal_point_se_derived = (as.numeric(`Q95%FP`) - as.numeric(`Q5%FP`)) / (2 * qnorm(0.95)),
    n_votes         = as.integer(NVotesFP)
  ) %>%
  arrange(country_text_id, year)

# ── 2.2 Roll-call votes ─────────────────────────────────────────────────────
e <- new.env()
load(here("data", "unga", "raw", "dvn_lejuqz_v33_votes", "UNVotes-1.RData"), envir = e)
votes_raw <- get("completeVotes", envir = e)

# ⚠️ vote_raw is KEPT. The request is explicit: the not-member (9) vs absent (8)
# distinction is substantive for this design and must NOT collapse into NA.
votes <- votes_raw %>%
  transmute(
    rcid, session = as.integer(session), year = as.integer(year), date,
    country_text_id = as.character(Country),
    COWcode         = as.integer(ccode),
    country_name    = Countryname,
    vote_raw        = as.integer(vote),
    vote = factor(vote, levels = c(1, 2, 3, 8, 9),
                  labels = c("yes", "abstain", "no", "absent", "not_member")),
    important_vote = as.integer(importantvote),
    issue_me = me, issue_nu = nu, issue_di = di,
    issue_hr = hr, issue_co = co, issue_ec = ec,
    unres, short, descr
  )

# ── Agreement rates with the P3 ─────────────────────────────────────────────
# The request lists pct_agree_us / _china / _russia in deliverable 2.1. Those
# live in the deposit's AgreementScores files (145 MB). They are DERIVED here
# from the roll-call data instead: identical construction, no extra download,
# and fully transparent. Denominator = votes where BOTH states cast a
# substantive vote (yes/abstain/no); absent and not-member are excluded.
substantive <- c("yes", "abstain", "no")
partner_cow <- c(us = 2, russia = 365, china = 710)

agree_one <- function(cow, label) {
  p <- votes %>%
    filter(COWcode == cow, vote %in% substantive) %>%
    select(rcid, partner_vote = vote)
  votes %>%
    filter(vote %in% substantive) %>%
    inner_join(p, by = "rcid") %>%
    filter(COWcode != cow) %>%
    group_by(country_text_id, year) %>%
    summarise(!!paste0("pct_agree_", label) := mean(vote == partner_vote),
              .groups = "drop")
}

for (nm in names(partner_cow)) {
  ip <- ip %>% left_join(agree_one(partner_cow[[nm]], nm),
                         by = c("country_text_id", "year"))
}

attr(ip, "source_version")    <- IDEALPOINT_VERSION
attr(ip, "se_note")           <- "No posterior SD in release; ideal_point_se_derived = (Q95-Q5)/(2*1.645)."
attr(ip, "agreement_note")    <- "pct_agree_* DERIVED from roll-calls (v33), so present only through 2022."
attr(votes, "source_version") <- VOTES_VERSION

saveRDS(ip, here("data", "processed", "unga_idealpoints.rds"))
write_parquet(ip, here("data", "processed", "unga_idealpoints.parquet"))
saveRDS(votes, here("data", "processed", "unga_votes.rds"))
write_parquet(votes, here("data", "processed", "unga_votes.parquet"))

cat("\n── unga_idealpoints ──\n")
cat(sprintf("  %s rows | %d countries | %d–%d\n", format(nrow(ip), big.mark=","),
            n_distinct(ip$country_text_id), min(ip$year), max(ip$year)))
cat(sprintf("  ⚠️ COVERAGE END YEAR (acceptance criterion #1): %d\n", max(ip$year)))
cat(sprintf("  ideal_point_se_derived: median %.3f (no shipped posterior SD)\n",
            median(ip$ideal_point_se_derived, na.rm = TRUE)))
cat(sprintf("  pct_agree_us non-missing: %.1f%% (censored at %d — votes vintage)\n",
            100*mean(!is.na(ip$pct_agree_us)), max(votes$year, na.rm = TRUE)))

cat("\n── unga_votes ──\n")
cat(sprintf("  %s rows | %d roll-calls | %d–%d\n", format(nrow(votes), big.mark=","),
            n_distinct(votes$rcid), min(votes$year, na.rm=TRUE), max(votes$year, na.rm=TRUE)))
cat(sprintf("  important votes: %s\n", format(sum(votes$important_vote == 1, na.rm=TRUE), big.mark=",")))
print(table(votes$vote, useNA = "ifany"))

# ── Freshness manifest ──────────────────────────────────────────────────────
# specs = character(): not a survey, no YAML harmonize specs.
# engine = this module's own script, NOT the shared harmonize engine — nothing
# here calls harmonize_all() or recoding.R, so recording those would mark this
# module STALE on every unrelated recoding.R edit.
#
# ⚠️ The two raw inputs are DIFFERENT DEPOSIT VERSIONS (ideal points v38,
# roll-calls v33 — see the header). Hashing both means a re-pull of either
# vintage is caught.
source(here("src", "r", "utils", "provenance.R"))
write_manifest(
  survey  = "unga",
  inputs  = Filter(file.exists, c(
    here("data", "unga", "raw", "dvn_lejuqz_v38", "Idealpointestimates1946-2025.tab"),
    here("data", "unga", "raw", "dvn_lejuqz_v33_votes", "UNVotes-1.RData"))),
  specs   = character(),
  outputs = Filter(file.exists, c(
    here("data", "processed", "unga_idealpoints.rds"),
    here("data", "processed", "unga_idealpoints.parquet"),
    here("data", "processed", "unga_votes.rds"),
    here("data", "processed", "unga_votes.parquet"))),
  engine  = "src/r/data_prep_modules/unga/99_create_final_dataset.R"
)
cat("\n  -> manifest:", here("outputs", "unga", "manifest.json"), "\n")
