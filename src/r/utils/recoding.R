# R/recoding.R
# Recoding functions for Asian Barometer analysis

# Private helper: validate variable label against expected semantic patterns.
# Called by safe_reverse_*pt(), safe_*pt_none(), and no_verify() before recoding.
.validate_semantic_label <- function(validate_all, data, var_name) {
  if (is.null(validate_all)) return(invisible(NULL))
  if (is.null(data) || is.null(var_name)) {
    stop("❌ validate_all requires both `data` and `var_name`")
  }
  if (!var_name %in% names(data)) {
    stop(glue::glue("❌ {var_name}: variable not found in data"))
  }
  qtext <- attr(data[[var_name]], "label")
  if (is.null(qtext) || is.na(qtext) || !nzchar(qtext)) {
    stop(glue::glue("❌ {var_name}: missing question label for validation"))
  }
  for (pattern in validate_all) {
    if (!grepl(pattern, qtext, ignore.case = TRUE)) {
      stop(glue::glue(
        "❌ {var_name}: expected concept '{pattern}' not found in question text:\n'{qtext}'"
      ))
    }
  }
  invisible(NULL)
}

# Internal helper for the safe_*pt family.
# Public wrappers (safe_reverse_Npt, safe_Npt_none) keep their names because
# YAML specs reference them via `fn:` and harmonize.R looks them up by name.
.safe_npt <- function(x,
                      n,
                      reverse,
                      data = NULL,
                      var_name = NULL,
                      missing_codes,
                      validate_all = NULL) {
  .validate_semantic_label(validate_all, data, var_name)
  dplyr::case_when(
    x %in% seq_len(n)     ~ if (reverse) (n + 1) - x else as.numeric(x),
    x %in% missing_codes  ~ NA_real_,
    TRUE                  ~ NA_real_
  )
}

safe_reverse_3pt <- function(x,
                              data = NULL,
                              var_name = NULL,
                              missing_codes = c(-1, 0, 7, 8, 9),
                              validate_all = NULL) {
  .safe_npt(x, n = 3, reverse = TRUE,
            data = data, var_name = var_name,
            missing_codes = missing_codes, validate_all = validate_all)
}

safe_reverse_4pt <- function(x,
                              data = NULL,
                              var_name = NULL,
                              missing_codes = c(-1, 0, 7, 8, 9),
                              validate_all = NULL) {
  .safe_npt(x, n = 4, reverse = TRUE,
            data = data, var_name = var_name,
            missing_codes = missing_codes, validate_all = validate_all)
}

reverse_trust_vietnam_w2 <- function(x,
                                     data = NULL,
                                     var_name = NULL,
                                     validate_all = NULL) {
  if (is.null(data) || !"country" %in% names(data)) {
    stop("❌ reverse_trust_vietnam_w2 requires `data$country`")
  }

  country <- data$country
  if (inherits(country, "haven_labelled")) {
    country <- haven::zap_labels(country)
  }
  country <- suppressWarnings(as.numeric(country))

  out <- x
  idx <- !is.na(out) & country == 11
  out[idx] <- 5 - out[idx]
  out
}

reverse_trust_vietnam_w3 <- function(x,
                                     data = NULL,
                                     var_name = NULL,
                                     validate_all = NULL) {
  if (is.null(data) || !"country" %in% names(data)) {
    stop("❌ reverse_trust_vietnam_w3 requires `data$country`")
  }

  country <- data$country
  if (inherits(country, "haven_labelled")) {
    country <- haven::zap_labels(country)
  }
  country <- suppressWarnings(as.numeric(country))

  out <- x
  idx <- !is.na(out) & country != 11
  out[idx] <- 5 - out[idx]
  out
}

safe_reverse_5pt <- function(x,
                              data = NULL,
                              var_name = NULL,
                              missing_codes = c(-1, 0, 7, 8, 9),
                              validate_all = NULL) {
  .safe_npt(x, n = 5, reverse = TRUE,
            data = data, var_name = var_name,
            missing_codes = missing_codes, validate_all = validate_all)
}

# ==============================================================================
# IDENTITY FUNCTIONS (NO REVERSAL, ONLY MISSING CODE HANDLING)
# ==============================================================================

safe_3pt_none <- function(x,
                           data = NULL,
                           var_name = NULL,
                           missing_codes = c(-1, 0, 7, 8, 9),
                           validate_all = NULL) {
  .safe_npt(x, n = 3, reverse = FALSE,
            data = data, var_name = var_name,
            missing_codes = missing_codes, validate_all = validate_all)
}

safe_4pt_none <- function(x,
                           data = NULL,
                           var_name = NULL,
                           missing_codes = c(-1, 0, 7, 8, 9),
                           validate_all = NULL) {
  .safe_npt(x, n = 4, reverse = FALSE,
            data = data, var_name = var_name,
            missing_codes = missing_codes, validate_all = validate_all)
}

safe_5pt_none <- function(x,
                           data = NULL,
                           var_name = NULL,
                           missing_codes = c(-1, 0, 7, 8, 9),
                           validate_all = NULL) {
  .safe_npt(x, n = 5, reverse = FALSE,
            data = data, var_name = var_name,
            missing_codes = missing_codes, validate_all = validate_all)
}

# ==============================================================================
# 6-POINT SCALE FUNCTIONS
# Wider missing-code default reflects ABS conventions for 6-pt batteries
# ==============================================================================

safe_reverse_6pt <- function(x,
                              data = NULL,
                              var_name = NULL,
                              missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                              validate_all = NULL) {
  .safe_npt(x, n = 6, reverse = TRUE,
            data = data, var_name = var_name,
            missing_codes = missing_codes, validate_all = validate_all)
}

safe_6pt_none <- function(x,
                           data = NULL,
                           var_name = NULL,
                           missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                           validate_all = NULL) {
  .safe_npt(x, n = 6, reverse = FALSE,
            data = data, var_name = var_name,
            missing_codes = missing_codes, validate_all = validate_all)
}

# ==============================================================================
# 6-POINT TO 4-POINT COLLAPSE (FOR ABS WAVE 5)
# ==============================================================================

safe_6pt_to_4pt <- function(x,
                             data = NULL,
                             var_name = NULL,
                             missing_codes = c(-1, 0, 97, 98, 99),
                             needs_reversal = TRUE,
                             validate_all = NULL) {
  #' Collapse 6-point scale to 4-point (for ABS Wave 5)
  #'

  #' This function handles Wave 5's 6-point trust scale and collapses it to 4-point
  #' to match other waves.
  #'
  #' Wave 5 scale (before reversal):
  #'   1=Trust fully, 2=Trust a lot, 3=Trust somewhat,
  #'   4=Distrust somewhat, 5=Distrust a lot, 6=Distrust fully
  #'
  #' After reversal (if needs_reversal=TRUE):
  #'   6=Trust fully, 5=Trust a lot, 4=Trust somewhat,
  #'   3=Distrust somewhat, 2=Distrust a lot, 1=Distrust fully
  #'
  #' Collapse to 4-point:
  #'   6,5 → 4 (A great deal of trust)
  #'   4   → 3 (Quite a lot of trust)
  #'   3   → 2 (Not very much trust)
  #'   2,1 → 1 (None at all)

  # ---- semantic validation (optional but recommended) ----
  .validate_semantic_label(validate_all, data, var_name)

  # ---- first handle missing codes ----
  x_clean <- dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    TRUE ~ x
  )

  # ---- if needs reversal, reverse first ----
  # Wave 5 is coded 1=high trust, 6=low trust, so we reverse to match other waves
  if (needs_reversal) {
    x_clean <- dplyr::case_when(
      !is.na(x_clean) ~ 7 - x_clean,
      TRUE ~ NA_real_
    )
  }

  # ---- collapse 6-point to 4-point ----
  # After reversal: 6,5=highest trust -> 4
  #                 4=moderate-high -> 3
  #                 3=moderate-low -> 2
  #                 2,1=lowest trust -> 1
  dplyr::case_when(
    x_clean %in% c(6, 5) ~ 4,
    x_clean == 4 ~ 3,
    x_clean == 3 ~ 2,
    x_clean %in% c(2, 1) ~ 1,
    TRUE ~ NA_real_
  )
}

#' Recode 6-point frequency scale to 4-point (W4 social media frequency)
#'
#' W4 scale:
#'   1=Everyday, 2=Several times a week, 3=Once or twice a week,
#'   4=A few times a month, 5=A few times a year, 6=Practically never
#'
#' Target 4-point scale (higher = more frequent):
#'   4=Often (1-2), 3=Sometimes (3-4), 2=Seldom (5), 1=Never (6)
recode_6pt_freq_to_4pt <- function(x,
                                  missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                                  ...) {
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% c(1, 2) ~ 4,
    x %in% c(3, 4) ~ 3,
    x == 5 ~ 2,
    x == 6 ~ 1,
    TRUE ~ NA_real_
  )
}

# ==============================================================================
# PARTY IDENTIFICATION FUNCTIONS
# ==============================================================================

recode_has_party <- function(x,
                              data = NULL,
                              var_name = NULL,
                              missing_codes = c(-1, 0, 97, 98, 99),
                              validate_all = NULL) {
  #' Recode party ID to binary has_party indicator
  #'
  #' Converts party identification variable to binary:
  #'   - 90, 1595, 1597 (no party codes) -> 0
  #'   - Other valid party codes -> 1
  #'   - Missing codes -> NA

  # ---- semantic validation (optional but recommended) ----
  .validate_semantic_label(validate_all, data, var_name)

  # No party codes: 90 = "Don't feel close to any political party"
  # Some waves may use country-specific "no party" codes (1595, 1597)
  no_party_codes <- c(90, 1595, 1597)

  # ---- recode to binary ----
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% no_party_codes ~ 0,
    x > 0 ~ 1,
    TRUE ~ NA_real_
  )
}

# ==============================================================================
# MIDDLE-VALUE 5-POINT SCALE FUNCTIONS
# ==============================================================================
# For scales where value 5 is coded as middle response (e.g., "neither agree
# nor disagree", "both equally important") but needs to be placed at the
# semantic center of the scale.
#
# Original coding: 1, 2, 3, 4 = endpoints/moderate, 5 = middle
# Semantic order:  1 < 2 < 5 (middle) < 3 < 4
#
# These functions remap so 5 becomes position 3 (center of 5-point scale)

middle_identity_5pt <- function(x,
                                 data = NULL,
                                 var_name = NULL,
                                 missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                                 validate_all = NULL) {
  #' Remap 5-point scale with middle value at position 5 to center

  #'

  #' For scales where:
  #'   1 = one extreme (e.g., "Strongly disagree" or "Development much more important")
  #'   2 = moderate (e.g., "Disagree" or "Development somewhat more important")
  #'   3 = moderate other direction (e.g., "Agree" or "Democracy somewhat more important")
  #'   4 = other extreme (e.g., "Strongly agree" or "Democracy much more important")
  #'   5 = middle/neutral (e.g., "Neither" or "Both equally important")
  #'
  #' Remaps to: 1→1, 2→2, 5→3, 3→4, 4→5
  #' So semantic order becomes: 1 < 2 < 3 (was 5) < 4 (was 3) < 5 (was 4)

  # ---- semantic validation (optional but recommended) ----
  .validate_semantic_label(validate_all, data, var_name)

  # ---- remap with middle value (5) moved to center (3) ----
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,
    x == 2 ~ 2,
    x == 5 ~ 3,
    x == 3 ~ 4,
    x == 4 ~ 5,
    TRUE ~ NA_real_
  )
}

middle_reverse_5pt <- function(x,
                                data = NULL,
                                var_name = NULL,
                                missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                                validate_all = NULL) {
  #' Reverse 5-point scale with middle value at position 5
  #'
  #' For scales where:
  #'   1 = one extreme (e.g., "Strongly agree" - HIGH on construct)
  #'   2 = moderate (e.g., "Agree")
  #'   3 = moderate other direction (e.g., "Disagree")
  #'   4 = other extreme (e.g., "Strongly disagree" - LOW on construct)
  #'   5 = middle/neutral (e.g., "Neither agree nor disagree")
  #'
  #' Reverses AND remaps: 1→5, 2→4, 5→3, 3→2, 4→1
  #' So original high (1) becomes low (5), and middle stays at center (3)

  # ---- semantic validation (optional but recommended) ----
  .validate_semantic_label(validate_all, data, var_name)

  # ---- reverse with middle value (5) staying at center (3) ----
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 5,
    x == 2 ~ 4,
    x == 5 ~ 3,
    x == 3 ~ 2,
    x == 4 ~ 1,
    TRUE ~ NA_real_
  )
}

# ==============================================================================
# WAVE-SPECIFIC RECODING FUNCTIONS (Added 2025-01-10)
# ==============================================================================
# These functions handle specific cross-wave harmonization issues identified
# during codebook verification.

# ------------------------------------------------------------------------------
# SOCIAL TRUST: Binary trust question recodes
# ------------------------------------------------------------------------------

recode_w1_trust_binary <- function(x,
                                    missing_codes = c(-1, 0, 97, 98, 99),
                                    ...) {
  #' Recode Wave 1 generalized trust (q024) to binary
  #'
  #' Wave 1 has 3 categories:
  #'   1 = "One can't be too careful in dealing with them" -> 2 (careful)
  #'   2 = "Most people can be trusted" -> 1 (trusted)
  #'   3 = "Both" -> NA (ambiguous middle category)
  #'
  #' Target scale: 1=Trusted, 2=Careful (to match W3-W6)

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 2,      # Careful -> 2
    x == 2 ~ 1,      # Trusted -> 1
    x == 3 ~ NA_real_,  # Both -> NA (can't place on binary scale)
    TRUE ~ NA_real_
  )
}

recode_w5_trust_binary <- function(x,
                                    missing_codes = c(-1, 0, 7, 8, 9),
                                    ...) {
  #' Recode Wave 5 generalized trust (q22) to binary
  #'
  #' Wave 5 has 3 categories:
  #'   1 = "Most people can be trusted" -> 1 (trusted)
  #'   2 = "You must be very careful in dealing with people" -> 2 (careful)
  #'   3 = "It depends" -> NA (ambiguous middle category)
  #'
  #' Target scale: 1=Trusted, 2=Careful (to match W3-W6)

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,      # Trusted -> 1
    x == 2 ~ 2,      # Careful -> 2
    x == 3 ~ NA_real_,  # Depends -> NA
    TRUE ~ NA_real_
  )
}

safe_reverse_2pt <- function(x,
                              missing_codes = c(-1, 0, 7, 8, 9),
                              ...) {
  #' Reverse 2-point scale
  #'
  #' For Wave 2 generalized trust (q23):
  #'   Original: 1=Careful, 2=Trusted
  #'   Target:   1=Trusted, 2=Careful (to match W3-W6)

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 2,
    x == 2 ~ 1,
    TRUE ~ NA_real_
  )
}

# ------------------------------------------------------------------------------
# SOCIAL TRUST: 6-point to 4-point collapse with reversal
# ------------------------------------------------------------------------------

collapse_6pt_to_4pt_reverse <- function(x,
                                         missing_codes = c(-1, 0, 97, 98, 99),
                                         ...) {
  #' Collapse Wave 5 6-point trust scale to 4-point and reverse
  #'
  #' Wave 5 trust items (relatives, neighbors, acquaintances) use 6-point scale:
  #'   1 = Trust fully
  #'   2 = Trust a lot
  #'   3 = Trust somewhat
  #'   4 = Distrust somewhat
  #'   5 = Distrust a lot
  #'   6 = Distrust fully
  #'
  #' Target 4-point scale (high = more trust):
  #'   4 = A great deal of trust (W5: 1,2)
  #'   3 = Quite a lot of trust (W5: 3)
  #'   2 = Not very much trust (W5: 4)
  #'   1 = None at all (W5: 5,6)
  #'
  #' Mapping: 1->4, 2->4, 3->3, 4->2, 5->1, 6->1

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% c(1, 2) ~ 4,   # Trust fully/a lot -> Great deal
    x == 3 ~ 3,            # Trust somewhat -> Quite a lot
    x == 4 ~ 2,            # Distrust somewhat -> Not very much
    x %in% c(5, 6) ~ 1,   # Distrust a lot/fully -> None at all
    TRUE ~ NA_real_
  )
}

# ------------------------------------------------------------------------------
# POLITICAL ATTITUDES: Collapse 5-point (Always -> Never) to 4-point
# ------------------------------------------------------------------------------

collapse_5pt_rarely_never <- function(x,
                                      missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                                      ...) {
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% 1:3 ~ as.numeric(x),
    x %in% 4:5 ~ 4,
    TRUE ~ NA_real_
  )
}

# ------------------------------------------------------------------------------
# INTERNATIONAL RELATIONS: Scale and category collapses
# ------------------------------------------------------------------------------

collapse_10pt_to_6pt <- function(x,
                                 ...) {
  dplyr::case_when(
    is.na(x) ~ NA_real_,
    x %in% 1:2 ~ 1,
    x %in% 3:4 ~ 2,
    x == 5 ~ 3,
    x == 6 ~ 4,
    x %in% 7:8 ~ 5,
    x %in% 9:10 ~ 6,
    TRUE ~ NA_real_
  )
}

collapse_influence_country_to_5 <- function(x,
                                            ...) {
  dplyr::case_when(
    is.na(x) ~ NA_real_,
    x %in% 1:4 ~ as.numeric(x),
    x %in% c(-1, 0, 90, 97, 98, 99) ~ NA_real_,
    TRUE ~ 5
  )
}

# ------------------------------------------------------------------------------
# INTERNATIONAL RELATIONS: Development model recodes
# ------------------------------------------------------------------------------

recode_dev_model_w3_w4_w6 <- function(x,
                                      missing_codes = c(-1, 0, 90, 97, 98, 99),
                                      ...) {
  #' Collapse expanded country lists to 1-7 scale for W3/W4/W6
  #'
  #' Target:
  #'   1=USA, 2=China, 3=India, 4=Japan, 5=Singapore, 6=Other, 7=Own model
  #'
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% 1:5 ~ as.numeric(x),
    x == 6 ~ 6,   # Other
    x == 7 ~ 7,   # Own model
    x >= 8 ~ 6,   # Specific countries/combinations -> Other
    TRUE ~ NA_real_
  )
}

recode_dev_model_w5 <- function(x,
                                missing_codes = c(-1, 0, 90, 97, 98, 99),
                                ...) {
  #' Collapse expanded country lists to 1-7 scale for W5
  #'
  #' W5 codes:
  #'   1-5 match target (USA/China/India/Japan/Singapore)
  #'   6=Russia -> Other
  #'   7=Other -> Other
  #'   8=Own model -> 7
  #'   9+ specific countries -> Other
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% 1:5 ~ as.numeric(x),
    x == 6 ~ 6,   # Russia -> Other
    x == 7 ~ 6,   # Other
    x == 8 ~ 7,   # Own model
    x >= 9 ~ 6,   # Specific countries -> Other
    TRUE ~ NA_real_
  )
}

# ------------------------------------------------------------------------------
# CORRUPTION: Wave 2 anti-corruption effort recode
# ------------------------------------------------------------------------------

recode_w2_anticorrupt <- function(x,
                                   missing_codes = c(-1, 7, 8, 9),
                                   ...) {
  #' Recode Wave 2 anti-corruption effort (q120) from 5-point to 4-point
  #'
  #' Wave 2 has 5-point scale starting at 0:
  #'   0 = It is doing this quite effectively
  #'   1 = It is doing its best
  #'   2 = It is doing something
  #'   3 = It is not doing much
  #'   4 = Doing nothing
  #'
  #' Target 4-point scale (W3-W6 style):
  #'   1 = Very effective / Doing its best
  #'   2 = Somewhat effective / Doing something
  #'   3 = Not very effective / Not doing much
  #'   4 = Not effective at all / Doing nothing
  #'
  #' Mapping: 0->1, 1->1, 2->2, 3->3, 4->4
  #' Note: Collapsing 0 and 1 into category 1 (top effectiveness)

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% c(0, 1) ~ 1,   # Quite effectively / Doing best -> 1
    x == 2 ~ 2,            # Doing something -> 2
    x == 3 ~ 3,            # Not doing much -> 3
    x == 4 ~ 4,            # Doing nothing -> 4
    TRUE ~ NA_real_
  )
}

# ------------------------------------------------------------------------------
# CORRUPTION: Witnessed corruption recodes
# Target scale: 0 = No (not witnessed), 1 = Yes (witnessed)
# ------------------------------------------------------------------------------

recode_witnessed_default <- function(x,
                                     missing_codes = c(-1, 0, 7, 8, 9),
                                     ...) {
  #' Recode default waves (W1, W2, W5, W6) witnessed corruption to 0/1
  #'
  #' Source coding: 1 = Yes/witnessed, 2 = No/not witnessed
  #' Target:        1 = Yes,           0 = No

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,  # Witnessed -> 1
    x == 2 ~ 0,  # Not witnessed -> 0
    TRUE ~ NA_real_
  )
}

recode_w3_witnessed <- function(x,
                                missing_codes = c(-1, 0, 7, 8, 9),
                                ...) {
  #' Recode Wave 3 witnessed corruption (q119) to 0/1
  #'
  #' Wave 3 has:
  #'   1 = Witnessed
  #'   2 = Never witnessed
  #'   6 = No one I know has personally witnessed
  #'
  #' Target: 1 = Yes, 0 = No
  #' Mapping: 1->1, 2->0, 6->0

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,           # Witnessed -> 1
    x %in% c(2, 6) ~ 0,   # Never witnessed / No one I know -> 0
    TRUE ~ NA_real_
  )
}

recode_w4_witnessed <- function(x,
                                missing_codes = c(-1, 0, 7, 8, 9),
                                ...) {
  #' Recode Wave 4 witnessed corruption (q120) to 0/1
  #'
  #' Wave 4 has 5 categories:
  #'   1 = Personally witnessed
  #'   2 = Told about it by a family member who personally witnessed
  #'   3 = Told about it by a friend who personally witnessed
  #'   4 = Personally never witnessed
  #'   5 = No one I know has personally witnessed
  #'
  #' Target: 1 = Yes (any witnessing), 0 = No
  #' Mapping: 1,2,3->1, 4,5->0

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% c(1, 2, 3) ~ 1,  # Any form of witnessed -> 1
    x %in% c(4, 5) ~ 0,     # Never witnessed -> 0
    TRUE ~ NA_real_
  )
}

# ------------------------------------------------------------------------------
# DEMOCRACY SATISFACTION: Collapse 5-point to 4-point then reverse
# ------------------------------------------------------------------------------

collapse_5pt_to_4pt_then_reverse <- function(x,
                                              missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                                              ...) {
  #' Collapse 5-point scale to 4-point and reverse
  #'
  #' For household income satisfaction in W5-W6 which may have 5 categories.
  #' Collapses middle categories and reverses direction.
  #'
  #' This is a placeholder - verify actual scale structure before using.

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 4,
    x == 2 ~ 3,
    x == 3 ~ 2,
    x == 4 ~ 2,  # Collapse 3&4 to middle-low
    x == 5 ~ 1,
    TRUE ~ NA_real_
  )
}

# ------------------------------------------------------------------------------
# CORRUPTION: W6 "No one is involved" recode
# ------------------------------------------------------------------------------

recode_w6_corruption <- function(x,
                                  missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                                  ...) {
  #' Recode Wave 6 corruption variables to handle category 5
  #'
  #' Wave 6 (Cambodia) has an extra category:
  #'   1 = Hardly anyone is involved
  #'   2 = Not a lot of officials are corrupt
  #'   3 = Most officials are corrupt
  #'   4 = Almost everyone is corrupt
  #'   5 = No one is involved  <- more extreme than "hardly anyone"
  #'
  #' Recode 5 -> 1 (most extreme low-corruption response)
  #' Keep 1-4 as identity

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 5 ~ 1,           # "No one involved" -> 1 (lowest corruption)
    x %in% 1:4 ~ as.numeric(x),
    TRUE ~ NA_real_
  )
}

# ------------------------------------------------------------------------------
# COUNTRY: W6 text-to-code mapping
# ------------------------------------------------------------------------------

recode_w6_country <- function(x,
                               data = NULL,
                               var_name = NULL,
                               validate_all = NULL) {
  #' Map Wave 6 country text names to numeric codes
  #'
  #' W1-W5 use numeric country codes (1-15)
  #' W6 uses text country names - map to same codes
  #'
  #' ABS Country Code Mapping:
  #'   1 = Japan
  #'   2 = Hong Kong
  #'   3 = Korea
  #'   4 = Mainland China
  #'   5 = Mongolia
  #'   6 = Philippines
  #'   7 = Taiwan
  #'   8 = Thailand
  #'   9 = Indonesia
  #'   10 = Singapore
  #'   11 = Vietnam
  #'   12 = Cambodia
  #'   13 = Malaysia
  #'   14 = Myanmar
  #'   15 = Australia
  #'
  #' NOTE: This function reads raw data from data[[var_name]] because
  #'       harmonize.R converts to numeric before calling, which destroys text

  # Use raw data if available (x will be NA from numeric conversion of text)
  if (!is.null(data) && !is.null(var_name) && var_name %in% names(data)) {
    x_raw <- data[[var_name]]
  } else {
    x_raw <- x
  }

  # Convert to character to handle both factor and character input
  x_char <- as.character(x_raw)

  dplyr::case_when(
    x_char == "Japan" ~ 1,
    x_char == "Hong Kong" ~ 2,
    x_char == "Korea" ~ 3,
    x_char == "Mainland China" | x_char == "China" ~ 4,
    x_char == "Mongolia" ~ 5,
    x_char == "Philippines" ~ 6,
    x_char == "Taiwan" ~ 7,
    x_char == "Thailand" ~ 8,
    x_char == "Indonesia" ~ 9,
    x_char == "Singapore" ~ 10,
    x_char == "Vietnam" ~ 11,
    x_char == "Cambodia" ~ 12,
    x_char == "Malaysia" ~ 13,
    x_char == "Myanmar" ~ 14,
    x_char == "Australia" ~ 15,
    x_char == "India" ~ 18,
    TRUE ~ NA_real_
  )
}

# ------------------------------------------------------------------------------
# POLITICAL ATTITUDES: News follow and discuss recodes (Added 2025-01-10)
# ------------------------------------------------------------------------------

recode_w1_news_follow <- function(x,
                                   missing_codes = c(-1, 0, 97, 98, 99),
                                   ...) {
  #' Recode Wave 1 news follow (q057) from 2-6 scale to 1-5

  #'
 #' W1 coded: 2=Practically never -> 6=Everyday
  #' Target: 1=Practically never -> 5=Everyday
  #' Simply subtract 1

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% 2:6 ~ as.numeric(x - 1),
    TRUE ~ NA_real_
  )
}

recode_w1_discuss <- function(x,
                               missing_codes = c(-1, 0, 97, 98, 99),
                               ...) {
  #' Recode Wave 1 discuss politics (q023) from 5pt to 3pt
  #'
  #' W1 coded: 1=Never, 2=Rarely, 3=Sometimes, 4=Often, 5=Very often
  #' Target 3pt: 1=Never, 2=Occasionally, 3=Frequently
  #' Collapse: 1->1, 2-3->2, 4-5->3

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,
    x %in% c(2, 3) ~ 2,
    x %in% c(4, 5) ~ 3,
    TRUE ~ NA_real_
  )
}

# ------------------------------------------------------------------------------
# GOV SATISFACTION: W1 5-point with middle at 5 to 4-point
# ------------------------------------------------------------------------------

collapse_middle5_to_4pt <- function(x,
                                     missing_codes = c(-1, 0, 97, 98, 99),
                                     ...) {
  #' Collapse 5-point scale (with middle at position 5) to 4-point

  #'
  #' W1 gov_sat_national (q104) has:
  #'   1 = Very dissatisfied
  #'   2 = Somewhat dissatisfied
  #'   3 = Somewhat satisfied
  #'   4 = Very satisfied
  #'   5 = Half and Half (middle - no equivalent in 4-point scale)
  #'
  #' Keeps 1-4 as identity, converts 5 to NA (can't place middle on 4-point)

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% 1:4 ~ as.numeric(x),
    x == 5 ~ NA_real_,  # Middle category - no 4-point equivalent
    TRUE ~ NA_real_
  )
}

# ------------------------------------------------------------------------------
# DEMOCRACY PREFERABLE: Wave-specific recodes for dem_always_preferable
# ------------------------------------------------------------------------------

recode_w1_dem_preferable <- function(x,
                                      missing_codes = c(-1, 0, 97, 98, 99),
                                      ...) {
  #' Recode Wave 1 democracy preferable (q117) to standard coding
  #'
  #' W1 coding:
  #'   1 = Authoritarian government can be preferable
  #'   2 = Does not matter whether we have a democratic or nondemocratic regime
  #'   3 = Democracy: preferable to any other kind of government
  #'
  #' Target coding (W3-W6 standard):
  #'   1 = Democracy is always preferable
  #'   2 = Authoritarian sometimes preferable
  #'   3 = Doesn't matter what kind of regime
  #'
  #' Mapping: 1->2, 2->3, 3->1

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 2,   # Auth -> 2
    x == 2 ~ 3,   # Doesn't matter -> 3
    x == 3 ~ 1,   # Democracy -> 1
    TRUE ~ NA_real_
  )
}

recode_w2_dem_preferable <- function(x,
                                      missing_codes = c(-1, 0, 7, 8, 9),
                                      ...) {
  #' Recode Wave 2 democracy preferable (q121) to standard coding
  #'
  #' W2 coding:
  #'   1 = For people like me, it does not matter (doesn't matter)
  #'   2 = Under some circumstances, an authoritarian government can be preferable
  #'   3 = Democracy is always preferable to any other kind of government
  #'
  #' Target coding (W3-W6 standard):
  #'   1 = Democracy is always preferable
  #'   2 = Authoritarian sometimes preferable
  #'   3 = Doesn't matter what kind of regime
  #'
  #' Mapping: 1->3, 2->2, 3->1

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 3,   # Doesn't matter -> 3
    x == 2 ~ 2,   # Auth -> 2 (no change)
    x == 3 ~ 1,   # Democracy -> 1
    TRUE ~ NA_real_
  )
}

# ==============================================================================
# NO-VERIFY IDENTITY FUNCTION
# ==============================================================================

#' Pass-through function for identifiers and other variables that don't need validation
#'
#' @description Returns values as-is. Use for ID numbers, country codes, and other
#'   variables where any numeric value is valid. Still supports semantic validation
#'   via validate_all if you want to verify the question text.
#'
#' @param x Numeric vector
#' @param data Optional dataframe for semantic validation
#' @param var_name Optional variable name for semantic validation
#' @param missing_codes Values to convert to NA (default: standard missing codes)
#' @param validate_all Optional character vector of regex patterns to match question text
#'
#' @return Numeric vector with missing codes converted to NA
no_verify <- function(x,
                      data = NULL,
                      var_name = NULL,
                      missing_codes = c(-1, 97, 98, 99),
                      validate_all = NULL) {

  # ---- semantic validation (optional) ----
  .validate_semantic_label(validate_all, data, var_name)

  # ---- pass-through: only convert missing codes to NA ----
  dplyr::if_else(x %in% missing_codes, NA_real_, as.numeric(x))
}

# ==============================================================================
# COMMUNITY LEADER CONTACT RECODING
# ==============================================================================

#' Recode W3 community leader contact from 0-2 to 1-3 scale
#'
#' W3 q66: 0=Never Done, 1=Once, 2=More than once
#' Target: 1=Never, 2=Once, 3=More than once
recode_w3_leader_contact <- function(x,
                                      data = NULL,
                                      var_name = NULL,
                                      missing_codes = c(-1, 7, 8, 9),
                                      validate_all = NULL) {

  if (!is.null(validate_all)) {
    if (is.null(data) || is.null(var_name)) {
      stop("validate_all requires both `data` and `var_name`")
    }
    qtext <- attr(data[[var_name]], "label")
    if (!is.null(qtext)) {
      for (pattern in validate_all) {
        if (!grepl(pattern, qtext, ignore.case = TRUE)) {
          stop(glue::glue("{var_name}: expected '{pattern}' not found in: '{qtext}'"))
        }
      }
    }
  }

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 0 ~ 1,  # Never → 1
    x == 1 ~ 2,  # Once → 2
    x == 2 ~ 3,  # More than once → 3
    TRUE ~ NA_real_
  )
}

#' Collapse W5/W6 5-point leader contact to 3-point scale
#'
#' W5/W6: 1=More than 3x, 2=2-3x, 3=Once, 4=Might do it, 5=Never would
#' Target: 1=Never, 2=Once, 3=More than once
collapse_5pt_leader_to_3pt <- function(x,
                                        data = NULL,
                                        var_name = NULL,
                                        missing_codes = c(-1, 0, 7, 8, 9),
                                        validate_all = NULL) {

  if (!is.null(validate_all)) {
    if (is.null(data) || is.null(var_name)) {
      stop("validate_all requires both `data` and `var_name`")
    }
    qtext <- attr(data[[var_name]], "label")
    if (!is.null(qtext)) {
      for (pattern in validate_all) {
        if (!grepl(pattern, qtext, ignore.case = TRUE)) {
          stop(glue::glue("{var_name}: expected '{pattern}' not found in: '{qtext}'"))
        }
      }
    }
  }

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% c(1, 2) ~ 3,  # More than once (more than 3x or 2-3x) → 3
    x == 3 ~ 2,          # Once → 2
    x %in% c(4, 5) ~ 1,  # Might/Never → 1 (Never)
    TRUE ~ NA_real_
  )
}


#' Recode voted_last_election W1 and W2
#'
#' W1 and W2 have reversed scale: 1=No, 2=Yes; recode to 0=No, 1=Yes
#' W1 missing: 97=Not applicable, 98=Don't remember, 99=No answer
#' W2 missing: 0=Not applicable, 8=Can't choose, 9=Decline to answer
#' @param x Numeric vector
#' @return Numeric vector (0=No, 1=Yes, others→NA)
recode_voted_w1 <- function(x,
                            data = NULL,
                            var_name = NULL,
                            missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                            validate_all = NULL) {
  # W1/W2: 1=No, 2=Yes → target: 0=No, 1=Yes
  # All other values (missing codes, not applicable) → NA
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 0,  # No → 0
    x == 2 ~ 1,  # Yes → 1
    TRUE ~ NA_real_
  )
}


#' Recode voted_last_election W2-W6
#'
#' Recode to 0=No, 1=Yes; "not eligible" and proxy voting → NA
#' @param x Numeric vector
#' @return Numeric vector (0=No, 1=Yes, others→NA)
recode_voted_default <- function(x,
                                 data = NULL,
                                 var_name = NULL,
                                 missing_codes = c(-1, 7, 8, 9, 10),
                                 validate_all = NULL) {
  # 1=Yes→1, 2=No→0, 0/3=Not eligible→NA, 1103/1104=proxy voting→NA
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 0 ~ NA_real_,     # Not applicable/not eligible (W4)
    x == 1 ~ 1,            # Yes → 1
    x == 2 ~ 0,            # No → 0
    x == 3 ~ NA_real_,     # Not yet eligible → NA
    x == 1103 ~ NA_real_,
    x == 1104 ~ NA_real_,
    TRUE ~ NA_real_
  )
}


#' Recode voted_winning_losing with vote-status mask
#'
#' Keep winner/loser only when respondent reports voting; otherwise NA.
#' W2 vote item q38: 1=No, 2=Yes
#' W3-W6 vote item q32/q33: 1=Yes, 2=No
#' @param x Numeric vector (winner/loser codes)
#' @param data Full wave data frame (used to read raw vote item)
#' @param var_name Variable name for winner/loser (q39a/q33a/q34a)
#' @return Numeric vector (1=Winner, 2=Loser, others→NA)
recode_voted_winning_losing_masked <- function(x,
                                               data = NULL,
                                               var_name = NULL,
                                               validate_all = NULL) {
  x_num <- suppressWarnings(as.numeric(x))

  # Determine the vote-status variable for the wave
  vote_var <- NULL
  yes_code <- NULL
  if (!is.null(var_name)) {
    if (var_name == "q39a") {
      # W2 winner/loser -> vote question is q38 (1=No, 2=Yes)
      vote_var <- "q38"
      yes_code <- 2
    } else if (var_name == "q33a") {
      # W3 winner/loser -> vote question is q32 (1=Yes, 2=No)
      vote_var <- "q32"
      yes_code <- 1
    } else if (var_name == "q34a") {
      # W4-W6 winner/loser -> vote question is q33 (1=Yes, 2=No)
      vote_var <- "q33"
      yes_code <- 1
    }
  }

  # Default: keep only valid winner/loser codes
  out <- dplyr::case_when(
    x_num %in% c(1, 2) ~ x_num,
    TRUE ~ NA_real_
  )

  # Apply vote-status mask if we can locate the vote variable
  if (!is.null(data) && !is.null(vote_var) && vote_var %in% names(data)) {
    vote_raw <- suppressWarnings(as.numeric(data[[vote_var]]))
    voted_yes <- vote_raw == yes_code
    out[!voted_yes] <- NA_real_
  }

  out
}


#' Extract month from Date column (for W3 ir9)
#'
#' W3 stores interview date as a Date object; extract month component.
#' Handles both Date objects and numeric representations (days since 1970-01-01).
#' @param x Date vector or numeric (days since epoch)
#' @param data Full wave data frame (used to access original Date column)
#' @param var_name Variable name to read from data
#' @return Numeric vector (1-12)
extract_month_from_date <- function(x,
                                    data = NULL,
                                    var_name = NULL,
                                    validate_all = NULL) {
  # Try to get original Date/character from data if available
  if (!is.null(data) && !is.null(var_name) && var_name %in% names(data)) {
    orig <- data[[var_name]]
    # Parse character dates (e.g., "2021-10-16" from Arab Barometer W7/W8)
    if (is.character(orig)) {
      orig <- suppressWarnings(as.Date(orig))
    }
    if (inherits(orig, "Date")) {
      months <- as.integer(format(orig, "%m"))
      years <- as.integer(format(orig, "%Y"))
      # Filter out obviously wrong dates
      months[is.na(years) | years < 2000 | years > 2030] <- NA_integer_
      return(as.numeric(months))
    }
  }

  # Fallback: if x is Date
  if (inherits(x, "Date")) {
    months <- as.integer(format(x, "%m"))
    years <- as.integer(format(x, "%Y"))
    months[years < 2000 | years > 2030] <- NA_integer_
    return(as.numeric(months))
  }

  # Fallback: if x is numeric (days since 1970-01-01), convert back to Date
  if (is.numeric(x)) {
    dates <- as.Date(x, origin = "1970-01-01")
    months <- as.integer(format(dates, "%m"))
    years <- as.integer(format(dates, "%Y"))
    # Filter out obviously wrong dates
    months[years < 2000 | years > 2030] <- NA_integer_
    return(as.numeric(months))
  }

  # Fallback: if x is character (e.g., "2021-10-16"), parse to Date then extract
  if (is.character(x)) {
    dates <- suppressWarnings(as.Date(x))
    months <- as.integer(format(dates, "%m"))
    years <- as.integer(format(dates, "%Y"))
    months[is.na(years) | years < 2000 | years > 2030] <- NA_integer_
    return(as.numeric(months))
  }

  # If nothing works, return NA
  rep(NA_real_, length(x))
}


#' Extract year from Date column (for W3 ir9)
#'
#' W3 stores interview date as a Date object; extract year component.
#' Handles both Date objects and numeric representations (days since 1970-01-01).
#' @param x Date vector or numeric (days since epoch)
#' @param data Full wave data frame (used to access original Date column)
#' @param var_name Variable name to read from data
#' @return Numeric vector (e.g., 2010, 2011, 2012)
extract_date <- function(x,
                         data = NULL,
                         var_name = NULL,
                         validate_all = NULL) {
  #' Extract Date from a Date or character column, preserving class
  #'
  #' The harmonization engine coerces to numeric (days since epoch).
  #' This function reads the original Date from data[[var_name]].
  #' Also handles character dates (e.g., "2021-10-16").
  #' @return Date vector

  # Get original Date/character from raw data
  if (!is.null(data) && !is.null(var_name) && var_name %in% names(data)) {
    orig <- data[[var_name]]
    if (is.character(orig)) {
      return(suppressWarnings(as.Date(orig)))
    }
    if (inherits(orig, "Date")) {
      return(orig)
    }
  }

  # Fallback: convert numeric (days since epoch) back to Date
  if (is.numeric(x)) {
    return(as.Date(x, origin = "1970-01-01"))
  }

  # Fallback: parse character strings (e.g., "2021-10-16")
  if (is.character(x)) {
    return(suppressWarnings(as.Date(x)))
  }

  rep(as.Date(NA), length(x))
}

recode_0_3_to_1_4 <- function(x,
                              data = NULL,
                              var_name = NULL,
                              missing_codes = c(-1, 8, 9, 98, 99, 998, 999),
                              validate_all = NULL) {
  #' Shift 0-3 scale to 1-4 (Afrobarometer trust items)
  #'
  #' Raw: 0=Not at all, 1=Just a little, 2=Somewhat, 3=A lot
  #' Target: 1=Not at all, 2=Just a little, 3=Somewhat, 4=A lot

  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% 0:3 ~ x + 1,
    TRUE ~ NA_real_
  )
}

extract_year_from_date <- function(x,
                                   data = NULL,
                                   var_name = NULL,
                                   validate_all = NULL) {
  # Try to get original Date/character from data if available
  if (!is.null(data) && !is.null(var_name) && var_name %in% names(data)) {
    orig <- data[[var_name]]
    if (is.character(orig)) {
      orig <- suppressWarnings(as.Date(orig))
    }
    if (inherits(orig, "Date")) {
      years <- as.integer(format(orig, "%Y"))
      years[is.na(years) | years < 2000 | years > 2030] <- NA_integer_
      return(as.numeric(years))
    }
  }

  # Fallback: if x is Date
  if (inherits(x, "Date")) {
    years <- as.integer(format(x, "%Y"))
    years[years < 2000 | years > 2030] <- NA_integer_
    return(as.numeric(years))
  }

  # Fallback: if x is numeric (days since 1970-01-01), convert back to Date
  if (is.numeric(x)) {
    dates <- as.Date(x, origin = "1970-01-01")
    years <- as.integer(format(dates, "%Y"))
    # Filter out obviously wrong dates
    years[years < 2000 | years > 2030] <- NA_integer_
    return(as.numeric(years))
  }

  # Fallback: if x is character (e.g., "2021-10-16"), parse to Date then extract
  if (is.character(x)) {
    dates <- suppressWarnings(as.Date(x))
    years <- as.integer(format(dates, "%Y"))
    years[is.na(years) | years < 2000 | years > 2030] <- NA_integer_
    return(as.numeric(years))
  }

  # If nothing works, return NA
  rep(NA_real_, length(x))
}

#' Extract year from a YYYYMMDD integer (e.g., WVS W4 V247 = 20000816 -> 2000)
extract_year_from_yyyymmdd <- function(x,
                                       data = NULL,
                                       var_name = NULL,
                                       validate_all = NULL) {
  x <- suppressWarnings(as.numeric(x))
  years <- x %/% 10000
  years[is.na(years) | years < 1981 | years > 2030] <- NA_real_
  years
}

#' Extract month from a YYYYMMDD integer (e.g., 20000816 -> 8)
extract_month_from_yyyymmdd <- function(x,
                                        data = NULL,
                                        var_name = NULL,
                                        validate_all = NULL) {
  x <- suppressWarnings(as.numeric(x))
  years <- x %/% 10000
  months <- (x %/% 100) %% 100
  bad <- is.na(months) | years < 1981 | years > 2030 | months < 1 | months > 12
  months[bad] <- NA_real_
  months
}

#' Extract year from a WVS S025 integer (country_iso3n * 10000 + year)
#'
#' S025 packs country and year (e.g., 202018 = country 20, year 2018). The year
#' is the last four digits.
extract_year_from_s025 <- function(x,
                                   data = NULL,
                                   var_name = NULL,
                                   validate_all = NULL) {
  x <- suppressWarnings(as.numeric(x))
  years <- x %% 10000
  years[is.na(years) | years < 1981 | years > 2030] <- NA_real_
  years
}

# ── KAMOS-specific recoding functions ─────────────────────────────────────────

# recode_kamos_gender_w1
# KAMOS Wave 1 codes gender as 1=female, 2=male.
# Wave 4 uses the reverse (1=male, 2=female).
# This function standardises W1 to match 1=male, 0=female.
recode_kamos_gender_w1 <- function(x, data = NULL, var_name = NULL,
                                   validate_all = NULL) {
  x <- as.numeric(x)
  dplyr::case_when(
    x == 1L ~ 0L,   # female → 0
    x == 2L ~ 1L,   # male   → 1
    TRUE    ~ NA_integer_
  )
}

# ------------------------------------------------------------------------------
# GENERAL BINARY RECODING: 1=Yes, 2=No -> 1=Yes, 0=No
# ------------------------------------------------------------------------------

#' Recode standard 1=Yes, 2=No binary scale to 1=Yes, 0=No
#'
#' @param x Numeric vector
#' @param data Full wave data frame
#' @param var_name Variable name
#' @param missing_codes Values to treat as NA
#' @param validate_all Optional patterns for label validation
#' @return Numeric vector (0=No, 1=Yes, others=NA)
recode_binary_yes_no <- function(x,
                                 data = NULL,
                                 var_name = NULL,
                                 missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                                 validate_all = NULL) {
  # ---- semantic validation (optional) ----
  if (!is.null(validate_all)) {
    if (is.null(data) || is.null(var_name)) {
      stop("❌ validate_all requires both `data` and `var_name`")
    }
    qtext <- attr(data[[var_name]], "label")
    if (!is.null(qtext)) {
      for (pattern in validate_all) {
        if (!grepl(pattern, qtext, ignore.case = TRUE)) {
          stop(glue::glue("❌ {var_name}: expected concept '{pattern}' not found in label '{qtext}'"))
        }
      }
    }
  }

  # ---- recode logic ----
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,  # Yes -> 1
    x == 2 ~ 0,  # No  -> 0
    TRUE ~ NA_real_
  )
}

#' Recode gender to 1=Male, 0=Female
recode_gender_binary <- function(x,
                                 missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                                 ...) {
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,  # Male -> 1
    x == 2 ~ 0,  # Female -> 0
    TRUE ~ NA_real_
  )
}

#' Recode WVS W4/W5 marital status (extra codes) to standard 1-6
#'
#' W4/W5 have extra codes: 7=combined divorced/sep/widow, 8/10=living apart
#' Maps: 1-6 pass through, 7→3 (Divorced), 8→4 (Separated), 10→4 (Separated)
recode_marital_w4w5 <- function(x,
                                data = NULL,
                                var_name = NULL,
                                missing_codes = c(-5, -4, -3, -2, -1),
                                validate_all = NULL) {
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% 1:6 ~ as.numeric(x),
    x == 7 ~ 3,   # Combined divorced/separated/widow → Divorced
    x == 8 ~ 4,   # Living apart → Separated
    x == 10 ~ 4,  # Living apart (W4 code) → Separated
    TRUE ~ NA_real_
  )
}

#' Recode continuous age to 5-category bracket (matching KAMOS W2/W3 de2)
#'
#' 1=18-29, 2=30-39, 3=40-49, 4=50-59, 5=60+
recode_age_to_5cat <- function(x,
                                missing_codes = c(97, 98, 99),
                                ...) {
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    is.na(x) ~ NA_real_,
    x < 18 ~ NA_real_,
    x <= 29 ~ 1,
    x <= 39 ~ 2,
    x <= 49 ~ 3,
    x <= 59 ~ 4,
    x >= 60 ~ 5,
    TRUE ~ NA_real_
  )
}

#' Recode urban/rural to 1=Urban, 0=Rural
#'
#' Default (W1-W3): 1=Urban, 2=Rural
#' Target: 1=Urban, 0=Rural
recode_urban_rural_binary <- function(x,
                                      missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                                      ...) {
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,  # Urban -> 1
    x == 2 ~ 0,  # Rural -> 0
    TRUE ~ NA_real_
  )
}

#' Recode urban/rural (reversed waves) to 1=Urban, 0=Rural
#'
#' Reversed (W4-W6): 1=Rural, 2=Urban
#' Target: 1=Urban, 0=Rural
recode_urban_rural_reversed_binary <- function(x,
                                               missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                                               ...) {
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 0,  # Rural -> 0
    x == 2 ~ 1,  # Urban -> 1
    TRUE ~ NA_real_
  )
}

#' Recode 1/2 binary to 0/1 (generic mapping 1->0, 2->1)
#'
#' Useful for "No/Yes" where 1=No, 2=Yes or "Alone/Others" where 1=Alone, 2=Others
recode_binary_01 <- function(x,
                             missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                             ...) {
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 0,
    x == 2 ~ 1,
    TRUE ~ NA_real_
  )
}

# ==============================================================================
# SCALE CONVERSION FUNCTIONS
# ==============================================================================

#' Recode 5-point to 4-point scale
#'
#' Linear rescaling: (x-1) * (4/5) + 1 with rounding
#' @param x Numeric vector (1-5)
#' @return Rescaled numeric vector (1-4)
recode_5pt_to_4pt <- function(x, ...) {
  round((as.numeric(x) - 1) * (4 / 5) + 1, 0)
}

#' Recode 3-point to 4-point scale
#'
#' Linear rescaling: (x-1) * (4/3) + 1
#' @param x Numeric vector (1-3)
#' @return Rescaled numeric vector (1-4)
recode_3pt_to_4pt <- function(x, ...) {
  round((as.numeric(x) - 1) * (4 / 3) + 1, 0)
}

#' Recode 6-point to 4-point scale
#'
#' Linear rescaling: (x-1) * (4/6) + 1 with rounding
#' @param x Numeric vector (1-6)
#' @return Rescaled numeric vector (1-4)
recode_6pt_to_4pt <- function(x, ...) {
  round((as.numeric(x) - 1) * (4 / 6) + 1, 0)
}

#' Recode 10-point to 4-point scale
#'
#' Linear rescaling: (x-1) * (4/10) + 1 with rounding
#' Maps 1-10 scale to 1-4 scale proportionally
#' @param x Numeric vector (1-10)
#' @return Rescaled numeric vector (1-4)
recode_10pt_to_4pt <- function(x, ...) {
  round((as.numeric(x) - 1) * (4 / 10) + 1, 0)
}

# ==============================================================================
# IDENTIFICATION AND VALIDATION FUNCTIONS
# ==============================================================================

#' Identify and preserve 4-point scale values
#'
#' Remove NA codes (keep only 1-4 values) without transforming
#' Converts out-of-range values to NA_real_
#' @param x Numeric vector containing 1-4 and missing codes
#' @return Numeric vector with missing codes converted to NA_real_
safe_identify_4pt <- function(x, ...) {
  ifelse(x >= 1 & x <= 4, x, NA_real_)
}

#' Identify and preserve 5-point scale values
#'
#' Remove NA codes (keep only 1-5 values) without transforming
#' Converts out-of-range values to NA_real_
#' @param x Numeric vector containing 1-5 and missing codes
#' @return Numeric vector with missing codes converted to NA_real_
safe_identify_5pt <- function(x, ...) {
  ifelse(x >= 1 & x <= 5, x, NA_real_)
}

#' Identify and preserve 6-point scale values
#'
#' Remove NA codes (keep only 1-6 values) without transforming
#' Converts out-of-range values to NA_real_
#' @param x Numeric vector containing 1-6 and missing codes
#' @return Numeric vector with missing codes converted to NA_real_
safe_identify_6pt <- function(x, ...) {
  ifelse(x >= 1 & x <= 6, x, NA_real_)
}

#' Handle W6 extended corruption scale (1-5 with special codes)
#'
#' W6 has extended scale with:
#'   1 = Hardly anyone involved
#'   2 = Not a lot of officials are corrupt
#'   3 = Most officials are corrupt
#'   4 = Almost everyone is corrupt
#'   5 = No one is involved (rare response)
#'   0 = Not applicable
#'
#' Map to standard 1-4 scale by treating 5 and 0 as NA
#' @param x Numeric vector (1-5 with 0=N/A)
#' @return Numeric vector with 5→NA, 0→NA, keeping 1-4
harmonize_w6_corruption <- function(x, ...) {
  # Map 5 (No one involved) and 0 (N/A) to NA
  # Keep 1-4 as-is
  ifelse(x >= 1 & x <= 4, x, NA_real_)
}

# ==============================================================================
# INTERNET FREQUENCY HARMONIZATION
# Harmonizes ABS news_internet (q66/q45/q49/q50) to a common 1-6 ordinal scale
# Output: 1=Never, 2=Hardly ever, 3=A few times/year, 4=Monthly, 5=Weekly, 6=Daily+
# Higher values = more frequent internet use (reversed from raw coding)
# ==============================================================================

#' Harmonize W2/W3 internet frequency to 1-6 scale
#'
#' W2 (q66): 0=not aware, 1=almost daily, 2=once/wk, 3=once/month,
#'           4=several/year, 5=hardly ever, 6=never; 7,8,9=non-response
#' W3 (q45): same structure, no 0 category
#' @param x Numeric vector (raw W2/W3 codes)
#' @return Numeric vector 1-6 (1=never, 6=daily+)
# ==============================================================================
# PARTICIPATION BINARY GATE FUNCTIONS
# Convert ABS political action items to binary: 0=never done, 1=ever done
#
# Raw scale structures differ by wave:
#   W1  (q073, q075, etc.): 1=Once, 2=More than once, 9=Never done; 97/98/99=non-response
#   W2  (q81, etc.):        1=Once, 2=More than once, 3=Never; 7/8/9=non-response
#   W3  (q64, etc.):        0=Never Done, 1=Once, 2=More than once; 8/9=non-response
#   W4  (q69 3-cat, etc.):  1=More than once, 2=Once, 3=Never; 7/8/9=non-response
#   W5/W6 (q70, etc.):      1=>3 times, 2=2-3 times, 3=once, 4=might, 5=would never;
#                            0=N/A; 7/8/9=non-response
#
# Use with missing convention: contact_binary_missing [-1, 7, 8, 97, 98, 99]
# (keeps 0 and 9 alive so recode functions can handle them semantically)
# ==============================================================================

#' Binary gate: W1 participation items (1=Once, 2=More, 9=Never done)
recode_contact_to_binary_w1 <- function(x, ...) {
  dplyr::case_when(
    x == 9         ~ 0,   # Never done
    x %in% c(1, 2) ~ 1,  # Once or more than once
    TRUE           ~ NA_real_
  )
}

#' Binary gate: W2 and W4 (3-cat) participation items
#' W2: 1=Once, 2=More than once, 3=Never
#' W4: 1=More than once, 2=Once, 3=Never (order differs but binary mapping is same)
recode_contact_to_binary_w2w4 <- function(x, ...) {
  dplyr::case_when(
    x %in% c(1, 2) ~ 1,  # Once or more than once (either order)
    x == 3         ~ 0,  # Never
    TRUE           ~ NA_real_
  )
}

#' Binary gate: W3 participation items (0=Never Done, 1=Once, 2=More than once)
#' Note: 0 must survive missing code filtering — use contact_binary_missing convention
recode_contact_to_binary_w3 <- function(x, ...) {
  dplyr::case_when(
    x == 0         ~ 0,  # Never Done
    x %in% c(1, 2) ~ 1,  # Once or more than once
    TRUE           ~ NA_real_
  )
}

#' Binary gate: W5/W6 participation items (5-pt scale, raw 1=most active)
#' 1=>3 times, 2=2-3 times, 3=once → ever done (1)
#' 4=might do, 5=would never → never done (0)
#' 0=Not applicable → NA (via TRUE branch)
recode_contact_to_binary_5pt <- function(x, ...) {
  dplyr::case_when(
    x %in% c(1, 2, 3) ~ 1,  # Ever done (any frequency)
    x %in% c(4, 5)    ~ 0,  # Never done (might or would never)
    TRUE               ~ NA_real_
  )
}

# ==============================================================================
# INTERNET FREQUENCY HARMONIZATION
recode_internet_w2w3_to_6pt <- function(x, ...) {
  dplyr::case_when(
    x == 0 ~ NA_real_,   # W2: not aware of internet
    x == 1 ~ 6,          # Almost daily    -> Daily or more
    x == 2 ~ 5,          # At least once a week
    x == 3 ~ 4,          # At least once a month
    x == 4 ~ 3,          # Several times a year
    x == 5 ~ 2,          # Hardly ever
    x == 6 ~ 1,          # Never
    TRUE   ~ NA_real_
  )
}

#' Harmonize W4 internet frequency to 1-6 scale
#'
#' W4 (q49): 0=not applicable, 1=several hrs/day, 2=half-1hr/day,
#'           3=at least once/day, 4=at least once/wk, 5=at least once/month,
#'           6=a few times/year, 7=hardly ever, 8=never; 97,98,99=non-response
#' @param x Numeric vector (raw W4 codes)
#' @return Numeric vector 1-6 (1=never, 6=daily+)
recode_internet_w4_to_6pt <- function(x, ...) {
  dplyr::case_when(
    x == 0          ~ NA_real_,  # Not applicable
    x %in% c(1,2,3) ~ 6,         # Several hrs / half-hr / once per day -> Daily+
    x == 4          ~ 5,          # At least once a week
    x == 5          ~ 4,          # At least once a month
    x == 6          ~ 3,          # A few times a year
    x == 7          ~ 2,          # Hardly ever
    x == 8          ~ 1,          # Never
    TRUE            ~ NA_real_
  )
}

#' Harmonize W5/W6 internet frequency to 1-6 scale
#'
#' W5 (q49): 1=connected all time, 2=several hrs/day, 3=half-1hr/day,
#'           4=<half hr/day, 5=at least once/wk, 6=at least once/month,
#'           7=a few times/year, 8=hardly ever, 9=never; 97,98,99=non-response
#' W6 (q50): 0=no access, 1-9 same as W5
#' @param x Numeric vector (raw W5/W6 codes)
#' @return Numeric vector 1-6 (1=never, 6=daily+)
recode_internet_w5w6_to_6pt <- function(x, ...) {
  dplyr::case_when(
    x == 0           ~ NA_real_,  # W6: no access to internet
    x %in% c(1,2,3,4) ~ 6,        # Connected all time / several hrs / half-hr / <half hr -> Daily+
    x == 5           ~ 5,          # At least once a week
    x == 6           ~ 4,          # At least once a month
    x == 7           ~ 3,          # A few times a year
    x == 8           ~ 2,          # Hardly ever
    x == 9           ~ 1,          # Never
    TRUE             ~ NA_real_
  )
}

#' Validate harmonization
#'
#' Check that harmonized vector has expected range and no invalid values
#' @param x Harmonized vector
#' @param expected_min Expected minimum value
#' @param expected_max Expected maximum value
#' @param var_name Variable name (for messages)
#' @return Logical TRUE/FALSE with warnings if issues found
validate_harmonization <- function(x, expected_min = 1, expected_max = 4, var_name = "variable") {
  valid_count <- sum(!is.na(x))
  missing_count <- sum(is.na(x))
  out_of_range <- sum(!is.na(x) & (x < expected_min | x > expected_max))

  cat(sprintf("\n%s:\n", var_name))
  cat(sprintf("  Valid: %d | Missing: %d | Out of range: %d\n",
              valid_count, missing_count, out_of_range))

  if (out_of_range > 0) {
    cat(sprintf("  ⚠️  Found %d out-of-range values\n", out_of_range))
    return(FALSE)
  } else {
    cat("  ✅ All values within expected range\n")
    return(TRUE)
  }
}

recode_afro_dem_sat <- function(x,
                                data = NULL,
                                var_name = NULL,
                                missing_codes = c(-1, 0, 8, 9, 98, 99, 998, 999),
                                validate_all = NULL) {
  #' Recode Afrobarometer dem_satisfaction (R2-R8)
  #'
  #' R2-R8 raw: 0=Not a democracy (→NA), 1-4=satisfaction scale
  #' 0 is treated as missing because it means "country is not a democracy"

  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% 1:4 ~ x,
    TRUE ~ NA_real_
  )
}

recode_afro_dem_pref_r1 <- function(x,
                                     data = NULL,
                                     var_name = NULL,
                                     missing_codes = c(-1, 8, 9, 98, 99, 998, 999),
                                     validate_all = NULL) {
  #' Recode Afrobarometer R1 dem_support_preferable
  #'
  #' R1 raw: 1=Dem pref, 2=Doesn't matter, 3=Non-dem pref
  #' Target: 1=Dem pref, 2=Non-dem pref, 3=Doesn't matter
  #' Swap positions 2 and 3

  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,
    x == 2 ~ 3,
    x == 3 ~ 2,
    TRUE ~ NA_real_
  )
}

recode_afro_dem_pref_r2_r8 <- function(x,
                                        data = NULL,
                                        var_name = NULL,
                                        missing_codes = c(-1, 8, 9, 98, 99, 998, 999),
                                        validate_all = NULL) {
  #' Recode Afrobarometer R2-R8 dem_support_preferable
  #'
  #' R2-R8 raw: 1=Doesn't matter, 2=Non-dem pref, 3=Dem pref
  #' Target: 1=Dem pref, 2=Non-dem pref, 3=Doesn't matter
  #' Reverse: 1->3, 2->2, 3->1

  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 3,
    x == 2 ~ 2,
    x == 3 ~ 1,
    TRUE ~ NA_real_
  )
}

recode_afro_reject_auth <- function(x,
                                    data = NULL,
                                    var_name = NULL,
                                    missing_codes = c(-1, 8, 9, 98, 99, 997, 998),
                                    validate_all = NULL) {
  #' Afrobarometer reject authoritarian rule items
  #'
  #' Raw: 1=Strongly disapprove, 2=Disapprove, 3=Neither, 4=Approve, 5=Strongly approve
  #' (of authoritarian alternative)
  #' Target: REVERSE so higher = MORE REJECTION (pro-democracy)
  #' 1->5, 2->4, 3->3, 4->2, 5->1

  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% 1:5 ~ 6 - x,
    TRUE ~ NA_real_
  )
}

recode_afro_educ_detailed <- function(x,
                                       data = NULL,
                                       var_name = NULL,
                                       missing_codes = c(-1, 8, 9, 10, 98, 99, 998, 999),
                                       validate_all = NULL) {
  #' Afrobarometer detailed education (0-9) -> condensed (0-3)
  #'
  #' Raw: 0=No formal, 1=Informal only, 2=Some primary, 3=Primary complete,
  #'       4=Some secondary, 5=Secondary complete, 6=Post-sec non-univ,
  #'       7=Some university, 8=University complete, 9=Post-graduate
  #' Target: 0=No formal, 1=Primary, 2=Secondary, 3=Post-secondary

  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% c(0, 1) ~ 0,     # No formal / informal only
    x %in% c(2, 3)  ~ 1,    # Some/complete primary
    x %in% c(4, 5)  ~ 2,    # Some/complete secondary
    x %in% c(6, 7, 8, 9) ~ 3,  # Post-secondary
    TRUE ~ NA_real_
  )
}

recode_afro_r1_trust <- function(x,
                                  data = NULL,
                                  var_name = NULL,
                                  missing_codes = c(-1, 8, 9, 98, 99, 998, 999),
                                  validate_all = NULL) {
  #' Afrobarometer R1 trust: already 1-4 scale, just clean missing codes
  #'
  #' R1 raw: 1=Not at all, 2=Distrust somewhat, 3=Trust somewhat, 4=Trust a lot
  #' Target: 1-4 (same direction, identity after missing cleanup)

  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% 1:4 ~ x,
    TRUE ~ NA_real_
  )
}

# ── KAMOS party bloc recoding ──────────────────────────────────────────────────
# Recodes raw party identification to 3-category bloc:
#   1 = conservative, 2 = progressive, 3 = none/other
# Party codes differ across waves so each wave needs its own function.

recode_party_bloc_w1 <- function(x, missing_codes = c(97, 98, 99), ...) {
  # W1: 1=Saenuri(cons), 2=Minjoo(prog), 3=People's, 4=other, 5=none
  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,  # conservative
    x == 2 ~ 2,  # progressive
    x %in% c(3, 4, 5) ~ 3,  # none/other
    TRUE ~ NA_real_
  )
}

recode_party_bloc_w2 <- function(x, missing_codes = c(97, 98, 99), ...) {
  # W2: 1=Minjoo(prog), 2=LKP(cons), 3=People's, 4=Bareun, 5=Justice, 6=other, 7=none
  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 2 ~ 1,  # conservative
    x == 1 ~ 2,  # progressive
    x %in% c(3, 4, 5, 6, 7) ~ 3,  # none/other
    TRUE ~ NA_real_
  )
}

recode_party_bloc_w3w4 <- function(x, missing_codes = c(97, 98, 99), ...) {
  # W3/W4: 1=Minjoo(prog), 2=LKP(cons), 3=Bareun Mirae, 4=Justice, 5=other, 6=none
  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 2 ~ 1,  # conservative
    x == 1 ~ 2,  # progressive
    x %in% c(3, 4, 5, 6) ~ 3,  # none/other
    TRUE ~ NA_real_
  )
}

# ==============================================================================
# AGE COHORT
# ==============================================================================

#' Recode continuous age to age cohort bins
#'
#' @param x Numeric age vector
#' @return Numeric cohort code: 1=18-29, 2=30-39, 3=40-49, 4=50-59, 5=60+
recode_age_cohort <- function(x, ...) {
  x <- as.numeric(x)
  dplyr::case_when(
    is.na(x) ~ NA_real_,
    x < 18  ~ NA_real_,
    x <= 29 ~ 1,
    x <= 39 ~ 2,
    x <= 49 ~ 3,
    x <= 59 ~ 4,
    x >= 60 ~ 5,
    TRUE ~ NA_real_
  )
}

# ==============================================================================
# PARTY CLOSENESS — AFROBAROMETER
# ==============================================================================

#' Recode Afro party closeness to binary (1=Yes close, 0=No)
#'
#' R1: pidcls 1=Yes, 2=No, 3=DK, 98=Refused, 99=Missing
#' R2: q87a  0=No, party codes (50+)=Yes, 995=Other, 998=Refused, 999=DK
#' R3-R9: qXX 0=No, 1=Yes, 8=Refused, 9=DK
recode_afro_party_close_r1 <- function(x, missing_codes = c(-1, 3, 98, 99, 998, 999), ...) {
  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,
    x == 2 ~ 0,
    TRUE ~ NA_real_
  )
}

recode_afro_party_close_r2 <- function(x, missing_codes = c(-1, 998, 999), ...) {
  # R2 q87a: combined var — 0=No party, party codes (1+)=Yes, 995=Other party (still Yes)
  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 0 ~ 0,     # No, not close to any party
    x >= 1 ~ 1,     # Any party code = close to a party
    TRUE ~ NA_real_
  )
}

recode_afro_party_close <- function(x, missing_codes = c(-1, 8, 9, 98, 99, 998, 999), ...) {
  # R3-R9: 0=No, 1=Yes
  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,
    x == 0 ~ 0,
    TRUE ~ NA_real_
  )
}

# ==============================================================================
# PARTY CLOSENESS — ARAB BAROMETER
# ==============================================================================

#' Recode Arab Barometer party closeness to binary
#'
#' q503/Q503A: nominal party codes (country-specific).
#' We recode to binary: has a party = 1, no party / none = 0.
#' Convention: "no party" codes vary by wave (often 0, high codes like 97/98/99).
recode_arab_party_close_binary <- function(x, missing_codes = c(-1, -8, -9, 98, 99, 997, 998, 999), ...) {
  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    is.na(x) ~ NA_real_,
    x == 0 ~ 0,   # 0 = no party / none
    TRUE ~ 1       # any non-zero, non-missing code = has a party
  )
}

# ==============================================================================
# EMPLOYMENT STATUS — AFROBAROMETER
# ==============================================================================

#' Recode Afro employment to 3-category (labor force status)
#'
#' R2: q89 0=No not looking, 1=No looking, 2=Yes PT not looking,
#'         3=Yes PT looking, 4=Yes FT not looking, 5=Yes FT looking
#' R5-R9: Q96/Q93A 0=No not looking, 1=No looking, 2=Yes part-time, 3=Yes full-time
#'
#' Target: 0=Out of labor force, 1=Unemployed (looking), 2=Employed
recode_afro_employment_r2 <- function(x, missing_codes = c(-1, 9, 60, 98, 998, 999), ...) {
  # R2: 6-category → 3-category
  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 0 ~ 0,           # No, not looking → out of labor force
    x == 1 ~ 1,           # No, looking → unemployed
    x %in% 2:5 ~ 2,       # Yes (any PT/FT) → employed
    TRUE ~ NA_real_
  )
}

recode_afro_employment <- function(x, missing_codes = c(-1, 8, 9, 98, 99, 998, 999, 9994), ...) {
  # R3-R9: 4-category → 3-category
  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 0 ~ 0,           # No, not looking → out of labor force
    x == 1 ~ 1,           # No, looking → unemployed
    x %in% 2:3 ~ 2,       # Yes, PT or FT → employed
    TRUE ~ NA_real_
  )
}

# ==============================================================================
# EMPLOYMENT STATUS — ARAB BAROMETER
# ==============================================================================

#' Recode Arab Barometer employment to 3-category (labor force status)
#'
#' W2-W4 (q1004): 1=Yes, 2=No (binary; no looking/not-looking distinction)
#'   → Employed=2, Not employed=0 (cannot distinguish unemployed vs OLF)
#' W5-W8 (Q1005): 1=Employed, 2=Self-employed, 3=Retired, 4=Housewife,
#'   5=Student, 6=Unemployed, 7=Other
#'
#' Target: 0=Out of labor force, 1=Unemployed, 2=Employed
#' Flag Tataouine respondents (Tunisia only, R5/R6/R9 governorate data)
recode_afro_tataouine_r5 <- function(x, ...) {
  x <- as.numeric(x)
  dplyr::case_when(x == 1600 ~ 1, x %in% 1580:1603 ~ 0, TRUE ~ NA_real_)
}

recode_afro_tataouine_r6 <- function(x, ...) {
  x <- as.numeric(x)
  dplyr::case_when(x == 1599 ~ 1, x %in% 1580:1603 ~ 0, TRUE ~ NA_real_)
}

recode_afro_tataouine_r9 <- function(x, ...) {
  x <- toupper(trimws(as.character(x)))
  tun_names <- c("TUNIS","ARIANA","L'ARIANA","BEN AROUS","MANOUBA","NABEUL",
                  "ZAGHOUAN","BIZERTE","SOUSSE","MONASTIR","MAHDIA","SFAX",
                  "GABES","MEDENINE","BEJA","JENDOUBA","LE KEF","KEF","SILIANA",
                  "KAIROUAN","KASSERINE","SIDI BOUZID","GAFSA","TOZEUR","KEBILI",
                  "TATAOUINE")
  dplyr::case_when(x == "TATAOUINE" ~ 1, x %in% tun_names ~ 0, TRUE ~ NA_real_)
}

recode_arab_employment_w2w4 <- function(x, missing_codes = c(0, -1, -8, -9, 8, 9, 98, 99, 997, 998, 999), ...) {
  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 2,  # Yes → employed
    x == 2 ~ 0,  # No → OLF (W2-W4 cannot distinguish unemployed vs OLF)
    TRUE ~ NA_real_
  )
}

# ==============================================================================
# TUNISIA COASTAL / INTERIOR — AFROBAROMETER
# ==============================================================================

#' Recode Afro REGION to coastal/interior for Tunisia
#'
#' Tunisia-specific. Returns NA for all non-Tunisia region codes.
#' coastal=1: Tunis, Ariana, Ben Arous, Manouba, Nabeul, Zaghouan,
#'            Bizerte, Sousse, Monastir, Mahdia, Sfax, Gabes, Medenine
#' interior=0: Beja, Jendouba, Le Kef, Siliana, Kairouan, Kasserine,
#'             Sidi Bouzid, Gafsa, Tozeur, Kebili, Tataouine
#'
#' NOTE: Tataouine is INTERIOR despite being in the "South East" region.
#' R7-R8 use region-level codes where South East is indivisible —
#' ~16 Tataouine respondents will be misclassified as coastal in R7-R8.
#' R5-R6 and R9 have governorate-level resolution, so Tataouine is correct.

recode_afro_coastal_tun_r5 <- function(x, ...) {
  # R5 governorate codes:
  # Coastal: Tunis(1580), Ariana(1581), Ben Arous(1582), Manouba(1583),
  #   Nabeul(1584), Zaghouan(1585), Bizerte(1586),
  #   Sousse(1591), Monastir(1592), Mahdia(1593), Sfax(1594),
  #   Gabes(1598), Medenine(1599)
  # Interior: Beja(1587), Jendouba(1588), Le Kef(1589), Siliana(1590),
  #   Kairouan(1595), Kasserine(1596), Sidi Bouzid(1597),
  #   Tataouine(1600), Gafsa(1601), Tozeur(1602), Kebili(1603)
  x <- as.numeric(x)
  coastal_r5 <- c(1580:1586, 1591:1594, 1598, 1599)
  interior_r5 <- c(1587:1590, 1595:1597, 1600:1603)
  dplyr::case_when(
    x %in% coastal_r5  ~ 1,
    x %in% interior_r5 ~ 0,
    TRUE ~ NA_real_  # non-Tunisia codes
  )
}

recode_afro_coastal_tun_r6 <- function(x, ...) {
  # R6 governorate codes (DIFFERENT ORDER from R5):
  # Coastal: Tunis(1580), Ariana(1581), Manouba(1582), Ben Arous(1583),
  #   Sfax(1584), Sousse(1585), Nabeul(1586), Bizerte(1587),
  #   Zaghouan(1588), Monastir(1596), Mahdia(1597),
  #   Medenine(1598), Gabes(1601)
  # Interior: Sidi Bouzid(1589), Le Kef(1590), Kasserine(1591),
  #   Jendouba(1592), Beja(1593), Siliana(1594), Kairouan(1595),
  #   Tataouine(1599), Gafsa(1600), Tozeur(1602), Kebili(1603)
  x <- as.numeric(x)
  coastal_r6 <- c(1580:1588, 1596, 1597, 1598, 1601)
  interior_r6 <- c(1589:1595, 1599, 1600, 1602, 1603)
  dplyr::case_when(
    x %in% coastal_r6  ~ 1,
    x %in% interior_r6 ~ 0,
    TRUE ~ NA_real_
  )
}

# --- Coarse versions: Tataouine treated as coastal (matching R7-R8 region grouping) ---
# Used by tunisia_coastal (consistent across R5-R9)

recode_afro_coastal_tun_r5_coarse <- function(x, ...) {
  # R5: same as precise but Tataouine(1600) → coastal to match region grouping
  x <- as.numeric(x)
  coastal_r5 <- c(1580:1586, 1591:1594, 1598:1600)  # includes Tataouine
  interior_r5 <- c(1587:1590, 1595:1597, 1601:1603)
  dplyr::case_when(
    x %in% coastal_r5  ~ 1,
    x %in% interior_r5 ~ 0,
    TRUE ~ NA_real_
  )
}

recode_afro_coastal_tun_r6_coarse <- function(x, ...) {
  # R6: same as precise but Tataouine(1599) → coastal to match region grouping
  x <- as.numeric(x)
  coastal_r6 <- c(1580:1588, 1596:1599, 1601)  # includes Tataouine
  interior_r6 <- c(1589:1595, 1600, 1602, 1603)
  dplyr::case_when(
    x %in% coastal_r6  ~ 1,
    x %in% interior_r6 ~ 0,
    TRUE ~ NA_real_
  )
}

recode_afro_coastal_tun_r7r8 <- function(x, ...) {
  # R7-R8 region-level codes (no governorate resolution):
  # 1580=Great Tunis (coastal), 1581=North East (coastal),
  # 1582=North West (interior), 1583=Center East (coastal),
  # 1584=Center West (interior),
  # 1585=South East (coastal — but includes ~16 Tataouine interior respondents),
  # 1586=South West (interior)
  # WARNING: Tataouine misclassified as coastal (~16/wave)
  x <- as.numeric(x)
  coastal_r7 <- c(1580, 1581, 1583, 1585)
  interior_r7 <- c(1582, 1584, 1586)
  dplyr::case_when(
    x %in% coastal_r7  ~ 1,
    x %in% interior_r7 ~ 0,
    TRUE ~ NA_real_
  )
}

#' Recode R9 LOCATION.LEVEL.1 (character governorate names) to coastal/interior
recode_afro_coastal_tun_r9 <- function(x, ...) {
  x <- toupper(trimws(as.character(x)))
  coastal_names <- c("TUNIS", "ARIANA", "L'ARIANA", "BEN AROUS",
                     "MANOUBA", "NABEUL", "ZAGHOUAN", "BIZERTE",
                     "SOUSSE", "MONASTIR", "MAHDIA", "SFAX",
                     "GABES", "MEDENINE")
  interior_names <- c("BEJA", "JENDOUBA", "LE KEF", "KEF", "SILIANA",
                       "KAIROUAN", "KASSERINE", "SIDI BOUZID",
                       "GAFSA", "TOZEUR", "KEBILI", "TATAOUINE")
  dplyr::case_when(
    x %in% coastal_names  ~ 1,
    x %in% interior_names ~ 0,
    TRUE ~ NA_real_
  )
}

recode_arab_employment_w5w8 <- function(x, missing_codes = c(0, -1, -8, -9, 98, 99, 100, 997, 998, 999), ...) {
  # Q1005: 1=Employed, 2=Self-employed, 3=Retired, 4=Housewife,
  #         5=Student, 6=Unemployed, 7/90=Other
  x <- as.numeric(x)
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% 1:2 ~ 2,            # employed or self-employed
    x == 6 ~ 1,                 # unemployed
    x %in% c(3,4,5,7,90) ~ 0,  # OLF (retired, housewife, student, other)
    TRUE ~ NA_real_
  )
}
