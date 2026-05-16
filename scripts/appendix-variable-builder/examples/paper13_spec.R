#' Paper 13 (Authoritarian Attraction) — variable spec for the appendix
#' generator. Mirrors the hand-written `aa-online-appendix.qmd` "Survey
#' Items" section so that running build_appendix() on this spec produces
#' (approximately) the same content.
#'
#' Source: paper-bank/papers/13_authoritarian_attraction/manuscript/aa-online-appendix.qmd

paper13_groups <- list(
  "Dependent Variable: Authoritarian Openness Scale" = c(
    strongman_rule     = "Strong Leader",
    military_rule      = "Military Rule",
    single_party_rule  = "Single-Party Rule"
  ),
  "Performance Controls" = c(
    democracy_satisfaction    = "Democratic Satisfaction",
    trust_national_government = "Trust in National Government",
    corrupt_national_govt     = "Corruption Perceptions",
    econ_national_now         = "Economic Evaluation"
  ),
  "Nostalgia Mechanism" = c(
    dem_country_past         = "Past Democracy Rating",
    dem_country_present_govt = "Present Democracy Rating"
  ),
  "Democratic Orientation (Replication Tables)" = c(
    dem_always_preferable = "Democracy Always Preferable",
    democracy_suitability = "Democracy Suitability",
    democracy_efficacy    = "Democracy Efficacy"
  ),
  "Liberal Values (Replication Tables)" = c(
    auth_govt_censor_ideas      = "Free Speech (`liberal_freespeech` after reversal)",
    auth_judges_defer_executive = "Judicial Independence (`liberal_judiciary` after reversal)"
  )
)

paper13_intro <- paste(
  "This section documents the verbatim question wording, response scales,",
  "and wave-specific question IDs for all survey items used in the analysis.",
  "Items are drawn from the Asian Barometer Survey (ABS); question IDs vary",
  "by wave. The harmonized variable name used in the analysis dataset is",
  "given in parentheses after each item heading."
)
