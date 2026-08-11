# src/r/harmonize/harmonize.R
# Core functions for cross-wave variable harmonization

# ==============================================================================
# HELPER OPERATORS AND FUNCTIONS
# ==============================================================================

#' Null coalescing operator
#'
#' Returns first non-null value (alternative if left side is NULL)
`%||%` <- function(a, b) {
  if (!is.null(a)) a else b
}

#' Clean missing codes to NA
#'
#' @param x Numeric vector
#' @param missing_codes Codes to treat as NA
#' @return Vector with missing codes converted to NA
apply_missing <- function(x, missing_codes) {
  if (length(missing_codes) == 0) {
    return(x)
  }
  x[x %in% missing_codes] <- NA_real_
  x
}

#' Resolve the harmonization rule for a given wave
#'
#' Walks the documented YAML format precedence:
#'   v1: harmonize.by_wave.<wave>
#'   v2: harmonize.exceptions.<wave>
#'   v3: harmonize.<wave>           (direct wave keys)
#'   fallback: harmonize.default
#'
#' Centralized so harmonize_variable() and validate_variable_wave()
#' agree on rule resolution. If a v4 format is added, change here only.
#'
#' @param var_spec One YAML variable entry
#' @param wave_name Wave identifier (e.g., "w1", "y2013", "2018")
#' @return List with at least `method`; never NULL (falls back to identity)
# ---- input-domain guard (2026-08-11) -----------------------------------------
# The class of bug this kills: a transform applied to a wave whose raw item has
# a different response format (a Yes/No wave through safe_reverse_4pt recorded
# No as "Sometimes"; a 5-category wave identity-mapped onto a 6-category scale
# misfiled 531 people). None of that is visible to the range gate because the
# outputs are in-range. The guard compares the OBSERVED substantive codes in
# the wave's data against the rule's expected input domain, before transforming.
# Report-only: findings go to outputs/<survey>/domain_log.csv via `domain_log`.

# Known input domains for named recoding helpers. Grow as needed; fns not
# listed (and derive rules) are skipped, not guessed.
.FN_INPUT_DOMAIN <- list(
  recode_6pt_freq_to_4pt      = 1:6,
  collapse_6pt_to_4pt_reverse = 1:6,
  recode_binary_yes_no        = 1:2
)

.rule_input_domain <- function(wave_rule, var_spec) {
  m <- wave_rule$method %||% "identity"
  if (identical(m, "identity")) {
    lo <- suppressWarnings(as.numeric(var_spec$scale$min))
    hi <- suppressWarnings(as.numeric(var_spec$scale$max))
    if (!is.na(lo) && !is.na(hi) && hi >= lo) return(seq(lo, hi)) else return(NULL)
  }
  if (identical(m, "recode")) {
    k <- suppressWarnings(as.numeric(names(wave_rule$mapping)))
    k <- k[!is.na(k)]
    return(if (length(k)) sort(k) else NULL)
  }
  if (identical(m, "r_function")) {
    fn <- wave_rule$fn %||% ""
    hit <- regmatches(fn, regexec("^safe_(?:reverse_)?([0-9])pt(?:_none)?$", fn))[[1]]
    if (length(hit) == 2) return(seq_len(as.integer(hit[2])))
    return(.FN_INPUT_DOMAIN[[fn]])
  }
  NULL
}

.check_input_domain <- function(x, wave_rule, var_spec, wave_name, src, domain_log) {
  if (is.null(domain_log)) return(invisible(NULL))
  domain <- .rule_input_domain(wave_rule, var_spec)
  if (is.null(domain)) return(invisible(NULL))
  obs <- sort(unique(x[!is.na(x)]))
  if (!length(obs)) return(invisible(NULL))

  status <- NULL
  outside <- setdiff(obs, domain)
  unused_top <- sum(domain > max(obs))
  if (length(outside)) {
    status <- "outside_domain"
    detail <- sprintf("observed codes outside the rule's input domain: %s",
                      paste(outside, collapse = ","))
  } else if (unused_top >= 2) {
    # the format-seam signature: the wave never reaches the top of the domain
    # (Yes/No data under a 4-pt transform observes only 1..2)
    status <- "underuses_domain"
    detail <- sprintf("observed %s..%s but domain runs to %s — format seam?",
                      min(obs), max(obs), max(domain))
  }
  if (is.null(status)) return(invisible(NULL))

  domain_log$records[[length(domain_log$records) + 1L]] <- data.frame(
    variable = var_spec$id %||% NA_character_, wave = wave_name, source_var = src,
    method = wave_rule$method %||% "identity", fn = wave_rule$fn %||% "",
    domain = paste(range(domain), collapse = ".."),
    observed = paste(range(obs), collapse = ".."),
    n_obs_values = length(obs), status = status, detail = detail,
    stringsAsFactors = FALSE
  )
  if (identical(status, "outside_domain")) {
    warning(sprintf("[domain] %s %s: %s", var_spec$id %||% "?", wave_name, detail),
            call. = FALSE)
  }
  invisible(NULL)
}

resolve_wave_rule <- function(var_spec, wave_name) {
  default_rule <- var_spec$harmonize$default %||% list(method = "identity")
  var_spec$harmonize$by_wave[[wave_name]] %||%
    var_spec$harmonize$exceptions[[wave_name]] %||%
    var_spec$harmonize[[wave_name]] %||%
    default_rule
}

# ==============================================================================
# MAIN HARMONIZATION ENGINE
# ==============================================================================

#' Harmonize a variable across waves using YAML specification
#'
#' Takes a variable specification (from YAML) and applies harmonization rules
#' to produce a harmonized variable across all waves.
#'
#' @param var_spec List: one YAML variable entry with fields:
#'   - id: variable identifier
#'   - source: list(w1="q001", w2="q1", ...)
#'   - missing: list(use_convention="treat_as_na")
#'   - harmonize: list(default=..., by_wave=...)
#'   - qc: list(valid_range_by_wave=...)
#'
#' @param waves List of named data frames: list(w1=df1, w2=df2, ...)
#'
#' @param missing_conventions Named list of missing code vectors
#'   e.g. list(treat_as_na = c(-1, 0, 7, 8, 9))
#'
#' @return List of harmonized vectors, one per wave:
#'   list(w1 = numeric(n1), w2 = numeric(n2), ...)
#'
#' @details
#' Harmonization workflow:
#' 1. Extract source variable from wave data
#' 2. Convert to numeric, apply missing code handling
#' 3. Select harmonization rule (default or wave-specific)
#' 4. Apply method:
#'    - "identity": pass through
#'    - "r_function": call recoding function (e.g., safe_reverse_5pt)
#' 5. QC: check valid range and coerce out-of-range values to NA
#'
#' @examples
#' \dontrun{
#' # Load YAML spec and wave data
#' spec <- yaml::read_yaml("src/config/abs/harmonize/economy.yml")
#' waves <- list(
#'   w1 = readRDS("data/processed/w1.rds"),
#'   w2 = readRDS("data/processed/w2.rds")
#' )
#'
#' # Harmonize one variable
#' econ <- harmonize_variable(
#'   var_spec = spec$variables[["econ_national_now"]],
#'   waves = waves,
#'   missing_conventions = spec$missing_conventions
#' )
#'
#' # econ$w1, econ$w2, ... are harmonized vectors
#' }
#'
#' @export
harmonize_variable <- function(
  var_spec,
  waves,
  missing_conventions,
  oob_log = NULL,
  domain_log = NULL
) {

  out <- list()

  # ---- pre-flight: detect probable missing wave entries ----
  # If a wave is NOT in var_spec$source, but a raw variable referenced in
  # OTHER waves' source mappings exists in this wave's data with valid
  # responses, warn — likely a forgotten YAML entry that produces silent NA.
  # Skips when skip_unmapped_check: true is set in var_spec$qc.
  if (!isTRUE(var_spec$qc$skip_unmapped_check)) {
    mapped_srcs <- unique(unlist(var_spec$source, use.names = FALSE))
    mapped_srcs <- mapped_srcs[!is.na(mapped_srcs) & nzchar(mapped_srcs)]
    for (wave_name in names(waves)) {
      if (wave_name %in% names(var_spec$source)) next
      df <- waves[[wave_name]]
      for (src_name in mapped_srcs) {
        if (!(src_name %in% names(df))) next
        col <- df[[src_name]]
        if (inherits(col, "haven_labelled")) col <- haven::zap_labels(col)
        n_valid <- if (is.character(col)) {
          sum(!is.na(col) & nzchar(col))
        } else {
          v <- suppressWarnings(as.numeric(col))
          sum(!is.na(v) & !(v %in% c(-1, -8)))
        }
        if (n_valid > 0) {
          warning(sprintf(
            "[harmonize] %s: wave '%s' is unmapped but raw var '%s' exists with %d valid values — probable missing source entry (output will be NA for this wave)",
            var_spec$id, wave_name, src_name, n_valid
          ), call. = FALSE)
          break  # one warning per missing wave is enough
        }
      }
    }
  }

  for (wave_name in names(waves)) {

    df <- waves[[wave_name]]

    # ---- extract source variable ----
    src <- var_spec$source[[wave_name]]

    if (is.null(src) || !src %in% names(df)) {
      # Source variable doesn't exist in this wave - return all NA
      out[[wave_name]] <- rep(NA_real_, nrow(df))
      next
    }

    # Convert to numeric (handle haven_labelled from SPSS imports)
    # Exception: preserve character columns when recode function expects strings
    x <- df[[src]]
    if (inherits(x, "haven_labelled")) {
      x <- as.numeric(haven::zap_labels(x))
    } else if (is.character(x)) {
      # Keep as character — recode function handles conversion
    } else {
      x <- suppressWarnings(as.numeric(x))
    }

    # ---- apply missing code handling ----
    # Each variable MUST explicitly declare which named missing-code
    # convention to use; the engine no longer falls back to a default.
    # See audit Phase F4 (commit Phase-F4-Step2): an implicit fallback
    # was masking ~2,000 undeclared missing codes across ABS/KINU/IPUS.
    miss_convention_key <- var_spec$missing$use_convention
    if (is.null(miss_convention_key)) {
      stop(sprintf(
        "Variable '%s' has no missing.use_convention declared. Each variable must explicitly state which missing-code convention to use (no implicit defaults).",
        var_spec$id
      ), call. = FALSE)
    }
    missing_codes <- numeric(0)

    if (!is.null(missing_conventions[[miss_convention_key]])) {
      convention <- missing_conventions[[miss_convention_key]]
      # Handle both direct vector and nested structure with 'codes' field
      if (is.list(convention) && !is.null(convention$codes)) {
        missing_codes <- as.numeric(convention$codes)
      } else {
        missing_codes <- as.numeric(convention)
      }
    }

    if (!is.null(var_spec$missing$codes)) {
      missing_codes <- unique(c(
        missing_codes,
        as.numeric(var_spec$missing$codes)
      ))
    }

    # qc.treat_as_na is in harmonize_v1.schema.json and documented as
    # "Engine appends these to the convention codes" (the KINU pattern), but
    # nothing read it. 47 variables relied on it; they were rescued only by the
    # valid_range gate, which logs them as out-of-range instead of missing.
    if (!is.null(var_spec$qc$treat_as_na)) {
      missing_codes <- unique(c(
        missing_codes,
        as.numeric(var_spec$qc$treat_as_na)
      ))
    }

    if (!is.character(x)) {
      x <- apply_missing(x, missing_codes)
    }

    # ---- select harmonization rule ----
    wave_rule <- resolve_wave_rule(var_spec, wave_name)

    # ---- input-domain guard (report-only) ----
    .check_input_domain(x, wave_rule, var_spec, wave_name, src, domain_log)

    # ---- apply harmonization method ----
    # `method: null` is valid per the schema ("do nothing / not mapped"), but
    # NULL == "identity" is logical(0) and `if (logical(0))` is an error, so the
    # variable used to die and get swallowed by the caller's tryCatch. Treat it
    # as an unmapped wave, exactly like a null source.
    if (is.null(wave_rule$method)) {

      out[[wave_name]] <- rep(NA_real_, nrow(df))
      next

    } else if (wave_rule$method == "identity") {

      # No transformation
      x_harm <- x

    } else if (wave_rule$method == "r_function") {

      fn_name <- wave_rule$fn
      if (!exists(fn_name, mode = "function")) {
        stop("❌ Recoding function not found: ", fn_name)
      }

      fn <- get(fn_name, mode = "function")

      # Call function with full wave data for semantic validation
      x_harm <- fn(
        x,
        data = df,
        var_name = src,
        validate_all = wave_rule$validate_all %||% NULL
      )

    } else if (wave_rule$method == "recode") {

      # Apply explicit value mapping from YAML
      # mapping: {1: 1, 2: 0, 3: null, 4: null}
      mapping <- wave_rule$mapping
      if (is.null(mapping)) {
        stop("❌ method 'recode' requires a 'mapping' field")
      }

      x_harm <- rep(NA_real_, length(x))

      for (from_val in names(mapping)) {
        to_val <- mapping[[from_val]]
        from_num <- as.numeric(from_val)

        if (is.null(to_val)) {
          # null in YAML means map to NA
          x_harm[x == from_num & !is.na(x)] <- NA_real_
        } else {
          # Map to the specified value
          x_harm[x == from_num & !is.na(x)] <- as.numeric(to_val)
        }
      }

      # Preserve NA from source
      x_harm[is.na(x)] <- NA_real_

    } else if (wave_rule$method == "derive") {

      # Derive method: compute from multiple source columns
      # Uses 'sources' list and 'fn' function name
      fn_name <- wave_rule$fn
      if (!exists(fn_name, mode = "function")) {
        stop("❌ Derive function not found: ", fn_name)
      }

      fn <- get(fn_name, mode = "function")

      # Call function with full wave data (function accesses needed columns)
      x_harm <- fn(
        data = df,
        wave_name = wave_name,
        sources = wave_rule$sources %||% NULL
      )

    } else {
      stop("❌ Unknown harmonization method: ", wave_rule$method)
    }

    # ---- QC: range check and coerce out-of-range to NA ----
    # Check for skip_range_check flag (for IDs and other unconstrained values)
    skip_range <- isTRUE(var_spec$qc$skip_range_check)

    # Check for valid_range (global) or valid_range_by_wave (wave-specific)
    vr <- var_spec$qc$valid_range_by_wave[[wave_name]] %||%
          var_spec$qc$valid_range %||%
          NULL

    if (skip_range) {
      # Explicitly skip range validation - no warning needed
    } else if (is.null(vr)) {
      # Warn if no valid_range specified - may miss bad data
      warning(
        sprintf("⚠️  %s (%s): No valid_range in qc - using defaults may miss bad values",
                var_spec$id, wave_name),
        call. = FALSE
      )
    } else {
      # Count and coerce out-of-range values to NA
      bad <- !is.na(x_harm) & (x_harm < vr[1] | x_harm > vr[2])
      if (any(bad)) {
        obs_min <- min(x_harm[bad], na.rm = TRUE)
        obs_max <- max(x_harm[bad], na.rm = TRUE)
        message(
          sprintf("   %s (%s): Converting %d out-of-range values to NA [valid: %s-%s, observed: %s-%s]",
                  var_spec$id, wave_name, sum(bad), vr[1], vr[2], obs_min, obs_max)
        )
        if (!is.null(oob_log)) {
          oob_log$records <- c(oob_log$records, list(data.frame(
            variable  = var_spec$id,
            wave      = wave_name,
            n_oob     = sum(bad),
            obs_min   = obs_min,
            obs_max   = obs_max,
            valid_min = vr[1],
            valid_max = vr[2],
            stringsAsFactors = FALSE
          )))
        }
        x_harm[bad] <- NA_real_
      }
    }

    # ---- attach per-variable provenance attribute (C3) ----
    # Records the lineage of this harmonized vector. Caller-populated fields
    # (source_file, spec_path, run_id) start as NA_character_; harmonize_spec()
    # fills spec_path, and stack_harmonized_wide() (or another caller) fills
    # run_id. source_file is left NA at this layer because the engine reads
    # from preprocessed RDS, not raw .sav — the manifest writer (C2/C5) owns
    # raw-input lineage.
    attr(x_harm, "provenance") <- list(
      variable_id = var_spec$id,
      source_file = NA_character_,
      source_var  = src,
      wave        = wave_name,
      method      = wave_rule$method,
      fn          = wave_rule$fn %||% NA_character_,
      spec_path   = NA_character_,
      run_id      = NA_character_
    )

    out[[wave_name]] <- x_harm
  }

  out
}

#' Harmonize multiple variables from YAML specification
#'
#' Applies harmonize_variable() to all variables in a YAML spec,
#' returning a list with one element per variable.
#'
#' @param spec List: parsed YAML specification
#' @param waves List of named data frames
#' @param silent Logical: suppress messages?
#'
#' @return List of harmonized variables:
#'   list(econ_national_now = list(w1=..., w2=..., ...),
#'        politics_trust = list(w1=..., w2=..., ...))
#'
#' @export
harmonize_all <- function(spec, waves, silent = FALSE) {

  # Pre-flight: catch r_function/derive typos before we start the loop,
  # so a misspelled fn: surfaces once at the top instead of per-variable.
  missing_fns <- check_recoding_functions(spec)
  if (length(missing_fns) > 0) {
    stop(
      "❌ YAML references recoding functions that aren't loaded:\n  ",
      paste(missing_fns, collapse = ", "),
      "\nSource src/r/utils/_load_functions.R, or check for typos in `fn:` fields.",
      call. = FALSE
    )
  }

  results <- list()

  # `variables:` is a YAML array in every production spec, so names() is NULL
  # and this loop returned an empty list without erroring. Take the id from the
  # entry itself; the legacy named-map form keeps working via the %||%.
  for (i in seq_along(spec$variables)) {

    var_spec <- spec$variables[[i]]
    var_id <- var_spec$id %||% names(spec$variables)[i]

    if (!silent) {
      message(sprintf("Harmonizing: %s", var_id))
    }

    tryCatch({
      results[[var_id]] <- harmonize_variable(
        var_spec = var_spec,
        waves = waves,
        missing_conventions = spec$missing_conventions
      )
    }, error = function(e) {
      warning(sprintf("❌ %s: %s", var_id, e$message), call. = FALSE)
    })
  }

  results
}

# ==============================================================================
# DERIVED VARIABLE FUNCTIONS
# Functions for computing variables from multiple source columns
# ==============================================================================

#' Compute procedural preference index from 4-set battery
#'
#' Sums procedural choices across 4 forced-choice sets measuring
#' procedural vs substantive democracy conceptions.
#'
#' @param data Data frame containing source columns
#' @param wave_name Wave identifier (w3, w4, w6)
#' @param sources List of source column names (q85-q88 or q88-q91)
#'
#' @return Numeric vector with 0-4 index (count of procedural choices)
#'
#' @details
#' Recode rules for each set:
#'   Set 1: {2,4}->1 (elections, expression), {1,3}->0 (redistribution, efficiency)
#'   Set 2: {1,3}->1 (oversight, organize), {2,4}->0 (basic needs, services)
#'   Set 3: {2,4}->1 (media, multiparty), {1,3}->0 (law-order, jobs)
#'   Set 4: {1,3}->1 (protests, courts), {2,4}->0 (anticorruption, unemployment)
#'
#' @export
compute_procedural_index <- function(data, wave_name = NULL, sources = NULL) {

  # Get source column names from YAML or use defaults by wave
  if (is.null(sources)) {
    sources <- switch(wave_name,
      w3 = c("q85", "q86", "q87", "q88"),
      w4 = c("q88", "q89", "q90", "q91"),
      w6 = c("q85", "q86", "q87", "q88"),
      stop("Unknown wave for procedural index: ", wave_name)
    )
  }

  # Helper to convert to numeric
  to_num <- function(x) {
    if (inherits(x, "haven_labelled")) {
      as.numeric(haven::zap_labels(x))
    } else {
      suppressWarnings(as.numeric(x))
    }
  }

  # Extract source columns
  s1 <- to_num(data[[sources[1]]])
  s2 <- to_num(data[[sources[2]]])
  s3 <- to_num(data[[sources[3]]])
  s4 <- to_num(data[[sources[4]]])

  # Recode each set: 1 = procedural choice, 0 = substantive choice
  # Set 1: 2,4 = procedural; 1,3 = substantive
  r1 <- dplyr::case_when(s1 %in% c(2, 4) ~ 1L, s1 %in% c(1, 3) ~ 0L, TRUE ~ NA_integer_)
  # Set 2: 1,3 = procedural; 2,4 = substantive
  r2 <- dplyr::case_when(s2 %in% c(1, 3) ~ 1L, s2 %in% c(2, 4) ~ 0L, TRUE ~ NA_integer_)
  # Set 3: 2,4 = procedural; 1,3 = substantive
  r3 <- dplyr::case_when(s3 %in% c(2, 4) ~ 1L, s3 %in% c(1, 3) ~ 0L, TRUE ~ NA_integer_)
  # Set 4: 1,3 = procedural; 2,4 = substantive
  r4 <- dplyr::case_when(s4 %in% c(1, 3) ~ 1L, s4 %in% c(2, 4) ~ 0L, TRUE ~ NA_integer_)

  # Sum: 0-4 index
  index <- r1 + r2 + r3 + r4

  as.numeric(index)
}
