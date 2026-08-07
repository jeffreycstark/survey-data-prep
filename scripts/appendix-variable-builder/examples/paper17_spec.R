#' Paper 17 (Korea anti-corruption belief decoupling) — multi-survey
#' variable spec for the appendix generator.
#'
#' Paper 17 uses two surveys:
#'   - ABS (Korea + cross-country comparisons, W1-W6)
#'   - KIPA Anti-Corruption Survey (specialty sample: corporate employees
#'     + self-employed with gov-business contact, 2004-2023)
#'
#' Variable lists extracted from analysis/00_data_preparation.qmd (ABS,
#' `keep_cols` block) and analysis/03_kipa_triangulation.qmd (KIPA, two
#' focal items: corr_bribery_experience_1yr + corr_prevalence_perception).

paper17_abs_groups <- list(
  "Corruption (focal measures)" = c(
    corrupt_witnessed     = "Personal/known witnessed corruption (focal experiential measure)",
    corrupt_national_govt = "Perceived corruption: national government",
    corrupt_local_govt    = "Perceived corruption: local government",
    govt_anticorrupt_effort = "Perceived government anti-corruption effort"
  ),
  "Trust controls" = c(
    trust_national_government = "Trust in national government",
    trust_courts              = "Trust in the courts",
    trust_police              = "Trust in the police"
  ),
  "Demographics (raw source items)" = c(
    age             = "Age",
    education_level = "Education level",
    gender          = "Gender",
    urban_rural     = "Urban / rural residence"
  )
)

paper17_abs_intro <- paste(
  "ABS provides the cross-country baseline for the experiential vs.",
  "institutional corruption-perception comparison. Korea is the focal",
  "country; secondary cross-country comparisons use all ABS-fielded waves",
  "(W1-W6, 2003-2022). Coverage and harmonization notes per variable are",
  "shown below."
)

paper17_kipa_groups <- list(
  "Corruption (focal Korean specialty-sample measures)" = c(
    corr_prevalence_perception   = "Perceived prevalence of corruption among public officials",
    corr_bribery_experience_1yr  = "Personal bribery experience in the past year (respondent or business)"
  )
)

paper17_kipa_intro <- paste0(
  "The KIPA Anti-Corruption Survey is a specialty-sample annual instrument ",
  "fielded by the Korea Institute of Public Administration since 2004. ",
  "**It is NOT a general-population survey** — respondents are corporate ",
  "employees and self-employed individuals with regular contact with public ",
  "officials. The sample is therefore selected on the basis of higher ",
  "exposure to bribery solicitation than the general public. KIPA results ",
  "in this paper triangulate the ABS Korea findings rather than serve as a ",
  "stand-alone trend series.\n\n",
  "**Coverage caveat for `corr_bribery_experience_1yr`:** the bribery-",
  "experience item is harmonized 2004–2021; the 2022 and 2023 waves ",
  "restructured the question and are dropped from the harmonized series. ",
  "The perceived-prevalence item `corr_prevalence_perception` is ",
  "harmonized across the full 2004–2023 window."
)

paper17_surveys <- list(
  abs = list(
    survey    = "abs",
    sub_label = "A2. ABS variable wording and coding",
    groups    = paper17_abs_groups,
    intro     = paper17_abs_intro
  ),
  kipa = list(
    survey    = "kipa_corruption",
    sub_label = "A3. KIPA variable wording and coding",
    groups    = paper17_kipa_groups,
    intro     = paper17_kipa_intro
  )
)

paper17_intro <- paste(
  "This appendix documents the two survey instruments used in the analysis.",
  "**Section A1** lists the Asian Barometer Survey (ABS) items, which",
  "provide the cross-country baseline for the experiential vs. institutional",
  "corruption-perception comparison.",
  "**Section A2** lists the Korea Institute of Public Administration (KIPA)",
  "Anti-Corruption Survey items, a specialty-sample Korean annual instrument",
  "used to triangulate the ABS Korea findings.",
  "Per-wave question IDs, verbatim question text, and harmonization details",
  "are auto-generated from the centralized verbatim dictionary in the",
  "survey-data-prep harmonization pipeline."
)
