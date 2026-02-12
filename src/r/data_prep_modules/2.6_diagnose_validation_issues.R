# 2.6_diagnose_validation_issues.R
# Triage validation errors/warnings to help distinguish:
# - human/spec errors
# - miscoding/transform mistakes
# - data anomalies
#
# Usage:
#   Rscript src/r/data_prep_modules/2.6_diagnose_validation_issues.R

library(here)
library(yaml)
library(dplyr)
library(purrr)
library(tidyr)
library(haven)

source(here::here("src/r/utils/validation.R"))
source(here::here("src/r/data_prep_modules/0_load_waves.R"))
source(here::here("src/r/data_prep_modules/_yaml_utils.R"))
source(here::here("src/r/data_prep_modules/2.5_validate_harmonization.R"))

here::i_am("src/r/data_prep_modules/2.6_diagnose_validation_issues.R")

# -----------------------------
# Helpers
# -----------------------------

get_var_index <- function() {
  spec_files <- list_yaml_specs()
  index <- list()

  for (spec_file in spec_files) {
    spec <- yaml::read_yaml(spec_file)
    spec_name <- tools::file_path_sans_ext(basename(spec_file))

    for (var_spec in spec$variables) {
      missing_codes <- get_missing_codes(spec, var_spec)
      index[[var_spec$id]] <- list(
        var_spec = var_spec,
        missing_codes = missing_codes,
        spec_name = spec_name
      )
    }
  }

  index
}

harmonized_wave_id <- function(harmonized, wave_name) {
  if ("wave" %in% names(harmonized) && is.numeric(harmonized$wave)) {
    return(as.integer(sub("^w", "", wave_name)))
  }
  wave_name
}

compute_cor <- function(x, y, method = "pearson") {
  out <- suppressWarnings(tryCatch(
    cor(x, y, use = "complete.obs", method = method),
    error = function(e) NA_real_
  ))
  out
}

reverse_raw <- function(x, valid_range) {
  if (is.null(valid_range) || length(valid_range) != 2) {
    return(rep(NA_real_, length(x)))
  }
  min_val <- valid_range[1]
  max_val <- valid_range[2]
  (min_val + max_val) - x
}

classify_issue <- function(issue, raw_vec, harm_vec, valid_range, missing_codes) {
  checks <- issue$checks
  error_checks <- names(checks)[sapply(checks, function(x) x$status %in% c("error", "warn"))]

  raw_num <- suppressWarnings(as.numeric(raw_vec))
  harm_num <- suppressWarnings(as.numeric(harm_vec))

  raw_clean <- raw_num
  raw_clean[raw_clean %in% missing_codes] <- NA_real_

  harm_clean <- harm_num

  identity_cor <- compute_cor(raw_clean, harm_clean, method = "pearson")
  spearman_cor <- compute_cor(raw_clean, harm_clean, method = "spearman")
  reverse_cor <- compute_cor(reverse_raw(raw_clean, valid_range), harm_clean, method = "pearson")

  raw_unique <- length(unique(raw_clean[!is.na(raw_clean)]))
  harm_unique <- length(unique(harm_clean[!is.na(harm_clean)]))

  raw_missing_n <- sum(raw_num %in% missing_codes, na.rm = TRUE)
  raw_out_of_range_n <- NA_integer_
  harm_out_of_range_n <- NA_integer_

  if (!is.null(valid_range) && length(valid_range) == 2) {
    raw_out_of_range_n <- sum(
      !is.na(raw_num) &
      !(raw_num %in% missing_codes) &
      (raw_num < valid_range[1] | raw_num > valid_range[2])
    )
    harm_out_of_range_n <- sum(
      !is.na(harm_num) &
      (harm_num < valid_range[1] | harm_num > valid_range[2])
    )
  }

  likely_cause <- c()
  suggestion <- c()

  if ("length_check" %in% error_checks) {
    likely_cause <- c(likely_cause, "pipeline_length_mismatch")
    suggestion <- c(suggestion, "Check harmonization stacking and wave filtering.")
  }

  if ("coverage" %in% error_checks) {
    if (!is.na(raw_out_of_range_n) && raw_out_of_range_n > 0) {
      likely_cause <- c(likely_cause, "raw_out_of_range_or_missing_codes")
      suggestion <- c(suggestion, "Inspect raw codes; add to missing_conventions or update valid_range.")
    } else {
      likely_cause <- c(likely_cause, "coverage_loss")
      suggestion <- c(suggestion, "Check recode logic for dropped values.")
    }
  }

  if ("transformation" %in% error_checks) {
    if (!is.na(reverse_cor) && reverse_cor > 0.99) {
      likely_cause <- c(likely_cause, "needs_reverse")
      suggestion <- c(suggestion, "Expected reversal; adjust harmonize method for this wave.")
    } else if (!is.na(identity_cor) && identity_cor > 0.99) {
      likely_cause <- c(likely_cause, "should_be_identity")
      suggestion <- c(suggestion, "Likely no transformation needed for this wave.")
    } else if (!is.na(spearman_cor) && abs(spearman_cor) > 0.99) {
      likely_cause <- c(likely_cause, "monotonic_scale_mismatch")
      suggestion <- c(suggestion, "Scale conversion may be off; recheck recode function.")
    } else {
      likely_cause <- c(likely_cause, "transform_mismatch_or_data_anomaly")
      suggestion <- c(suggestion, "Inspect raw labels/value distributions for anomalies.")
    }
  }

  if ("range" %in% error_checks) {
    if (!is.na(harm_out_of_range_n) && harm_out_of_range_n > 0) {
      likely_cause <- c(likely_cause, "harm_out_of_range")
      suggestion <- c(suggestion, "Verify recode function or valid_range in YAML.")
    } else {
      likely_cause <- c(likely_cause, "range_spec_mismatch")
      suggestion <- c(suggestion, "Check YAML valid_range or wave-specific exceptions.")
    }
  }

  if ("crosstab" %in% error_checks) {
    if (checks$crosstab$missing_leaked %||% FALSE) {
      likely_cause <- c(likely_cause, "missing_codes_not_na")
      suggestion <- c(suggestion, "Ensure missing codes are treated as NA.")
    } else {
      likely_cause <- c(likely_cause, "one_to_many_mapping")
      suggestion <- c(suggestion, "Check recode function for non-deterministic mapping.")
    }
  }

  list(
    error_checks = error_checks,
    identity_cor = identity_cor,
    spearman_cor = spearman_cor,
    reverse_cor = reverse_cor,
    raw_unique = raw_unique,
    harm_unique = harm_unique,
    raw_missing_n = raw_missing_n,
    raw_out_of_range_n = raw_out_of_range_n,
    harm_out_of_range_n = harm_out_of_range_n,
    likely_cause = paste(unique(likely_cause), collapse = "; "),
    suggestion = paste(unique(suggestion), collapse = " ")
  )
}

# -----------------------------
# Run diagnosis
# -----------------------------

cat("Running validation (quiet)...\n")
validation_results <- run_validation(save_report = FALSE, verbose = FALSE)

issues <- validation_results[sapply(validation_results, function(r) r$status %in% c("warn", "error"))]

cat(sprintf("Found %d issues (warn/error)\n", length(issues)))

raw_waves <- load_waves()
harmonized <- load_harmonized_data()
var_index <- get_var_index()

issue_rows <- map_dfr(issues, function(issue) {
  var_id <- issue$var_id
  wave_name <- issue$wave

  idx <- var_index[[var_id]]
  if (is.null(idx)) {
    return(tibble(
      var_id = var_id,
      wave = wave_name,
      status = issue$status,
      error_checks = NA_character_,
      likely_cause = "spec_not_found",
      suggestion = "Check YAML specs for missing variable definition."
    ))
  }

  var_spec <- idx$var_spec
  missing_codes <- idx$missing_codes

  # Resolve source variable for this wave
  source_var <- var_spec$source[[wave_name]]

  # Extract vectors
  raw_data <- raw_waves[[wave_name]]
  harm_wave <- harmonized %>% dplyr::filter(wave == harmonized_wave_id(harmonized, wave_name))

  raw_vec <- if (!is.null(source_var) && source_var %in% names(raw_data)) raw_data[[source_var]] else NA
  harm_vec <- if (var_id %in% names(harm_wave)) harm_wave[[var_id]] else NA

  # Determine valid range
  valid_range <- var_spec$qc$valid_range_by_wave[[wave_name]] %||%
    var_spec$qc$valid_range %||% NULL

  diagnostics <- classify_issue(issue, raw_vec, harm_vec, valid_range, missing_codes)

  raw_label <- if (!is.null(raw_vec)) attr(raw_vec, "label") else NA_character_

  tibble(
    spec = idx$spec_name,
    var_id = var_id,
    wave = wave_name,
    source_var = source_var %||% NA_character_,
    status = issue$status,
    error_checks = paste(diagnostics$error_checks, collapse = ", "),
    likely_cause = diagnostics$likely_cause,
    suggestion = diagnostics$suggestion,
    raw_label = raw_label %||% NA_character_,
    identity_cor = diagnostics$identity_cor,
    spearman_cor = diagnostics$spearman_cor,
    reverse_cor = diagnostics$reverse_cor,
    raw_unique = diagnostics$raw_unique,
    harm_unique = diagnostics$harm_unique,
    raw_missing_n = diagnostics$raw_missing_n,
    raw_out_of_range_n = diagnostics$raw_out_of_range_n,
    harm_out_of_range_n = diagnostics$harm_out_of_range_n
  )
})

# Summary by cause
summary_by_cause <- issue_rows %>%
  group_by(likely_cause) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(desc(n))

# Write outputs
out_dir <- here::here("outputs")
out_csv <- file.path(out_dir, "harmonization_validation_triage.csv")
out_md <- file.path(out_dir, "harmonization_validation_triage.md")

readr::write_csv(issue_rows, out_csv)

md_lines <- c(
  "# Harmonization Validation Triage",
  "",
  sprintf("Generated: %s", Sys.time()),
  "",
  "## Summary by Likely Cause",
  ""
)

md_lines <- c(md_lines,
              paste0("- ", summary_by_cause$likely_cause, ": ", summary_by_cause$n))

md_lines <- c(md_lines, "", "## Issue Details", "")

issue_table <- issue_rows %>%
  select(spec, var_id, wave, source_var, status, error_checks, likely_cause, suggestion)

md_lines <- c(md_lines,
              paste0("| ", paste(names(issue_table), collapse = " | "), " |"),
              paste0("|", paste(rep("---", ncol(issue_table)), collapse = "|"), "|"))

apply(issue_table, 1, function(row) {
  md_lines <<- c(md_lines, paste0("| ", paste(row, collapse = " | "), " |"))
})

writeLines(md_lines, out_md)

cat("Triage report saved:\n")
cat("  -", out_csv, "\n")
cat("  -", out_md, "\n")
