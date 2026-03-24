library(haven)

files <- list.files("data/kipa/raw", pattern="[.]sav$", full.names=TRUE, ignore.case=TRUE)
files <- sort(files)

for (f in files) {
  year <- regmatches(basename(f), regexpr("[0-9]{4}", basename(f)))
  d <- read_sav(f)
  labs <- sapply(d, function(x) attr(x, "label"))

  cat(sprintf("=== %s (%d x %d) ===\n", year, nrow(d), ncol(d)))

  # Find institutional trust battery
  trust_idx <- grep("기관별 신뢰 정도|기관별 신뢰도|기관.*신뢰", labs)
  if (length(trust_idx) > 0) {
    # Show first and last to identify prefix and range
    cat(sprintf("  TRUST: %s ... %s (%d items)\n",
                names(d)[trust_idx[1]], names(d)[trust_idx[length(trust_idx)]],
                length(trust_idx)))
    # Show first 3 labels
    for (i in trust_idx[1:min(3, length(trust_idx))]) {
      cat(sprintf("    %-10s: %s\n", names(d)[i], labs[i]))
    }
    # Show value labels of first trust var
    val_labs <- attr(d[[trust_idx[1]]], "labels")
    if (!is.null(val_labs)) {
      cat(sprintf("    Scale: %s\n", paste(paste0(val_labs, "=", names(val_labs)), collapse=", ")))
    }
  } else {
    # Broader search
    cat("  NO standard trust battery found. Searching broadly...\n")
    broad_idx <- grep("신뢰|trust", labs, ignore.case=TRUE)
    for (i in broad_idx[1:min(8, length(broad_idx))]) {
      cat(sprintf("    %-10s: %s\n", names(d)[i], labs[i]))
    }
  }

  # Find bonus variables
  for (pat in c("일반적.*신뢰|사람.*신뢰", "민주주의.*만족", "이념", "정치.*만족")) {
    idx <- grep(pat, labs)
    if (length(idx) > 0) {
      cat(sprintf("  %-10s: %s\n", names(d)[idx[1]], labs[idx[1]]))
    }
  }

  # Demographics
  demo_pats <- c("성별"="sex", "연령"="age", "학력|교육"="edu", "지역"="region")
  for (pat in names(demo_pats)) {
    idx <- grep(pat, labs)
    if (length(idx) > 0) {
      cat(sprintf("  DEMO %-6s: %s (%s)\n", demo_pats[pat], names(d)[idx[1]], labs[idx[1]]))
    }
  }

  cat("\n")
}
