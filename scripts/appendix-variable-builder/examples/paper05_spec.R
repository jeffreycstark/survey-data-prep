#' Paper 05 (Thailand Trust Collapse) — variable spec for the appendix
#' generator.
#'
#' Mirrors the 4 topical groupings in the hand-written tribble at
#' `manuscript/05-borrowed-legitimacy-online-appendix.qmd` lines 102-125.
#' Paper 05 uses 15 raw ABS items (6-item trust battery + dem
#' satisfaction + econ + 3 auth alternatives + 4 demographic source vars).
#'
#' Derived/composite variables (`reject_*`, `trust_political`,
#' `trust_nonpolitical`, `trust_all`, `age_centered`, `female`,
#' `education_z`, `is_urban`) are documented inline in the display name —
#' the underlying raw ABS item is what gets the verbatim entry.

paper05_groups <- list(
  "Institutional Trust (Q7 battery)" = c(
    trust_national_government = "Trust in national government",
    trust_parliament          = "Trust in parliament",
    trust_political_parties   = "Trust in political parties",
    trust_courts              = "Trust in the courts",
    trust_military            = "Trust in the military",
    trust_police              = "Trust in the police"
  ),
  "Performance and Satisfaction" = c(
    democracy_satisfaction = "Satisfaction with democracy",
    econ_national_now      = "Economic evaluation (national, now)"
  ),
  "Authoritarian Regime Alternatives" = c(
    military_rule     = "Approval of military rule (also entered as `reject_military` = 5 - military_rule)",
    strongman_rule    = "Approval of strongman rule (also entered as `reject_strongman` = 5 - strongman_rule)",
    single_party_rule = "Approval of single-party rule (also entered as `reject_single_party` = 5 - single_party_rule)"
  ),
  "Demographics (raw source items)" = c(
    age             = "Age (raw years; entered as `age_centered` = age − sample mean)",
    gender          = "Gender (raw; recoded as `female` = 1 if gender == 2, else 0)",
    education_level = "Education (raw years; entered as `education_z` = standardized z-score)",
    urban_rural     = "Urban / rural residence (raw; recoded as `is_urban` = 1 if urban_rural == 1, else 0)"
  )
)

paper05_intro <- paste(
  "This appendix documents the verbatim ABS question wording, response",
  "scales, and per-wave question IDs for the 15 raw items used in the",
  "analysis. The institutional-trust battery (`trust_*`, six items) is",
  "ABS Q7, asked identically across all six waves; the harmonization",
  "engine handles per-wave scale corrections so the analysis variable is",
  "consistently 1-4 with higher = more trust. **Derived analytical",
  "variables** include `reject_military`, `reject_strongman`,",
  "`reject_single_party` (each computed as 5 - raw approval, so higher =",
  "more rejection of that authoritarian alternative), `reject_authoritarian`",
  "(mean of the three rejection items), `trust_political` / `trust_nonpolitical` /",
  "`trust_all` (composite means of subsets of the trust battery),",
  "`age_centered` (age - sample mean), `female` (binary from gender),",
  "`education_z` (z-scored years of education), and `is_urban` (binary from",
  "urban_rural). Country sample: Thailand, Philippines, Taiwan."
)
