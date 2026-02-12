# R/recoding.R
# Recoding functions for Asian Barometer analysis

safe_reverse_3pt <- function(x,
                              data = NULL,
                              var_name = NULL,
                              missing_codes = c(-1, 0, 7, 8, 9),
                              validate_all = NULL) {

  # ---- semantic validation (optional but recommended) ----
  if (!is.null(validate_all)) {

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
  }

  # ---- reversal logic ----
  dplyr::case_when(
    x %in% 1:3 ~ 4 - x,
    x %in% missing_codes ~ NA_real_,
    TRUE ~ NA_real_
  )
}

safe_reverse_4pt <- function(x,
                              data = NULL,
                              var_name = NULL,
                              missing_codes = c(-1, 0, 7, 8, 9),
                              validate_all = NULL) {

  # ---- semantic validation (optional but recommended) ----
  if (!is.null(validate_all)) {

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
  }

  # ---- reversal logic ----
  dplyr::case_when(
    x %in% 1:4 ~ 5 - x,
    x %in% missing_codes ~ NA_real_,
    TRUE ~ NA_real_
  )
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

  # ---- semantic validation (optional but recommended) ----
  if (!is.null(validate_all)) {

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
  }

  # ---- reversal logic ----
  dplyr::case_when(
    x %in% 1:5 ~ 6 - x,
    x %in% missing_codes ~ NA_real_,
    TRUE ~ NA_real_
  )
}

# ==============================================================================
# IDENTITY FUNCTIONS (NO REVERSAL, ONLY MISSING CODE HANDLING)
# ==============================================================================

safe_3pt_none <- function(x,
                           data = NULL,
                           var_name = NULL,
                           missing_codes = c(-1, 0, 7, 8, 9),
                           validate_all = NULL) {

  # ---- semantic validation (optional but recommended) ----
  if (!is.null(validate_all)) {

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
  }

  # ---- identity logic (no reversal) ----
  dplyr::case_when(
    x %in% 1:3 ~ as.numeric(x),
    x %in% missing_codes ~ NA_real_,
    TRUE ~ NA_real_
  )
}

safe_4pt_none <- function(x,
                           data = NULL,
                           var_name = NULL,
                           missing_codes = c(-1, 0, 7, 8, 9),
                           validate_all = NULL) {

  # ---- semantic validation (optional but recommended) ----
  if (!is.null(validate_all)) {

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
  }

  # ---- identity logic (no reversal) ----
  dplyr::case_when(
    x %in% 1:4 ~ as.numeric(x),
    x %in% missing_codes ~ NA_real_,
    TRUE ~ NA_real_
  )
}

safe_5pt_none <- function(x,
                           data = NULL,
                           var_name = NULL,
                           missing_codes = c(-1, 0, 7, 8, 9),
                           validate_all = NULL) {

  # ---- semantic validation (optional but recommended) ----
  if (!is.null(validate_all)) {

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
  }

  # ---- identity logic (no reversal) ----
  dplyr::case_when(
    x %in% 1:5 ~ as.numeric(x),
    x %in% missing_codes ~ NA_real_,
    TRUE ~ NA_real_
  )
}

# ==============================================================================
# 6-POINT SCALE FUNCTIONS
# ==============================================================================

safe_reverse_6pt <- function(x,
                              data = NULL,
                              var_name = NULL,
                              missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                              validate_all = NULL) {

  # ---- semantic validation (optional but recommended) ----
  if (!is.null(validate_all)) {

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
  }

  # ---- reversal logic ----
  dplyr::case_when(
    x %in% 1:6 ~ 7 - x,
    x %in% missing_codes ~ NA_real_,
    TRUE ~ NA_real_
  )
}

safe_6pt_none <- function(x,
                           data = NULL,
                           var_name = NULL,
                           missing_codes = c(-1, 0, 7, 8, 9, 97, 98, 99),
                           validate_all = NULL) {

  # ---- semantic validation (optional but recommended) ----
  if (!is.null(validate_all)) {

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
  }

  # ---- identity logic (no reversal) ----
  dplyr::case_when(
    x %in% 1:6 ~ as.numeric(x),
    x %in% missing_codes ~ NA_real_,
    TRUE ~ NA_real_
  )
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
  if (!is.null(validate_all)) {

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
  }

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
  if (!is.null(validate_all)) {

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
  }

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
  if (!is.null(validate_all)) {

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
  }

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
  if (!is.null(validate_all)) {

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
  }

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
# ------------------------------------------------------------------------------

recode_w3_witnessed <- function(x,
                                 missing_codes = c(-1, 0, 7, 8, 9),
                                 ...) {
  #' Recode Wave 3 witnessed corruption (q119) to binary
  #'
  #' Wave 3 has:
  #'   1 = Witnessed
  #'   2 = Never witnessed
  #'   6 = No one I know has personally witnessed
  #'
  #' Target binary: 1=Yes, 2=No
  #' Mapping: 1->1, 2->2, 6->2

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x == 1 ~ 1,           # Witnessed -> Yes
    x %in% c(2, 6) ~ 2,   # Never witnessed / No one I know -> No
    TRUE ~ NA_real_
  )
}

recode_w4_witnessed <- function(x,
                                 missing_codes = c(-1, 0, 7, 8, 9),
                                 ...) {
  #' Recode Wave 4 witnessed corruption (q120) to binary
  #'
  #' Wave 4 has 5 categories:
  #'   1 = Personally witnessed
  #'   2 = Told about it by a family member who personally witnessed
  #'   3 = Told about it by a friend who personally witnessed
  #'   4 = Personally never witnessed
  #'   5 = No one I know has personally witnessed
  #'
  #' Target binary: 1=Yes (any witnessing), 2=No
  #' Mapping: 1,2,3->1, 4,5->2

  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% c(1, 2, 3) ~ 1,  # Any form of witnessed -> Yes
    x %in% c(4, 5) ~ 2,      # Never witnessed -> No
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
  if (!is.null(validate_all)) {

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
  }

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
  # Try to get original Date from data if available
  if (!is.null(data) && !is.null(var_name) && var_name %in% names(data)) {
    orig <- data[[var_name]]
    if (inherits(orig, "Date")) {
      months <- as.integer(format(orig, "%m"))
      years <- as.integer(format(orig, "%Y"))
      # Filter out obviously wrong dates
      months[years < 2000 | years > 2030] <- NA_integer_
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
extract_year_from_date <- function(x,
                                   data = NULL,
                                   var_name = NULL,
                                   validate_all = NULL) {
  # Try to get original Date from data if available
  if (!is.null(data) && !is.null(var_name) && var_name %in% names(data)) {
    orig <- data[[var_name]]
    if (inherits(orig, "Date")) {
      years <- as.integer(format(orig, "%Y"))
      # Filter out obviously wrong dates
      years[years < 2000 | years > 2030] <- NA_integer_
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

  # If nothing works, return NA
  rep(NA_real_, length(x))
}
