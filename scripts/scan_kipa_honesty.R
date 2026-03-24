library(haven)

files <- list.files("data/kipa/raw", pattern="[.]sav$", full.names=TRUE, ignore.case=TRUE)
files <- sort(files)

for (f in files) {
  year <- regmatches(basename(f), regexpr("[0-9]{4}", basename(f)))
  d <- read_sav(f)
  labs <- sapply(d, function(x) attr(x, "label"))

  cat(sprintf("=== %s (%d x %d) ===\n", year, nrow(d), ncol(d)))

  # Find honesty/integrity battery (청렴)
  hon_idx <- grep("청렴", labs)
  if (length(hon_idx) > 0) {
    cat(sprintf("  청렴도 (honesty): %d items\n", length(hon_idx)))
    for (i in hon_idx[1:min(3, length(hon_idx))]) {
      cat(sprintf("    %s: %s\n", names(d)[i], labs[i]))
    }
    # Show last item
    if (length(hon_idx) > 3) {
      cat(sprintf("    ... %s: %s\n", names(d)[hon_idx[length(hon_idx)]], labs[hon_idx[length(hon_idx)]]))
    }
    # Value labels
    vl <- attr(d[[hon_idx[1]]], "labels")
    if (!is.null(vl)) cat(sprintf("    Scale: %s\n", paste(paste0(vl, "=", names(vl)), collapse=", ")))
  } else {
    cat("  NO 청렴도 battery\n")
  }

  # Also check for fairness battery (공정한 업무수행) — different from 청렴
  fair_idx <- grep("공정한 업무수행", labs)
  if (length(fair_idx) > 0) {
    cat(sprintf("  공정한 업무수행 (fairness): %d items\n", length(fair_idx)))
    for (i in fair_idx[1:min(2, length(fair_idx))]) {
      cat(sprintf("    %s: %s\n", names(d)[i], labs[i]))
    }
  }

  cat("\n")
}
