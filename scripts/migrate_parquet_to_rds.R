#!/usr/bin/env Rscript
#' Migrate parquet outputs to RDS (materialized, arrow-independent)
#'
#' The project standardizes harmonized outputs on .rds. A few files in
#' data/processed/ exist ONLY as .parquet with no .rds sibling (e.g. wvs, kgss).
#' This re-saves each as a genuine .rds.
#'
#' IMPORTANT: a .parquet renamed to .rds is still Arrow binary and readRDS()
#' cannot open it. AND arrow returns lazy zero-copy (ALTREP) columns by default,
#' which, if saved directly, only reload when arrow is attached and read as EMPTY
#' in plain R. So we disable ALTREP and force full materialization to base-R
#' vectors before saving, then VERIFY the columns actually carry their rows.
#'
#' Usage:
#'   Rscript scripts/migrate_parquet_to_rds.R                         # orphans only
#'   Rscript scripts/migrate_parquet_to_rds.R --force                 # also refresh existing .rds (ALL parquets)
#'   Rscript scripts/migrate_parquet_to_rds.R --force --only wvs_harmonized,kgss_harmonized
#'   Rscript scripts/migrate_parquet_to_rds.R --dry-run
#'
#' --only <a,b>  restrict to parquets whose filename contains any of these (comma-sep).
#' The .parquet files are left in place. Re-runnable.

options(arrow.use_altrep = FALSE)   # force materialized base-R vectors, not lazy views

cmd_all <- commandArgs(trailingOnly = FALSE)
args    <- commandArgs(trailingOnly = TRUE)
force   <- "--force"   %in% args
dry_run <- "--dry-run" %in% args

get_val <- function(flag) {
  i <- which(args == flag)
  if (length(i) && i[1] < length(args)) args[i[1] + 1] else NA_character_
}
only_raw <- get_val("--only")
only     <- if (!is.na(only_raw)) trimws(strsplit(only_raw, ",")[[1]]) else character(0)

need_arrow <- function() {
  if (!requireNamespace("arrow", quietly = TRUE))
    stop("Package 'arrow' is required to read the parquet files. install.packages('arrow')")
}

this_file <- sub("^--file=", "", grep("^--file=", cmd_all, value = TRUE))
repo_root <- if (length(this_file)) {
  normalizePath(file.path(dirname(this_file), ".."))
} else if (requireNamespace("here", quietly = TRUE)) {
  here::here()
} else {
  normalizePath(getwd())
}
proc_dir <- file.path(repo_root, "data", "processed")
if (!dir.exists(proc_dir)) stop("Could not find data/processed at: ", proc_dir)

cat("\n=== parquet -> rds migration (materialized) ===\n")
cat("processed dir:", proc_dir, "\n")
cat("mode:", if (dry_run) "DRY RUN" else if (force) "convert + refresh existing" else "convert orphans only", "\n")
if (length(only)) cat("only:", paste(only, collapse = ", "), "\n")
cat("\n")

parquets <- list.files(proc_dir, pattern = "\\.parquet$", full.names = TRUE)
if (length(only)) {
  parquets <- parquets[vapply(parquets, function(p)
    any(vapply(only, function(o) grepl(o, basename(p), fixed = TRUE), logical(1))), logical(1))]
}
if (!length(parquets)) { cat("No matching .parquet files. Nothing to do.\n"); quit(status = 0) }

to_do <- Filter(function(pq) force || !file.exists(sub("\\.parquet$", ".rds", pq)), parquets)
if (length(to_do) && !dry_run) need_arrow()

converted <- character(); skipped <- character(); failed <- character()

for (pq in parquets) {
  rds <- sub("\\.parquet$", ".rds", pq)
  has_rds <- file.exists(rds)

  if (has_rds && !force) {
    skipped <- c(skipped, basename(pq))
    cat(sprintf("  skip   %-40s (.rds already exists; use --force to refresh)\n", basename(pq)))
    next
  }

  action <- if (has_rds) "refresh" else "create "
  if (dry_run) {
    cat(sprintf("  %s%-40s -> %s\n", action, basename(pq), basename(rds)))
    converted <- c(converted, basename(rds)); next
  }

  ok <- tryCatch({
    df <- as.data.frame(arrow::read_parquet(pq))   # altrep already disabled above
    df[] <- lapply(df, function(x) x[])             # belt-and-suspenders: force materialization
    saveRDS(df, rds)
    chk <- readRDS(rds)                              # verify CONTENT, not just dims
    col_ok <- ncol(chk) > 0 && length(chk[[1]]) == nrow(chk)
    if (!col_ok) stop(sprintf("columns did not materialize (first col length %d vs %d rows)",
                              length(chk[[1]]), nrow(chk)))
    cat(sprintf("  %s%-40s -> %s  [%s x %s, cols carry rows: OK]\n",
                action, basename(pq), basename(rds),
                format(nrow(chk), big.mark = ","), ncol(chk)))
    TRUE
  }, error = function(e) { cat("  ERROR ", basename(pq), ": ", conditionMessage(e), "\n", sep = ""); FALSE })

  if (ok) converted <- c(converted, basename(rds)) else failed <- c(failed, basename(pq))
}

cat("\n--- summary ---\n")
cat("converted:", length(converted), if (length(converted)) paste0("(", paste(converted, collapse = ", "), ")") else "", "\n")
cat("skipped (already had .rds):", length(skipped), "\n")
if (length(failed)) cat("FAILED:", paste(failed, collapse = ", "), "\n")
cat("\nDone.", if (dry_run) " (dry run - nothing written)" else "", "\n\n", sep = "")
