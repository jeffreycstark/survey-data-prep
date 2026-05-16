#' Human-readable harmonization notes
#'
#' Maps recode function names (used in YAML harmonize.fn fields) to short
#' English sentences suitable for inclusion in an Appendix A entry.
#'
#' Unknown function names fall through to a generic
#' "Custom transformation: <fn_name>." sentence so the generator never
#' silently drops information.

recode_note_table <- list(
  identity                       = "Used as-is.",
  safe_reverse_3pt               = "Reverse-coded so higher values indicate more of the construct.",
  safe_reverse_4pt               = "Reverse-coded so higher values indicate more of the construct.",
  safe_reverse_5pt               = "Reverse-coded so higher values indicate more of the construct.",
  safe_reverse_6pt               = "Reverse-coded so higher values indicate more of the construct.",
  safe_reverse_2pt               = "Reverse-coded so higher values indicate more of the construct.",
  safe_3pt_none                  = "Missing-value codes converted to NA; otherwise used as-is.",
  safe_4pt_none                  = "Missing-value codes converted to NA; otherwise used as-is.",
  safe_5pt_none                  = "Missing-value codes converted to NA; otherwise used as-is.",
  safe_6pt_none                  = "Missing-value codes converted to NA; otherwise used as-is.",
  safe_identify_4pt              = "Out-of-range values converted to NA; otherwise used as-is.",
  safe_6pt_to_4pt                = "Collapsed from 6-point to 4-point scale.",
  collapse_6pt_to_4pt_reverse    = "Collapsed from 6-point to 4-point scale and reverse-coded.",
  collapse_5pt_to_4pt_then_reverse = "Collapsed from 5-point to 4-point scale and reverse-coded.",
  recode_6pt_freq_to_4pt         = "Collapsed from 6-point frequency scale to 4-point.",
  collapse_10pt_to_6pt           = "Collapsed from 10-point to 6-point scale.",
  recode_10pt_to_4pt             = "Collapsed from 10-point to 4-point scale (bins 1-2, 3-5, 6-7, 8-10).",
  collapse_middle5_to_4pt        = "Middle category collapsed to produce a 4-point scale.",
  recode_binary_yes_no           = "Dichotomized: 1 = yes/affirmative, 0 = no/negative.",
  recode_has_party               = "Dichotomized: 1 = has party identification, 0 = none.",
  recode_witnessed_default       = "Dichotomized: 1 = witnessed corruption, 0 = did not witness.",
  recode_w3_witnessed            = "Dichotomized: 1 = witnessed corruption (incl. through household member), 0 = did not witness.",
  recode_w4_witnessed            = "Dichotomized: 1 = any witnessing (self, family, or friend), 0 = none.",
  recode_w6_corruption           = "Extra 'no one involved' category collapsed to 'hardly anyone'; otherwise used as-is.",
  recode_dev_model_w3_w4_w6      = "Recoded to align development-model item across waves.",
  recode_dev_model_w5            = "Recoded to align development-model item with W3/W4/W6 coding.",
  recode_w2_anticorrupt          = "W2 wording mapped to the W3+ anti-corruption scale.",
  recode_0_3_to_1_4              = "Shifted from 0-3 to 1-4 scale.",
  collapse_influence_country_to_5 = "Collapsed to 5-point country-influence scale.",
  middle_identity_5pt            = "5-point scale: midpoint preserved at 3.",
  middle_reverse_5pt             = "5-point scale: midpoint preserved at 3 and direction reversed.",
  recode_kamos_gender_w1         = "W1 gender coding aligned with later waves."
)

#' Look up a harmonization function and return a human-readable note.
#'
#' @param fn_name Character: function name from a YAML harmonize.fn field.
#' @return One-sentence English description.
recode_note <- function(fn_name) {
  if (is.null(fn_name) || is.na(fn_name) || fn_name == "") {
    return(NA_character_)
  }
  if (!is.null(recode_note_table[[fn_name]])) {
    return(recode_note_table[[fn_name]])
  }
  paste0("Custom transformation: `", fn_name, "()`.")
}
