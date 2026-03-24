library(haven)

files <- list.files("data/kipa/raw", pattern="[.]sav$", full.names=TRUE, ignore.case=TRUE)
files <- sort(files)

for (f in files) {
  year <- regmatches(basename(f), regexpr("[0-9]{4}", basename(f)))
  d <- read_sav(f)
  labs <- sapply(d, function(x) attr(x, "label"))

  trust_idx <- grep("기관별 신뢰 정도", labs)

  cat(sprintf("=== %s (%d x %d) ===\n", year, nrow(d), ncol(d)))
  if (length(trust_idx) > 0) {
    for (i in trust_idx) {
      cat(sprintf("  %-10s: %s\n", names(d)[i], labs[i]))
    }
  } else {
    cat("  NO institutional trust vars found with standard label\n")
  }

  # Also find generalized trust, democracy satisfaction, ideology
  bonus_pats <- c("일반적으로 사람.*신뢰", "민주주의.*만족", "이념적 성향",
                   "정치 상황 만족", "정치 효능")
  for (pat in bonus_pats) {
    idx <- grep(pat, labs)
    if (length(idx) > 0) {
      cat(sprintf("  %-10s: %s\n", names(d)[idx[1]], labs[idx[1]]))
    }
  }
  cat("\n")
}
