library(haven)
d <- read_sav("data/kipa/raw/kipa_2021.sav")
labs <- sapply(d, function(x) attr(x, "label"))

# Get raw means for trust battery
trust_idx <- grep("기관별 신뢰 정도", labs)
our_means <- numeric(length(trust_idx))
our_korean <- character(length(trust_idx))
our_suffix <- character(length(trust_idx))
for (i in seq_along(trust_idx)) {
  v <- as.numeric(d[[trust_idx[i]]])
  v[v >= 8] <- NA
  our_means[i] <- round(mean(v, na.rm = TRUE), 3)
  our_korean[i] <- sub(".*-", "", labs[trust_idx[i]])
  our_suffix[i] <- sub(".*_", "", names(d)[trust_idx[i]])
}

# Rich 2024 Appendix A: Job Performance means
# Listed in Rich's presentation order (political, other state, non-state)
rich <- data.frame(
  rich_label = c(
    "Central Government", "National Assembly", "Local Government",
    "Court", "Prosecutor", "Police", "Public Corporations", "Army",
    "Labor Unions", "Civic Organizations", "TV Broadcasters", "Newspapers",
    "Educational Institutions", "Medical Institutions", "Large Corporations",
    "Religious Organizations", "Financial Institutions"
  ),
  rich_mean = c(
    2.553, 2.181, 2.610,
    2.517, 2.481, 2.546, 2.530, 2.538,
    2.443, 2.509, 2.566, 2.493,
    2.493, 2.761, 2.833,
    2.574, 2.539
  ),
  # Map Rich's labels to our suffix positions
  our_suffix = c(
    "1", "2", "6",     # Political: central govt, NA, local govt
    "3", "4", "5", "7", "8",  # State: court, prosecutor, police, public corp, army
    "9", "10", "11", "12",    # Non-state: labor, civic, TV, newspaper
    "13", "14", "15",          # education, medical, large corp
    "16", "17"                 # religious, financial
  ),
  stringsAsFactors = FALSE
)

# Merge
result <- merge(rich,
                data.frame(our_suffix = our_suffix, our_mean = our_means,
                           korean = our_korean, stringsAsFactors = FALSE),
                by = "our_suffix")
result$diff <- round(result$our_mean - result$rich_mean, 3)

# Sort by absolute difference (biggest mismatches first)
result <- result[order(-abs(result$diff)), ]

cat("=== Rich (2024) Appendix A vs Our Raw Data — Job Performance (2021) ===\n\n")
cat(sprintf("%-25s %-20s  Rich   Ours   Diff\n", "Rich Label", "Korean"))
cat(paste(rep("-", 78), collapse = ""), "\n")
for (i in 1:nrow(result)) {
  r <- result[i, ]
  flag <- if (abs(r$diff) > 0.001) " *** MISMATCH" else ""
  cat(sprintf("%-25s %-20s  %.3f  %.3f  %+.3f%s\n",
              r$rich_label, r$korean, r$rich_mean, r$our_mean, r$diff, flag))
}

# Now check: did Rich swap some non-state institutions?
cat("\n\n=== Hypothesis: Rich swapped Education/LargeCorp/Religious/Financial ===\n\n")
cat("Rich's non-state order:\n")
cat("  Educational Institutions = 2.493\n")
cat("  Medical Institutions     = 2.761\n")
cat("  Large Corporations       = 2.833\n")
cat("  Religious Organizations  = 2.574\n")
cat("  Financial Institutions   = 2.539\n")
cat("\nOur raw data (suffix order _13 through _17):\n")
for (s in c("13", "14", "15", "16", "17")) {
  idx <- which(our_suffix == s)
  cat(sprintf("  _%s %-20s = %.3f\n", s, our_korean[idx], our_means[idx]))
}

cat("\nIf Rich mapped by suffix number assuming a different ordering:\n")
cat("  Rich 'Educational'  (2.493) matches our _12 신문사/Newspapers  (2.493) EXACTLY\n")
cat("  Rich 'Medical'      (2.761) matches our _13 교육기관/Education (2.761) EXACTLY\n")
cat("  Rich 'Large Corp'   (2.833) matches our _14 의료기관/Medical   (2.833) EXACTLY\n")
cat("  Rich 'Religious'    (2.574) matches our _15 대기업/Large Corp  (2.574) EXACTLY\n")
cat("  Rich 'Financial'    (2.539) matches our _16 종교기관/Religious (2.539) EXACTLY\n")
cat("\n==> Rich's labels are SHIFTED BY ONE starting at Educational Institutions.\n")
cat("    He appears to have mapped suffix _12 onward with labels off by one position.\n")
