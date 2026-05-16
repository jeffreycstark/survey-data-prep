#' Paper 04 (Cambodia Fairy Tale) — variable spec for the appendix
#' generator.
#'
#' Mirrors the 11 domain groupings and 39 variables defined in the
#' hand-written `cd-online-appendix.qmd` Appendix A code chunk (lines
#' 158-194 of cd-online-appendix.qmd).
#'
#' Note: Cambodia is not in ABS W1 or W5, so all variables here render
#' with the QID grid limited to W2/W3/W4/W6 (where each variable is
#' actually fielded for Cambodia). The generator's QID grid reflects the
#' YAML source map, which covers all waves the item was fielded *anywhere*;
#' paper 04 supplementary text should clarify the Cambodia-specific
#' coverage.

paper04_groups <- list(
  "Political Participation" = c(
    gate_contact_influential   = "Contacted influential person",
    gate_contact_elected       = "Contacted elected official",
    gate_contact_civil_servant = "Contacted civil servant",
    gate_petition              = "Signed a petition",
    gate_demonstration         = "Attended a demonstration",
    gate_contact_media         = "Contacted media",
    community_leader_contact   = "Contacted community leader",
    voted_last_election        = "Voted in last election"
  ),
  "Authoritarian Governance Preferences" = c(
    single_party_rule = "Single-party rule",
    strongman_rule    = "Strong leader rule",
    military_rule     = "Military rule",
    expert_rule       = "Expert (technocratic) rule"
  ),
  "Democratic Commitment & Satisfaction" = c(
    dem_always_preferable  = "Democracy always preferable",
    dem_best_form          = "Democracy is the best form of government",
    dem_vs_equality        = "Democracy vs. economic equality tradeoff",
    democracy_satisfaction = "Satisfaction with democracy"
  ),
  "Democratic Expectations" = c(
    dem_country_future       = "Future democracy rating (10 years out)",
    dem_country_past         = "Past democracy rating (10 years ago)",
    dem_country_present_govt = "Present democracy rating"
  ),
  "Corruption" = c(
    corrupt_witnessed     = "Personal/known witnessed corruption",
    corrupt_national_govt = "Perceived corruption: national government",
    corrupt_local_govt    = "Perceived corruption: local government"
  ),
  "Media & Political Interest" = c(
    political_interest = "Interest in politics",
    pol_news_follow    = "Frequency of following political news",
    pol_discuss        = "Frequency of political discussion",
    news_internet      = "Internet news consumption"
  ),
  "Freedom Perceptions" = c(
    dem_free_speech      = "Freedom of speech",
    gov_free_to_organize = "Freedom to organize"
  ),
  "Placebo Battery (Non-Political)" = c(
    nat_proud_citizen        = "National pride",
    econ_family_now          = "Family economic condition (now)",
    econ_change_1yr          = "Change in family economic condition (past year)",
    trust_generalized_binary = "Generalized social trust (binary)"
  ),
  "Partisan Identity" = c(
    voted_winning_losing = "Voted for winning or losing party (Cambodia-specific construction)"
  ),
  "International Orientation" = c(
    intl_china_asia_goodharm    = "China's influence on Asia: good or harmful",
    intl_future_influence_asia  = "Future leading influence in Asia"
  ),
  "Demographics" = c(
    age             = "Age",
    gender          = "Gender",
    education_level = "Education level",
    urban_rural     = "Urban / rural residence"
  )
)

paper04_intro <- paste(
  "This appendix documents the verbatim question wording, response scales, and",
  "per-wave question IDs for the 39 ABS items used in the analysis. Question IDs",
  "vary across waves; the **Wave QIDs** line for each variable lists the raw",
  "question number in every ABS wave for which the item was fielded.",
  "**Cambodia coverage caveat:** the Cambodia ABS panel covers Waves 2, 3, 4,",
  "and 6 only (Cambodia was not surveyed in W1 or W5). Some items show QIDs",
  "for waves Cambodia did not field; consult Table A2 (sample sizes) for",
  "Cambodia-specific wave availability."
)
