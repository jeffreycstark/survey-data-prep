#!/usr/bin/env Rscript
# src/r/audit/05_threshold_calibration.R
#
# Layer 5 — Drift threshold calibration (audit ticket G3).
#
# G1's engine (05_drift_check.R) emitted one row per
# (variable × wave-pair × country) with a TVD or KS-D statistic. G3 reads
# that output, filters out bookkeeping variables that are wave-disjoint by
# design (idnumber, weights, etc.) and produces:
#
#   1. A histogram (audit/reports/<survey>/05-calibration.png) of the per-
#      country TVD distribution with vertical lines at the 95th and 99th
#      percentiles.
#   2. A thresholds JSON (audit/reports/<survey>/05-thresholds.json)
#      capturing percentile cutoffs for both per-country and pooled rows,
#      plus the recommended flag/block thresholds.
#
# Initial guidance (per the framework): flag at the 95th percentile of
# observed drifts; block at the 99th. Hand-tune later by editing the JSON.
#
# CLI:
#   Rscript src/r/audit/05_threshold_calibration.R --survey abs
#   Rscript src/r/audit/05_threshold_calibration.R --survey kgss
#   Rscript src/r/audit/05_threshold_calibration.R --all-surveys
#   Rscript src/r/audit/05_threshold_calibration.R --help
#
# Exit codes:
#   0 — calibration produced successfully
#   1 — invalid invocation, missing input CSV, or unrecoverable I/O error
#
# See audit/01-audit-framework.md §Layer 5 and audit/02-implementation-tickets.md ticket G3.

suppressPackageStartupMessages({
  library(here)
  library(jsonlite)
})

here::i_am("src/r/audit/05_threshold_calibration.R")


# ---------------------------------------------------------------------------
# Bookkeeping variables that are wave-disjoint by design and trivially
# produce TVD ≈ 1.0. Excluded from percentile computation so the calibrated
# thresholds reflect substantive drift, not respondent-id churn.
#
# `country` and `wave` are not output columns themselves but are listed
# defensively in case a future engine change leaks them in.
# ---------------------------------------------------------------------------
.DRIFT_BOOKKEEPING_VARS <- c(
  "idnumber", "int_month", "int_year", "year", "yr_resp_id",
  "resp_id", "weight", "weight_cross", "country", "wave"
)


# ---------------------------------------------------------------------------
# Surveys this script knows how to dispatch under --all-surveys.
# Mirrors 05_drift_check.R's .SUPPORTED_SURVEYS.
# ---------------------------------------------------------------------------
.SUPPORTED_SURVEYS <- c(
  "abs", "wvs", "lbs", "afro", "arab-barometer",
  "kamos", "kgss", "kipa_corruption", "kinu", "ipus"
)


# ---------------------------------------------------------------------------
# Help text
# ---------------------------------------------------------------------------
.print_help <- function() {
  cat(
    "Usage: Rscript src/r/audit/05_threshold_calibration.R --survey <name>\n",
    "       Rscript src/r/audit/05_threshold_calibration.R --all-surveys\n",
    "\n",
    "Reads audit/reports/<survey>/05-drift.csv (G1 output) and writes:\n",
    "  - audit/reports/<survey>/05-calibration.png\n",
    "  - audit/reports/<survey>/05-thresholds.json\n",
    "\n",
    "  --survey NAME      Survey slug (one of: ",
        paste(.SUPPORTED_SURVEYS, collapse = ", "), ").\n",
    "  --all-surveys      Run for every supported survey with a 05-drift.csv.\n",
    "  --output-dir PATH  Override output directory (default: audit/reports/<survey>).\n",
    "  -h, --help         Show this message.\n",
    "\n",
    "Exit 0 = calibration written. Exit 1 = bad invocation or missing input.\n",
    sep = ""
  )
}


# ---------------------------------------------------------------------------
# CLI parsing — same conventions as 05_drift_check.R / 04_strict_reversal.R.
# ---------------------------------------------------------------------------
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, all_surveys = FALSE, output_dir = NULL)
  i <- 1L
  while (i <= length(argv)) {
    a <- argv[i]
    if (a %in% c("-h", "--help"))   { .print_help(); quit(status = 0) }
    if (a == "--survey")            { out$survey      <- argv[i + 1L]; i <- i + 2L; next }
    if (a == "--all-surveys")       { out$all_surveys <- TRUE;          i <- i + 1L; next }
    if (a == "--output-dir")        { out$output_dir  <- argv[i + 1L]; i <- i + 2L; next }
    stop(sprintf("unknown argument: %s (see --help)", a), call. = FALSE)
  }
  if (!out$all_surveys && (is.null(out$survey) || !nzchar(out$survey))) {
    stop("--survey <name> or --all-surveys is required (see --help)", call. = FALSE)
  }
  out
}


# ---------------------------------------------------------------------------
# Compute percentiles at 90/95/99/99.5 for a numeric vector. Returns a
# named list with NA-valued slots when the input is empty (so the caller
# can still emit a JSON with a clear "no data" signal).
# ---------------------------------------------------------------------------
.compute_percentiles <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) {
    return(list(p90 = NA_real_, p95 = NA_real_, p99 = NA_real_, p99_5 = NA_real_))
  }
  q <- stats::quantile(x, probs = c(0.90, 0.95, 0.99, 0.995),
                       names = FALSE, type = 7L)
  list(p90 = unname(q[1]), p95 = unname(q[2]),
       p99 = unname(q[3]), p99_5 = unname(q[4]))
}


# ---------------------------------------------------------------------------
# Filter G1's CSV to substantive rows only:
#   - statistic is finite (drops the rare NA leak from G1)
#   - variable not in .DRIFT_BOOKKEEPING_VARS
# Returns the filtered data frame plus a count of the bookkeeping rows that
# were excluded — surfaced in the JSON for transparency.
# ---------------------------------------------------------------------------
.filter_substantive <- function(drift) {
  is_finite <- !is.na(drift$statistic) & is.finite(drift$statistic)
  keep <- is_finite & !(drift$variable %in% .DRIFT_BOOKKEEPING_VARS)
  list(
    data = drift[keep, , drop = FALSE],
    n_bookkeeping_excluded = sum(is_finite & drift$variable %in% .DRIFT_BOOKKEEPING_VARS),
    n_nonfinite = sum(!is_finite)
  )
}


# ---------------------------------------------------------------------------
# Render the calibration histogram. Per-country rows only (the substantive
# audit signal). ggplot2 if available; falls back to base R hist().
# ---------------------------------------------------------------------------
.write_calibration_plot <- function(stats, p95, p99, survey, png_path) {
  if (length(stats) == 0L) {
    # Nothing to plot — write a stub PNG with a message so the artifact
    # exists for downstream consumers.
    grDevices::png(png_path, width = 800, height = 600)
    on.exit(grDevices::dev.off(), add = TRUE)
    graphics::plot.new()
    graphics::title(main = sprintf("Drift distribution: %s (no data)", survey))
    graphics::text(0.5, 0.5, "No per-country drift rows after bookkeeping filter.")
    return(invisible(NULL))
  }

  has_ggplot <- requireNamespace("ggplot2", quietly = TRUE)

  if (has_ggplot) {
    df <- data.frame(statistic = stats)
    p <- ggplot2::ggplot(df, ggplot2::aes(x = .data$statistic)) +
      ggplot2::geom_histogram(bins = 50L, fill = "#4477AA",
                              colour = "white", linewidth = 0.2) +
      ggplot2::geom_vline(xintercept = p95, linetype = "dashed",
                          colour = "#EE6677", linewidth = 0.7) +
      ggplot2::geom_vline(xintercept = p99, linetype = "dashed",
                          colour = "#CC3311", linewidth = 0.7) +
      ggplot2::annotate("text", x = p95, y = Inf,
                        label = sprintf("p95 = %.3f", p95),
                        hjust = -0.05, vjust = 1.5,
                        colour = "#EE6677", size = 3.5) +
      ggplot2::annotate("text", x = p99, y = Inf,
                        label = sprintf("p99 = %.3f", p99),
                        hjust = -0.05, vjust = 3.0,
                        colour = "#CC3311", size = 3.5) +
      ggplot2::labs(
        title = sprintf("Drift distribution: %s", survey),
        subtitle = sprintf(
          "Per-country rows after bookkeeping filter (n = %d). Dashed lines = p95 (flag) / p99 (block).",
          length(stats)
        ),
        x = "Drift statistic (TVD or KS-D)",
        y = "Number of (variable x wave-pair x country) cells"
      ) +
      ggplot2::theme_minimal(base_size = 11)
    ggplot2::ggsave(png_path, plot = p, width = 800 / 96, height = 600 / 96,
                    dpi = 96, units = "in")
  } else {
    grDevices::png(png_path, width = 800, height = 600)
    on.exit(grDevices::dev.off(), add = TRUE)
    graphics::hist(
      stats, breaks = 50L, col = "#4477AA", border = "white",
      main = sprintf("Drift distribution: %s", survey),
      xlab = "Drift statistic (TVD or KS-D)",
      ylab = "Number of (variable x wave-pair x country) cells"
    )
    graphics::abline(v = p95, col = "#EE6677", lty = 2, lwd = 2)
    graphics::abline(v = p99, col = "#CC3311", lty = 2, lwd = 2)
    graphics::legend(
      "topright",
      legend = c(sprintf("p95 = %.3f (flag)", p95),
                 sprintf("p99 = %.3f (block)", p99)),
      col = c("#EE6677", "#CC3311"), lty = 2, lwd = 2, bty = "n"
    )
  }
  invisible(NULL)
}


# ---------------------------------------------------------------------------
# Public: compute thresholds for one survey's 05-drift.csv.
#
# Returns a list with the structure that ends up serialized to JSON.
# ---------------------------------------------------------------------------
calibrate_thresholds <- function(survey, drift_csv = NULL, output_dir = NULL) {
  if (is.null(output_dir)) {
    output_dir <- here::here("audit", "reports", survey)
  }
  if (is.null(drift_csv)) {
    drift_csv <- file.path(output_dir, "05-drift.csv")
  }
  if (!file.exists(drift_csv)) {
    stop(sprintf("drift CSV not found: %s (run G1 first: src/r/audit/05_drift_check.R --survey %s)",
                 drift_csv, survey), call. = FALSE)
  }

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  drift <- utils::read.csv(drift_csv, stringsAsFactors = FALSE,
                           na.strings = c("", "NA"))

  filt <- .filter_substantive(drift)
  d_subst <- filt$data

  is_pooled <- d_subst$country == "<pooled>"
  per_country <- d_subst[!is_pooled, , drop = FALSE]
  pooled      <- d_subst[ is_pooled, , drop = FALSE]

  # Single-country surveys: G1 emits only pooled rows. The per-country slot
  # is empty by construction; report that explicitly rather than NA-filling
  # silently.
  single_country <- nrow(per_country) == 0L && nrow(pooled) > 0L

  pct_per_country <- .compute_percentiles(per_country$statistic)
  pct_pooled      <- .compute_percentiles(pooled$statistic)

  # For multi-country surveys recommend per-country percentiles (the
  # tighter bound). For single-country surveys recommend pooled percentiles.
  if (single_country) {
    rec_flag  <- pct_pooled$p95
    rec_block <- pct_pooled$p99
    plot_stats <- pooled$statistic
    plot_p95 <- pct_pooled$p95
    plot_p99 <- pct_pooled$p99
  } else {
    rec_flag  <- pct_per_country$p95
    rec_block <- pct_per_country$p99
    plot_stats <- per_country$statistic
    plot_p95 <- pct_per_country$p95
    plot_p99 <- pct_per_country$p99
  }

  # Plot.
  png_path <- file.path(output_dir, "05-calibration.png")
  .write_calibration_plot(
    stats    = plot_stats,
    p95      = plot_p95,
    p99      = plot_p99,
    survey   = survey,
    png_path = png_path
  )

  # JSON.
  out <- list(
    survey = survey,
    n_observations_per_country = nrow(per_country),
    n_observations_pooled      = nrow(pooled),
    n_bookkeeping_excluded     = filt$n_bookkeeping_excluded,
    bookkeeping_vars_excluded  = .DRIFT_BOOKKEEPING_VARS,
    single_country             = single_country,
    per_country = list(
      p90   = pct_per_country$p90,
      p95   = pct_per_country$p95,
      p99   = pct_per_country$p99,
      p99_5 = pct_per_country$p99_5
    ),
    pooled = list(
      p90   = pct_pooled$p90,
      p95   = pct_pooled$p95,
      p99   = pct_pooled$p99,
      p99_5 = pct_pooled$p99_5
    ),
    recommended_flag_threshold  = rec_flag,
    recommended_block_threshold = rec_block,
    recommendation_basis        = if (single_country) "pooled" else "per_country",
    computed_at                 = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  )

  json_path <- file.path(output_dir, "05-thresholds.json")
  jsonlite::write_json(
    out, json_path, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null"
  )

  list(
    summary = out,
    png_path = png_path,
    json_path = json_path,
    per_country_n = nrow(per_country),
    pooled_n = nrow(pooled),
    bookkeeping_excluded = filt$n_bookkeeping_excluded,
    nonfinite_excluded = filt$n_nonfinite,
    top_substantive = .top_substantive(d_subst, n = 10L)
  )
}


# ---------------------------------------------------------------------------
# Pull the highest-drift NON-bookkeeping rows for the stdout summary.
# Returns a small data.frame.
# ---------------------------------------------------------------------------
.top_substantive <- function(d_subst, n = 10L) {
  if (nrow(d_subst) == 0L) return(d_subst)
  ord <- order(-d_subst$statistic)
  d <- d_subst[ord, , drop = FALSE]
  cols <- intersect(
    c("variable", "type", "wave_from", "wave_to", "country",
      "n_from", "n_to", "statistic", "stat_type"),
    names(d)
  )
  d[seq_len(min(n, nrow(d))), cols, drop = FALSE]
}


# ---------------------------------------------------------------------------
# Print the stdout summary requested in the ticket.
# ---------------------------------------------------------------------------
.print_summary <- function(survey, result) {
  s <- result$summary
  cat(sprintf("\n[threshold calibration] survey=%s\n", survey))
  cat(sprintf("  per-country rows:        %d\n", result$per_country_n))
  cat(sprintf("  pooled rows:             %d\n", result$pooled_n))
  cat(sprintf("  bookkeeping excluded:    %d (vars: %s)\n",
              result$bookkeeping_excluded,
              paste(.DRIFT_BOOKKEEPING_VARS, collapse = ", ")))
  if (result$nonfinite_excluded > 0L) {
    cat(sprintf("  non-finite excluded:     %d\n", result$nonfinite_excluded))
  }

  fmt_pct <- function(p) {
    if (is.na(p)) "    NA " else sprintf("%6.4f", p)
  }

  cat("\n  Percentiles:\n")
  cat(sprintf("    %-15s %8s %8s %8s %8s\n",
              "scope", "p90", "p95", "p99", "p99.5"))
  cat(sprintf("    %-15s %8s %8s %8s %8s\n",
              "per_country",
              fmt_pct(s$per_country$p90), fmt_pct(s$per_country$p95),
              fmt_pct(s$per_country$p99), fmt_pct(s$per_country$p99_5)))
  cat(sprintf("    %-15s %8s %8s %8s %8s\n",
              "pooled",
              fmt_pct(s$pooled$p90), fmt_pct(s$pooled$p95),
              fmt_pct(s$pooled$p99), fmt_pct(s$pooled$p99_5)))

  cat("\n  Recommended thresholds (basis: ", s$recommendation_basis, "):\n", sep = "")
  cat(sprintf("    flag  >= %s\n", fmt_pct(s$recommended_flag_threshold)))
  cat(sprintf("    block >= %s\n", fmt_pct(s$recommended_block_threshold)))

  if (s$single_country) {
    cat("\n  Note: single-country survey — per-country output is empty by\n",
        "  construction. Recommendation derived from pooled percentiles.\n",
        sep = "")
  }

  cat("\n  Outputs:\n")
  cat(sprintf("    %s\n", result$png_path))
  cat(sprintf("    %s\n", result$json_path))

  if (nrow(result$top_substantive) > 0L) {
    cat("\n  Top substantive (non-bookkeeping) drift rows:\n")
    print(result$top_substantive, row.names = FALSE, digits = 4)
  }

  cat("\n  Downstream consumers (G4 country-pattern, future merge gate)\n",
      "  should read 05-thresholds.json — do not hard-code these values.\n",
      sep = "")
}


# ---------------------------------------------------------------------------
# Public: run + print summary.
# ---------------------------------------------------------------------------
run_threshold_calibration <- function(survey, drift_csv = NULL, output_dir = NULL) {
  result <- calibrate_thresholds(survey = survey,
                                 drift_csv = drift_csv,
                                 output_dir = output_dir)
  .print_summary(survey, result)
  invisible(result)
}


# ---------------------------------------------------------------------------
# CLI main
# ---------------------------------------------------------------------------
.main <- function(argv) {
  args <- .parse_cli_args(argv)

  if (args$all_surveys) {
    surveys <- .SUPPORTED_SURVEYS
    cat(sprintf("[threshold calibration] running for %d surveys: %s\n",
                length(surveys), paste(surveys, collapse = ", ")))
    any_ok <- FALSE
    for (s in surveys) {
      ok <- tryCatch({
        run_threshold_calibration(survey = s, output_dir = args$output_dir)
        TRUE
      }, error = function(e) {
        cat(sprintf("\n[threshold calibration] survey '%s' SKIPPED: %s\n",
                    s, conditionMessage(e)))
        FALSE
      })
      any_ok <- any_ok || ok
    }
    if (!any_ok) quit(status = 1)
    return(invisible(NULL))
  }

  if (!(args$survey %in% .SUPPORTED_SURVEYS)) {
    stop(sprintf(
      "unknown survey '%s'. Supported: %s",
      args$survey, paste(.SUPPORTED_SURVEYS, collapse = ", ")
    ), call. = FALSE)
  }

  run_threshold_calibration(survey = args$survey, output_dir = args$output_dir)
}


if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) == 0L) {
    .print_help()
    quit(status = 1)
  }
  .main(argv)
}
