# src/r/harmonize/validate_spec.R
# YAML specification validation for harmonization

# ---- Cached jsonvalidate validator (ticket B3) -------------------------------
# Module-local cache: avoid re-parsing the schema on every call. The ajv
# validator object is stable across calls, so harmonize_all_specs() (which
# invokes validate_harmonize_spec() once per spec across ~117 specs) parses
# the schema exactly once per R session.
.harmonize_validator_cache <- local({
  cache <- list(validator = NULL, schema_path = NULL)

  function(schema_path) {
    if (is.null(cache$validator) || !identical(cache$schema_path, schema_path)) {
      if (!file.exists(schema_path)) {
        stop(sprintf(
          "validate_harmonize_spec(): schema file not found at %s",
          schema_path
        ), call. = FALSE)
      }
      if (!requireNamespace("jsonvalidate", quietly = TRUE)) {
        stop("validate_harmonize_spec(): package 'jsonvalidate' is required",
             call. = FALSE)
      }
      cache$validator <<- jsonvalidate::json_validator(
        schema_path,
        engine = "ajv"
      )
      cache$schema_path <<- schema_path
    }
    cache$validator
  }
})

#' Validate harmonization YAML specification structure
#'
#' Thin wrapper around `jsonvalidate::json_validator()` (ticket B3). The
#' authoritative schema is `src/config/_schema/harmonize_v1.schema.json`.
#' Replaces the imperative `if (is.null(...))` validator that silently
#' accepted typos like `harmnoize:` because top-level keys were not
#' enforced. The schema declares `additionalProperties: false` at every
#' object level, so misspellings now fail loud with a JSON-path error.
#'
#' @param spec List: parsed YAML specification (from `yaml::read_yaml()`).
#' @param var_id Optional character: when supplied, only errors whose
#'   instance path falls inside `/variables/<idx>` for the matching id
#'   are reported. The full spec is still validated (cheap; the validator
#'   is cached) and errors are filtered post-hoc.
#'
#' @return Invisibly returns `TRUE` if valid; stops with a multi-line
#'   error message otherwise. Each error line carries the offending JSON
#'   path and the schema-derived message.
#'
#' @details
#' Implementation notes:
#' - YAML is converted to JSON via `jsonlite::toJSON(auto_unbox = TRUE,
#'   null = "null")`. The schema is written to tolerate the auto-unboxed
#'   shapes (length-1 arrays collapsed to scalars).
#' - The `ajv` engine is used because `imjv` does not implement
#'   `additionalProperties: false` strictly enough to catch misspelt
#'   top-level keys.
#' - `var_id` filtering is post-hoc: we validate the whole spec, then
#'   match each error's `instancePath` against the index of the variable
#'   whose `id:` equals `var_id`. If `var_id` is supplied but absent from
#'   the spec, an error is raised regardless of schema result.
#'
#' @export
validate_harmonize_spec <- function(spec, var_id = NULL) {

  schema_path <- here::here("src/config/_schema/harmonize_v1.schema.json")

  validator <- .harmonize_validator_cache(schema_path)

  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("validate_harmonize_spec(): package 'jsonlite' is required",
         call. = FALSE)
  }

  json_str <- jsonlite::toJSON(spec, auto_unbox = TRUE, null = "null")

  result <- validator(json_str, verbose = TRUE, greedy = TRUE)

  if (isTRUE(result)) {
    # If var_id was supplied, ensure the variable actually exists.
    if (!is.null(var_id)) {
      ids <- vapply(
        spec$variables %||% list(),
        function(v) v$id %||% NA_character_,
        character(1)
      )
      if (!var_id %in% ids) {
        stop(sprintf(
          "❌ Specification validation failed:\n\n  1. variables: variable id '%s' not found in spec\n",
          var_id
        ), call. = FALSE)
      }
    }
    return(invisible(TRUE))
  }

  errors_df <- attr(result, "errors")

  # Optional var_id filtering: keep only errors whose instancePath is
  # inside the matching /variables/<idx>/... subtree, plus any errors
  # outside /variables (top-level structural errors that affect the
  # whole spec and should still be surfaced).
  if (!is.null(var_id) && !is.null(errors_df) && nrow(errors_df) > 0) {
    ids <- vapply(
      spec$variables %||% list(),
      function(v) v$id %||% NA_character_,
      character(1)
    )
    idx <- match(var_id, ids) - 1L  # JSON pointer is 0-indexed
    if (is.na(idx)) {
      stop(sprintf(
        "❌ Specification validation failed:\n\n  1. variables: variable id '%s' not found in spec\n",
        var_id
      ), call. = FALSE)
    }
    var_prefix <- sprintf("/variables/%d", idx)
    paths <- errors_df$instancePath %||% character(nrow(errors_df))
    keep <- !startsWith(paths, "/variables/") |
      startsWith(paths, paste0(var_prefix, "/")) |
      paths == var_prefix
    errors_df <- errors_df[keep, , drop = FALSE]
    if (nrow(errors_df) == 0) {
      return(invisible(TRUE))
    }
  }

  # ---- Format errors ----
  error_msg <- "❌ Specification validation failed:\n\n"

  if (is.null(errors_df) || nrow(errors_df) == 0) {
    error_msg <- paste0(error_msg, "  1. (validator returned FALSE without details)\n")
  } else {
    paths    <- errors_df$instancePath %||% rep("", nrow(errors_df))
    messages <- errors_df$message      %||% rep("", nrow(errors_df))
    keywords <- errors_df$keyword      %||% rep("", nrow(errors_df))

    for (i in seq_len(nrow(errors_df))) {
      path <- if (nzchar(paths[i])) paths[i] else "<root>"
      msg  <- messages[i]
      # ajv's "additional properties" message omits the offending key from
      # the message itself; pull it from params$additionalProperty when
      # present so the error names the typo.
      if (identical(keywords[i], "additionalProperties")) {
        params <- errors_df$params
        extra <- NULL
        if (!is.null(params)) {
          if (is.data.frame(params) && "additionalProperty" %in% names(params)) {
            extra <- params$additionalProperty[[i]]
          } else if (is.list(params) && length(params) >= i) {
            extra <- params[[i]]$additionalProperty
          }
        }
        if (!is.null(extra) && nzchar(extra)) {
          msg <- sprintf("%s ('%s')", msg, extra)
        }
      }
      error_msg <- paste0(
        error_msg,
        sprintf("  %d. %s: %s\n", i, path, msg)
      )
    }
  }

  stop(error_msg, call. = FALSE)
}

# ---- Cached registry loader (ticket B4) --------------------------------------
# Module-local cache for the recoding-function registry. Mirrors the validator
# cache pattern used for the JSON Schema above: parse the YAML once per
# session, reuse the parsed list across calls. validate_cross_references()
# is invoked once per spec (e.g. ~117 times across all surveys), so this
# avoids redundant YAML parsing.
.recoding_registry_cache <- local({
  cache <- list(registry = NULL, registry_path = NULL)

  function(registry_path) {
    if (is.null(cache$registry) ||
        !identical(cache$registry_path, registry_path)) {
      if (!file.exists(registry_path)) {
        stop(sprintf(
          "validate_cross_references(): registry file not found at %s",
          registry_path
        ), call. = FALSE)
      }
      if (!requireNamespace("yaml", quietly = TRUE)) {
        stop("validate_cross_references(): package 'yaml' is required",
             call. = FALSE)
      }
      registry <- yaml::read_yaml(registry_path)
      registry_names <- vapply(
        registry,
        function(e) if (is.null(e$fn)) NA_character_ else e$fn,
        character(1)
      )
      cache$registry <<- registry_names[!is.na(registry_names)]
      cache$registry_path <<- registry_path
    }
    cache$registry
  }
})

#' Validate cross-references in a harmonization spec
#'
#' Performs post-schema integrity checks that JSON Schema cannot express
#' (cross-references between fields, or across multiple specs). Run AFTER
#' `validate_harmonize_spec()` — assumes the spec is structurally valid.
#'
#' Checks performed:
#'
#'   (a) Every `var$missing$use_convention` (if set) is a key in
#'       `spec$missing_conventions`.
#'   (b) Every `harmonize.<rule>.fn` (across default + by_wave + exceptions +
#'       direct wave keys) for `method: r_function` or `method: derive` is
#'       present in the recoding-function registry
#'       (src/r/utils/recoding_registry.yml).
#'   (c) No two variables in `spec$variables` share the same `id:`.
#'   (d) When `all_specs_in_survey` is supplied, the same `id:` declared in
#'       multiple specs must have consistent `type:` and
#'       `qc$expected_direction:`.
#'
#' @param spec List: parsed YAML specification (already passed
#'   `validate_harmonize_spec()`).
#' @param all_specs_in_survey Optional list of parsed specs. When supplied,
#'   enables check (d). Pass NULL (default) to skip cross-spec consistency.
#' @param registry_path Optional override of the recoding-registry path.
#'   Defaults to `here::here("src/r/utils/recoding_registry.yml")`.
#'
#' @return Invisibly returns `TRUE` if all checks pass; stops with a
#'   multi-line error message otherwise. Header is
#'   `❌ Cross-reference validation failed:`, followed by one line per
#'   violation.
#'
#' @export
validate_cross_references <- function(spec,
                                      all_specs_in_survey = NULL,
                                      registry_path = NULL) {

  violations <- character()

  # ---- (a) missing.use_convention resolves -----------------------------------
  conv_keys <- names(spec$missing_conventions %||% list())

  for (var_spec in spec$variables %||% list()) {
    use_conv <- var_spec$missing$use_convention
    if (is.null(use_conv) || !nzchar(use_conv)) next
    if (!use_conv %in% conv_keys) {
      violations <- c(violations, sprintf(
        "variable '%s': use_convention '%s' is not a key in missing_conventions (available: %s)",
        var_spec$id %||% "<unknown>",
        use_conv,
        if (length(conv_keys) > 0) paste(conv_keys, collapse = ", ") else "<none>"
      ))
    }
  }

  # ---- (b) fn: names exist in registry ---------------------------------------
  if (is.null(registry_path)) {
    registry_path <- here::here("src/r/utils/recoding_registry.yml")
  }
  registry_names <- .recoding_registry_cache(registry_path)

  reserved <- c("default", "by_wave", "exceptions")

  collect_fn_violations <- function(rule, var_id, where) {
    if (is.null(rule) || is.null(rule$method)) return()
    if (!rule$method %in% c("r_function", "derive")) return()
    fn_name <- rule$fn
    if (is.null(fn_name) || !is.character(fn_name) || !nzchar(fn_name)) return()
    if (!fn_name %in% registry_names) {
      violations <<- c(violations, sprintf(
        "variable '%s' (%s): fn '%s' is not in the recoding registry (%s)",
        var_id, where, fn_name, registry_path
      ))
    }
  }

  for (var_spec in spec$variables %||% list()) {
    var_id <- var_spec$id %||% "<unknown>"
    h <- var_spec$harmonize
    if (is.null(h)) next

    collect_fn_violations(h$default, var_id, "default")

    for (wave_name in names(h$by_wave %||% list())) {
      collect_fn_violations(h$by_wave[[wave_name]], var_id,
                            sprintf("by_wave.%s", wave_name))
    }
    for (wave_name in names(h$exceptions %||% list())) {
      collect_fn_violations(h$exceptions[[wave_name]], var_id,
                            sprintf("exceptions.%s", wave_name))
    }
    for (key in setdiff(names(h), reserved)) {
      collect_fn_violations(h[[key]], var_id, key)
    }
  }

  # ---- (c) duplicate id within this spec -------------------------------------
  ids <- vapply(
    spec$variables %||% list(),
    function(v) v$id %||% NA_character_,
    character(1)
  )
  ids <- ids[!is.na(ids)]
  dup_ids <- unique(ids[duplicated(ids)])
  for (dup in dup_ids) {
    violations <- c(violations, sprintf(
      "duplicate id '%s' declared %d times within this spec",
      dup, sum(ids == dup)
    ))
  }

  # ---- (d) cross-spec consistency (when all_specs supplied) ------------------
  if (!is.null(all_specs_in_survey)) {

    # Build map: id -> list of (type, expected_direction) tuples observed.
    id_attrs <- list()
    for (other_spec in all_specs_in_survey) {
      for (var_spec in other_spec$variables %||% list()) {
        vid <- var_spec$id
        if (is.null(vid) || !nzchar(vid)) next
        entry <- list(
          type = var_spec$type %||% NA_character_,
          expected_direction = var_spec$qc$expected_direction %||% NA_character_
        )
        id_attrs[[vid]] <- c(id_attrs[[vid]] %||% list(), list(entry))
      }
    }

    # Restrict to ids declared in THIS spec — we report conflicts that affect
    # the current spec's contract.
    this_ids <- unique(ids)
    for (vid in this_ids) {
      occurrences <- id_attrs[[vid]]
      if (is.null(occurrences) || length(occurrences) <= 1) next

      types <- unique(unlist(lapply(occurrences, `[[`, "type")))
      types <- types[!is.na(types)]
      if (length(types) > 1) {
        violations <- c(violations, sprintf(
          "id '%s' declared with conflicting type across specs: %s",
          vid, paste(types, collapse = " vs ")
        ))
      }

      dirs <- unique(unlist(lapply(occurrences, `[[`, "expected_direction")))
      dirs <- dirs[!is.na(dirs)]
      if (length(dirs) > 1) {
        violations <- c(violations, sprintf(
          "id '%s' declared with conflicting expected_direction across specs: %s",
          vid, paste(dirs, collapse = " vs ")
        ))
      }
    }
  }

  # ---- Format & raise --------------------------------------------------------
  if (length(violations) == 0) {
    return(invisible(TRUE))
  }

  error_msg <- "❌ Cross-reference validation failed:\n\n"
  for (i in seq_along(violations)) {
    error_msg <- paste0(error_msg, sprintf("  %d. %s\n", i, violations[i]))
  }
  stop(error_msg, call. = FALSE)
}

#' Validate a spec structurally and via cross-reference checks
#'
#' Convenience wrapper: runs `validate_harmonize_spec()` (JSON Schema) and
#' then `validate_cross_references()` (post-schema integrity). This is what
#' `harmonize_spec()` in `2_harmonize_all.R` should call.
#'
#' @param spec List: parsed YAML specification.
#' @param all_specs_in_survey Optional list of parsed specs (enables
#'   cross-spec consistency check d). See `validate_cross_references()`.
#'
#' @return Invisibly `TRUE` on success; stops on first failure.
#' @export
validate_spec_full <- function(spec, all_specs_in_survey = NULL) {
  validate_harmonize_spec(spec)
  validate_cross_references(spec, all_specs_in_survey = all_specs_in_survey)
  invisible(TRUE)
}

#' Validate variable labels contain expected phrases
#'
#' Checks that source variables in each wave have labels containing
#' the expected phrase from qc$validate. This catches wrong variable mappings.
#'
#' @param spec List: parsed YAML specification
#' @param waves List: named list of wave dataframes (w1, w2, etc.)
#' @param verbose Logical: print results as they're checked
#'
#' @return List with:
#'   - passed: tibble of successful validations
#'   - failed: tibble of failed validations (label doesn't contain phrase)
#'   - missing: tibble of variables that couldn't be checked (no label or var not found)
#'
#' @export
validate_phrases <- function(spec, waves, verbose = TRUE) {

  results <- list(
    passed = list(),
    failed = list(),
    missing = list()
  )

  # Iterate through each variable in spec
  for (var_spec in spec$variables) {

    var_id <- var_spec$id
    validate_rules <- var_spec$qc$validate

    # Skip if no validate rules
    if (is.null(validate_rules)) next

    # Process each validate rule
    for (rule in validate_rules) {

      phrase <- rule$phrase
      rule_waves <- rule$waves

      # Skip if no phrase specified
      if (is.null(phrase)) next

      # Check each wave in this rule
      for (wave_name in rule_waves) {

        # Get source variable name for this wave
        source_var <- var_spec$source[[wave_name]]

        # Skip if source is null (variable not in this wave)
        if (is.null(source_var)) next

        # Check if wave exists
        if (!wave_name %in% names(waves)) {
          results$missing[[length(results$missing) + 1]] <- list(
            var_id = var_id,
            wave = wave_name,
            source_var = source_var,
            phrase = phrase,
            reason = "Wave not loaded"
          )
          next
        }

        wave_data <- waves[[wave_name]]

        # Check if variable exists in wave
        if (!source_var %in% names(wave_data)) {
          results$missing[[length(results$missing) + 1]] <- list(
            var_id = var_id,
            wave = wave_name,
            source_var = source_var,
            phrase = phrase,
            reason = "Variable not found in wave"
          )
          next
        }

        # Get variable label
        var_label <- attr(wave_data[[source_var]], "label")

        if (is.null(var_label) || var_label == "") {
          results$missing[[length(results$missing) + 1]] <- list(
            var_id = var_id,
            wave = wave_name,
            source_var = source_var,
            phrase = phrase,
            reason = "No label found"
          )
          next
        }

        # Check if label contains phrase (case-insensitive regex)
        if (grepl(phrase, var_label, ignore.case = TRUE)) {
          results$passed[[length(results$passed) + 1]] <- list(
            var_id = var_id,
            wave = wave_name,
            source_var = source_var,
            phrase = phrase,
            label = var_label
          )
        } else {
          results$failed[[length(results$failed) + 1]] <- list(
            var_id = var_id,
            wave = wave_name,
            source_var = source_var,
            phrase = phrase,
            label = var_label
          )
        }
      }
    }
  }

  # Convert to tibbles
  results$passed <- if (length(results$passed) > 0) {
    dplyr::bind_rows(results$passed)
  } else {
    dplyr::tibble(var_id = character(), wave = character(),
                  source_var = character(), phrase = character(), label = character())
  }

  results$failed <- if (length(results$failed) > 0) {
    dplyr::bind_rows(results$failed)
  } else {
    dplyr::tibble(var_id = character(), wave = character(),
                  source_var = character(), phrase = character(), label = character())
  }

  results$missing <- if (length(results$missing) > 0) {
    dplyr::bind_rows(results$missing)
  } else {
    dplyr::tibble(var_id = character(), wave = character(),
                  source_var = character(), phrase = character(), reason = character())
  }

  # Print summary if verbose
  if (verbose) {
    n_passed <- nrow(results$passed)
    n_failed <- nrow(results$failed)
    n_missing <- nrow(results$missing)

    cat(sprintf("\n=== Phrase Validation Results ===\n"))
    cat(sprintf("✅ Passed:  %d\n", n_passed))
    cat(sprintf("❌ Failed:  %d\n", n_failed))
    cat(sprintf("⚠️  Missing: %d\n", n_missing))

    if (n_failed > 0) {
      cat("\n❌ FAILED validations (label doesn't contain phrase):\n")
      for (i in seq_len(nrow(results$failed))) {
        row <- results$failed[i, ]
        cat(sprintf("   %s (%s): '%s' not in label\n",
                    row$var_id, row$wave, row$phrase))
        cat(sprintf("      Source: %s\n", row$source_var))
        cat(sprintf("      Label:  %s\n", substr(row$label, 1, 80)))
      }
    }

    if (n_missing > 0 && n_missing <= 20) {
      cat("\n⚠️  Could not validate (missing label or variable):\n")
      for (i in seq_len(nrow(results$missing))) {
        row <- results$missing[i, ]
        cat(sprintf("   %s (%s → %s): %s\n",
                    row$var_id, row$wave, row$source_var, row$reason))
      }
    } else if (n_missing > 20) {
      cat(sprintf("\n⚠️  %d variables could not be validated (use results$missing for details)\n",
                  n_missing))
    }
  }

  results
}


#' Validate all YAML specs against wave data
#'
#' Runs phrase validation for all YAML specs in a directory.
#' Spec discovery is delegated to `find_survey_spec_dir()` /
#' `list_survey_specs()` (see `src/r/utils/spec_discovery.R`).
#'
#' @param waves List: named list of wave dataframes
#' @param survey Survey name (default "abs"). Resolved via the spec-discovery
#'   utility — ABS reads `harmonize/`, every other survey reads
#'   `harmonize/`. Pass NULL to use an explicit `config_dir` instead.
#' @param config_dir Optional: explicit path to a spec directory. Overrides
#'   `survey` when non-NULL. Retained for back-compat with callers that
#'   passed a directory directly.
#' @param verbose Print progress
#'
#' @return List of validation results by spec name
#'
#' @export
validate_all_specs <- function(waves,
                               survey = "abs",
                               config_dir = NULL,
                               verbose = TRUE) {

  # Lazy-source spec_discovery.R so this file stays usable even if a
  # caller sources only validate_spec.R directly.
  if (!exists("list_survey_specs", mode = "function") ||
      !exists("find_survey_spec_dir", mode = "function")) {
    source(here::here("src/r/utils/spec_discovery.R"))
  }

  if (is.null(config_dir)) {
    yaml_files <- list_survey_specs(survey)
  } else {
    # Back-compat path: caller supplied an explicit directory.
    yaml_files <- list.files(config_dir, pattern = "\\.yml$", full.names = TRUE)
    exclude <- c("MODEL_VARIABLE", "TEMPLATE", "README")
    yaml_files <- yaml_files[!grepl(paste(exclude, collapse = "|"),
                                    basename(yaml_files), ignore.case = TRUE)]
  }

  all_results <- list()
  total_passed <- 0
  total_failed <- 0
  total_missing <- 0

  for (yml_path in yaml_files) {
    spec_name <- tools::file_path_sans_ext(basename(yml_path))

    if (verbose) {
      cat(sprintf("\nValidating: %s\n", spec_name))
    }

    spec <- yaml::read_yaml(yml_path)
    result <- validate_phrases(spec, waves, verbose = FALSE)

    all_results[[spec_name]] <- result
    total_passed <- total_passed + nrow(result$passed)
    total_failed <- total_failed + nrow(result$failed)
    total_missing <- total_missing + nrow(result$missing)

    if (verbose && nrow(result$failed) > 0) {
      cat(sprintf("  ❌ %d failed validations\n", nrow(result$failed)))
      for (i in seq_len(min(5, nrow(result$failed)))) {
        row <- result$failed[i, ]
        cat(sprintf("     - %s (%s): '%s' not found\n",
                    row$var_id, row$wave, row$phrase))
      }
    }
  }

  if (verbose) {
    cat(sprintf("\n=== TOTAL SUMMARY ===\n"))
    cat(sprintf("Specs validated: %d\n", length(yaml_files)))
    cat(sprintf("✅ Passed:  %d\n", total_passed))
    cat(sprintf("❌ Failed:  %d\n", total_failed))
    cat(sprintf("⚠️  Missing: %d\n", total_missing))
  }

  all_results
}


#' Check if recoding functions exist (and are catalogued in the registry)
#'
#' Validates that every r_function/derive rule referenced by the spec —
#' across the default rule and all wave-specific rules under by_wave,
#' exceptions, or direct wave keys — names a function loaded in the
#' calling environment. Mirrors the resolution order used by
#' harmonize_variable() / resolve_wave_rule().
#'
#' Additionally checks the recoding-function registry
#' (src/r/utils/recoding_registry.yml, ticket A4 / framework CC2). Functions
#' referenced by `fn:` but missing from the registry are returned as a
#' separate set, exposed via the `not_in_registry` attribute on the result.
#' Callers that only inspect `length(result)` continue to work unchanged.
#'
#' @param spec List: parsed YAML specification
#' @param registry_path Optional path to recoding_registry.yml. If NULL, the
#'   function tries `src/r/utils/recoding_registry.yml` relative to cwd, and
#'   falls back to `here::here(...)` if the `here` package is available.
#'   Pass `NA` to skip the registry check entirely.
#'
#' @return Character vector of missing function names — i.e. names referenced
#'   by `fn:` that do not resolve to a loaded function (current behaviour).
#'   Two attributes on the return value extend this without breaking callers:
#'     `not_in_registry`: character vector of `fn:` names that ARE loaded but
#'         have no entry in recoding_registry.yml (Layer 1 audit signal).
#'     `registry_checked`: logical scalar — TRUE if the registry was found
#'         and read, FALSE if it was skipped (e.g. file not found).
#'
#' @export
check_recoding_functions <- function(spec, registry_path = NULL) {

  missing_fns <- character()
  referenced_fns <- character()

  collect_fn <- function(rule) {
    if (is.null(rule) || is.null(rule$method)) return()
    if (!rule$method %in% c("r_function", "derive")) return()
    fn_name <- rule$fn
    if (is.null(fn_name) || !nzchar(fn_name)) return()
    referenced_fns <<- c(referenced_fns, fn_name)
    if (!exists(fn_name, mode = "function")) {
      missing_fns <<- c(missing_fns, fn_name)
    }
  }

  # Wave keys NOT to treat as wave-rules at the top level of `harmonize`
  reserved <- c("default", "by_wave", "exceptions")

  for (var_id in names(spec$variables)) {
    var_spec <- spec$variables[[var_id]]
    h <- var_spec$harmonize
    if (is.null(h)) next

    collect_fn(h$default)

    for (wave_name in names(h$by_wave %||% list())) {
      collect_fn(h$by_wave[[wave_name]])
    }
    for (wave_name in names(h$exceptions %||% list())) {
      collect_fn(h$exceptions[[wave_name]])
    }
    # v3 format: harmonize.<wave_name> as direct keys
    for (key in setdiff(names(h), reserved)) {
      collect_fn(h[[key]])
    }
  }

  out <- unique(missing_fns)

  # ---- Registry cross-check (Layer 1 / ticket A4) ----
  not_in_registry <- character()
  registry_checked <- FALSE

  if (!identical(registry_path, NA)) {
    if (is.null(registry_path)) {
      candidate <- "src/r/utils/recoding_registry.yml"
      if (!file.exists(candidate) && requireNamespace("here", quietly = TRUE)) {
        candidate <- here::here("src/r/utils/recoding_registry.yml")
      }
      registry_path <- candidate
    }
    if (file.exists(registry_path) && requireNamespace("yaml", quietly = TRUE)) {
      registry <- yaml::read_yaml(registry_path)
      registry_names <- vapply(
        registry,
        function(e) if (is.null(e$fn)) NA_character_ else e$fn,
        character(1)
      )
      registry_names <- registry_names[!is.na(registry_names)]
      # Only flag fns that DO resolve to a function but aren't catalogued —
      # missing-from-loaded (already in `out`) is the more critical signal.
      loaded_referenced <- setdiff(unique(referenced_fns), missing_fns)
      not_in_registry <- setdiff(loaded_referenced, registry_names)
      registry_checked <- TRUE
    }
  }

  attr(out, "not_in_registry") <- unique(not_in_registry)
  attr(out, "registry_checked") <- registry_checked
  out
}
