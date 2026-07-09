#' Cross-survey education harmonization
#'
#' Every survey stores education on its own native ladder. `education_5cat` is
#' the one column that means the same thing everywhere:
#'
#'   1 = No formal schooling
#'   2 = Primary (incomplete or complete)
#'   3 = Secondary (incomplete or complete)
#'   4 = Post-secondary / some university, no degree
#'   5 = University degree (complete) or post-graduate
#'
#' This file is the single definition of that mapping. It exists because the
#' mapping used to live as four copy-pasted `case_when()` blocks inside
#' individual `99_create_final_dataset.R` scripts, and they drifted: the
#' Afrobarometer copy mapped `education_detailed %in% 8:9 -> 5` while a missing-
#' code convention deleted 8 and 9 upstream, so category 5 never occurred and
#' 16,172 degree-holders were filed as "some university" or dropped (fixed
#' 2026-07-09). One definition, one place, tests next door.
#'
#' DO NOT use `education_level_01` to compare surveys. It is a min-max rescale
#' of each survey's OWN ladder, so its step size differs (ABS 1/9, Afro 1/3,
#' WVS 1/5). Use `education_5cat_01()` instead, which is built from the shared
#' 5-category scale and therefore means the same thing everywhere.
#'
#' Tests: src/r/utils/test_education.R

# ---------------------------------------------------------------------------
# Per-survey native ladder -> shared 5-category scale
# ---------------------------------------------------------------------------

#' ABS `education_level` (1-10) -> education_5cat
#'
#' 1=No formal; 2-3=Primary; 4-7=Secondary; 8=Post-sec/some uni; 9-10=Uni+postgrad
edu5_from_abs <- function(education_level) {
  dplyr::case_when(
    education_level == 1        ~ 1L,
    education_level %in% 2:3    ~ 2L,
    education_level %in% 4:7    ~ 3L,
    education_level == 8        ~ 4L,
    education_level %in% 9:10   ~ 5L,
    TRUE                        ~ NA_integer_
  )
}

#' Afrobarometer -> education_5cat
#'
#' Prefers the 0-9 `education_detailed` ladder. R1 has no detailed item, so it
#' falls back to the 0-3 condensed `education_level`, where "post-secondary" (3)
#' cannot distinguish a degree from some university — it maps to 4, never 5.
#'
#' 0-1=No formal/informal; 2-3=Primary; 4-5=Secondary; 6-7=Post-sec/some uni;
#' 8-9=University completed / post-graduate.
edu5_from_afro <- function(education_detailed, education_level) {
  dplyr::case_when(
    !is.na(education_detailed) & education_detailed %in% 0:1 ~ 1L,
    !is.na(education_detailed) & education_detailed %in% 2:3 ~ 2L,
    !is.na(education_detailed) & education_detailed %in% 4:5 ~ 3L,
    !is.na(education_detailed) & education_detailed %in% 6:7 ~ 4L,
    !is.na(education_detailed) & education_detailed %in% 8:9 ~ 5L,
    # R1 fallback: condensed 0-3 only. 3 = "post-secondary" is ambiguous
    # between levels 4 and 5; we take the conservative 4.
    is.na(education_detailed) & education_level == 0 ~ 1L,
    is.na(education_detailed) & education_level == 1 ~ 2L,
    is.na(education_detailed) & education_level == 2 ~ 3L,
    is.na(education_detailed) & education_level == 3 ~ 4L,
    TRUE ~ NA_integer_
  )
}

#' Latinobarómetro `education_level` (REEDUC 1-7) -> education_5cat
#'
#' 1=No studies; 2-3=Primary; 4-5=Secondary; 6=Incomplete higher; 7=Complete higher
edu5_from_lbs <- function(education_level) {
  dplyr::case_when(
    education_level == 1      ~ 1L,
    education_level %in% 2:3  ~ 2L,
    education_level %in% 4:5  ~ 3L,
    education_level == 6      ~ 4L,
    education_level == 7      ~ 5L,
    TRUE                      ~ NA_integer_
  )
}

#' KGSS `education` (0-8) -> education_5cat
#'
#' 0=no formal, 1=elementary, 2=junior high, 3=high school, 4=junior college,
#' 5=college, 6=masters, 7=PhD, 8=OTHER.
#'
#' Code 8 is "other", NOT a level above PhD. It must become NA, never 5, and it
#' must never be fed to a min-max rescale — `normalize_01(education)` would rank
#' "other" above a doctorate. Junior college (4) is a completed tertiary
#' qualification below a bachelor's, so it maps to 4 (post-secondary), while
#' college/masters/PhD (5-7) are degree holders.
edu5_from_kgss <- function(education) {
  dplyr::case_when(
    education == 0       ~ 1L,
    education == 1       ~ 2L,
    education %in% 2:3   ~ 3L,
    education == 4       ~ 4L,
    education %in% 5:7   ~ 5L,
    education == 8       ~ NA_integer_,   # "other" — not orderable
    TRUE                 ~ NA_integer_
  )
}

#' WVS `education_level` (harmonized 1-6) -> education_5cat
#'
#' The WVS six-level ladder splits secondary into incomplete (3) and complete
#' (4); the shared scale merges them.
edu5_from_wvs <- function(education_level) {
  dplyr::case_when(
    education_level == 1      ~ 1L,
    education_level == 2      ~ 2L,
    education_level %in% 3:4  ~ 3L,
    education_level == 5      ~ 4L,
    education_level == 6      ~ 5L,
    TRUE                      ~ NA_integer_
  )
}

# ---------------------------------------------------------------------------
# Shared 0-1 rescale
# ---------------------------------------------------------------------------

#' education_5cat (1-5) -> 0-1, comparable ACROSS surveys.
#'
#' Unlike `education_level_01`, this is anchored to the shared 5-category scale,
#' so 0.5 means "secondary" in every survey.
edu5_to_01 <- function(education_5cat) {
  out <- (as.numeric(education_5cat) - 1) / 4
  out[education_5cat < 1 | education_5cat > 5] <- NA_real_
  out
}
