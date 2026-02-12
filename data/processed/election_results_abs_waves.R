# Election Results for ABS Waves (W2-W6)
# Data collected from IFES Election Guide, Wikipedia, and other sources
# Purpose: Match election results to ABS survey respondents for winner/loser coding
#
# Sources:
# - IFES Election Guide (electionguide.org)
# - Wikipedia election articles
# - Taiwan Today, Focus Taiwan
# - World Elections blog

library(tidyverse)

# =============================================================================
# THAILAND ELECTIONS
# =============================================================================

thailand_2007 <- tribble(
  ~country, ~election_date, ~election_year, ~abs_wave, ~party_name, ~party_name_thai, ~votes, ~vote_pct, ~seats, ~ruling_coalition,
  "Thailand", "2007-12-23", 2007, "W3", "People's Power Party", "พรรคพลังประชาชน", NA, NA, 233, TRUE,
  "Thailand", "2007-12-23", 2007, "W3", "Democrat Party", "พรรคประชาธิปัตย์", NA, NA, 164, FALSE,
  "Thailand", "2007-12-23", 2007, "W3", "Thai Nation Party", "พรรคชาติไทย", NA, NA, 34, TRUE,
  "Thailand", "2007-12-23", 2007, "W3", "For the Motherland Party", "พรรคเพื่อแผ่นดิน", NA, NA, 24, TRUE,
  "Thailand", "2007-12-23", 2007, "W3", "Neutral Democratic Party", "พรรคมัชฌิมาธิปไตย", NA, NA, 11, TRUE,
  "Thailand", "2007-12-23", 2007, "W3", "Thai United National Development Party", "พรรครวมใจไทยชาติพัฒนา", NA, NA, 9, TRUE,
  "Thailand", "2007-12-23", 2007, "W3", "Royalist People's Party", "พรรคประชาราช", NA, NA, 5, FALSE
)

thailand_2011 <- tribble(
  ~country, ~election_date, ~election_year, ~abs_wave, ~party_name, ~party_name_thai, ~votes, ~vote_pct, ~seats, ~ruling_coalition,
  "Thailand", "2011-07-03", 2011, "W4", "Pheu Thai Party", "พรรคเพื่อไทย", 15744190, 45.2, 265, TRUE,
  "Thailand", "2011-07-03", 2011, "W4", "Democrat Party", "พรรคประชาธิปัตย์", 11433501, 33.0, 159, FALSE,
  "Thailand", "2011-07-03", 2011, "W4", "Bhumjaithai Party", "พรรคภูมิใจไทย", 1281652, 3.8, 34, TRUE,
  "Thailand", "2011-07-03", 2011, "W4", "Chartthaipattana Party", "พรรคชาติไทยพัฒนา", 906656, 2.6, 19, TRUE,
  "Thailand", "2011-07-03", 2011, "W4", "Palang Chon Party", "พรรคพลังชล", NA, NA, 7, TRUE,
  "Thailand", "2011-07-03", 2011, "W4", "Chart Pattana Puea Pandin", "พรรคชาติพัฒนาเพื่อแผ่นดิน", NA, NA, 7, TRUE,
  "Thailand", "2011-07-03", 2011, "W4", "Love Thailand Party", "พรรครักประเทศไทย", NA, 2.8, 4, FALSE,
  "Thailand", "2011-07-03", 2011, "W4", "Matubhum Party", "พรรคมาตุภูมิ", NA, NA, 2, FALSE,
  "Thailand", "2011-07-03", 2011, "W4", "New Democrat Party", NA, NA, NA, 1, FALSE,
  "Thailand", "2011-07-03", 2011, "W4", "Mahachon Party", NA, NA, NA, 1, FALSE
)

thailand_2019 <- tribble(
  ~country, ~election_date, ~election_year, ~abs_wave, ~party_name, ~party_name_thai, ~votes, ~vote_pct, ~seats, ~ruling_coalition,
  "Thailand", "2019-03-24", 2019, "W6", "Palang Pracharath Party", "พรรคพลังประชารัฐ", 8433137, 23.7, 116, TRUE,
  "Thailand", "2019-03-24", 2019, "W6", "Pheu Thai Party", "พรรคเพื่อไทย", 7920630, 22.3, 136, FALSE,
  "Thailand", "2019-03-24", 2019, "W6", "Future Forward Party", "พรรคอนาคตใหม่", 6265950, 17.6, 81, FALSE,
  "Thailand", "2019-03-24", 2019, "W6", "Democrat Party", "พรรคประชาธิปัตย์", 3947726, 11.1, 52, TRUE,
  "Thailand", "2019-03-24", 2019, "W6", "Bhumjaithai Party", "พรรคภูมิใจไทย", 3732883, 10.5, 51, TRUE,
  "Thailand", "2019-03-24", 2019, "W6", "Thai Liberal Party", "พรรคเสรีรวมไทย", 826530, 2.3, 10, FALSE,
  "Thailand", "2019-03-24", 2019, "W6", "Charthaipattana Party", "พรรคชาติไทยพัฒนา", 782031, 2.2, 10, TRUE,
  "Thailand", "2019-03-24", 2019, "W6", "Prachachart Party", "พรรคประชาชาติ", 485436, 1.4, 7, FALSE,
  "Thailand", "2019-03-24", 2019, "W6", "New Economics Party", "พรรคเศรษฐกิจใหม่", 485664, 1.4, 6, FALSE,
  "Thailand", "2019-03-24", 2019, "W6", "Puea Chat Party", "พรรคเพื่อชาติ", 419393, 1.2, 5, FALSE,
  "Thailand", "2019-03-24", 2019, "W6", "Chart Pattana Party", "พรรคชาติพัฒนา", 252044, 0.7, 3, TRUE
)

# =============================================================================
# SOUTH KOREA ELECTIONS
# =============================================================================

korea_2004 <- tribble(
  ~country, ~election_date, ~election_year, ~abs_wave, ~party_name, ~party_name_korean, ~votes, ~vote_pct, ~seats, ~ruling_coalition,
  "South Korea", "2004-04-15", 2004, "W2", "Uri Party", "열린우리당", 8145924, 38.27, 152, TRUE,
  "South Korea", "2004-04-15", 2004, "W2", "Grand National Party", "한나라당", 7613660, 35.77, 121, FALSE,
  "South Korea", "2004-04-15", 2004, "W2", "Democratic Labor Party", "민주노동당", 2773769, 13.03, 10, FALSE,
  "South Korea", "2004-04-15", 2004, "W2", "Millennium Democratic Party", "새천년민주당", 1510178, 7.09, 9, FALSE,
  "South Korea", "2004-04-15", 2004, "W2", "United Liberal Democrats", "자유민주연합", 600462, 2.82, 4, FALSE,
  "South Korea", "2004-04-15", 2004, "W2", "Others/Independents", NA, 642091, 3.02, 3, FALSE
)

korea_2008 <- tribble(
  ~country, ~election_date, ~election_year, ~abs_wave, ~party_name, ~party_name_korean, ~votes, ~vote_pct, ~seats, ~ruling_coalition,
  "South Korea", "2008-04-09", 2008, "W3", "Grand National Party", "한나라당", 6421654, 37.37, 153, TRUE,
  "South Korea", "2008-04-09", 2008, "W3", "United Democratic Party", "통합민주당", 4313111, 25.10, 81, FALSE,
  "South Korea", "2008-04-09", 2008, "W3", "Park's Party (Pro-Park)", "친박연대", 2258726, 13.14, 14, TRUE,
  "South Korea", "2008-04-09", 2008, "W3", "Liberty Forward Party", "자유선진당", 1173452, 6.83, 18, FALSE,
  "South Korea", "2008-04-09", 2008, "W3", "Democratic Labor Party", "민주노동당", 973394, 5.66, 5, FALSE,
  "South Korea", "2008-04-09", 2008, "W3", "Renewal of Korea Party", "창조한국당", 651980, 3.79, 3, FALSE,
  "South Korea", "2008-04-09", 2008, "W3", "Independents", NA, 1391392, 8.10, 25, FALSE
)

korea_2012 <- tribble(
  ~country, ~election_date, ~election_year, ~abs_wave, ~party_name, ~party_name_korean, ~votes, ~vote_pct, ~seats, ~ruling_coalition,
  "South Korea", "2012-04-11", 2012, "W4", "Saenuri Party (New Frontier)", "새누리당", 9129226, 42.80, 152, TRUE,
  "South Korea", "2012-04-11", 2012, "W4", "Democratic United Party", "민주통합당", 7775737, 36.46, 127, FALSE,
  "South Korea", "2012-04-11", 2012, "W4", "Unified Progressive Party", "통합진보당", 2441077, 11.45, 13, FALSE,
  "South Korea", "2012-04-11", 2012, "W4", "Liberty Forward Party", "자유선진당", 689843, 3.23, 10, FALSE
)

korea_2020 <- tribble(
  ~country, ~election_date, ~election_year, ~abs_wave, ~party_name, ~party_name_korean, ~votes, ~vote_pct, ~seats, ~ruling_coalition,
  "South Korea", "2020-04-15", 2020, "W6", "Democratic Party of Korea", "더불어민주당", 14345425, 49.91, 180, TRUE,
  "South Korea", "2020-04-15", 2020, "W6", "United Future Party", "미래통합당", 11915277, 41.45, 103, FALSE,
  "South Korea", "2020-04-15", 2020, "W6", "Justice Party", "정의당", 487519, 1.69, 6, FALSE,
  "South Korea", "2020-04-15", 2020, "W6", "People's Party", "국민의당", 377861, 1.31, 3, FALSE,
  "South Korea", "2020-04-15", 2020, "W6", "Open Democratic Party", "열린민주당", 490289, 1.70, 3, TRUE
)

# =============================================================================
# TAIWAN ELECTIONS
# =============================================================================

taiwan_2004 <- tribble(
  ~country, ~election_date, ~election_year, ~abs_wave, ~party_name, ~party_name_chinese, ~votes, ~vote_pct, ~seats, ~ruling_coalition,
  "Taiwan", "2004-12-11", 2004, "W2", "Democratic Progressive Party", "民主進步黨", 3471429, 35.72, 89, TRUE,
  "Taiwan", "2004-12-11", 2004, "W2", "Kuomintang", "中國國民黨", 3190081, 32.83, 79, FALSE,
  "Taiwan", "2004-12-11", 2004, "W2", "People First Party", "親民黨", 1350613, 13.90, 34, FALSE,
  "Taiwan", "2004-12-11", 2004, "W2", "Taiwan Solidarity Union", "台灣團結聯盟", 756712, 7.79, 12, TRUE,
  "Taiwan", "2004-12-11", 2004, "W2", "New Party", "新黨", NA, NA, 1, FALSE,
  "Taiwan", "2004-12-11", 2004, "W2", "Non-Partisan Solidarity Union", "無黨團結聯盟", NA, NA, 6, FALSE,
  "Taiwan", "2004-12-11", 2004, "W2", "Independents", NA, NA, NA, 4, FALSE
)

taiwan_2008 <- tribble(
  ~country, ~election_date, ~election_year, ~abs_wave, ~party_name, ~party_name_chinese, ~votes, ~vote_pct, ~seats, ~ruling_coalition,
  "Taiwan", "2008-01-12", 2008, "W3", "Kuomintang", "中國國民黨", 5291512, 53.50, 81, TRUE,
  "Taiwan", "2008-01-12", 2008, "W3", "Democratic Progressive Party", "民主進步黨", 3775352, 38.17, 27, FALSE,
  "Taiwan", "2008-01-12", 2008, "W3", "Non-Partisan Solidarity Union", "無黨團結聯盟", 239317, 2.42, 3, FALSE,
  "Taiwan", "2008-01-12", 2008, "W3", "People First Party", "親民黨", 28254, 0.29, 1, TRUE,
  "Taiwan", "2008-01-12", 2008, "W3", "Taiwan Solidarity Union", "台灣團結聯盟", 93840, 0.95, 0, FALSE,
  "Taiwan", "2008-01-12", 2008, "W3", "Independents", NA, NA, NA, 1, FALSE
)

taiwan_2016 <- tribble(
  ~country, ~election_date, ~election_year, ~abs_wave, ~party_name, ~party_name_chinese, ~votes, ~vote_pct, ~seats, ~ruling_coalition,
  "Taiwan", "2016-01-16", 2016, "W4", "Democratic Progressive Party", "民主進步黨", 6370953, 44.06, 68, TRUE,
  "Taiwan", "2016-01-16", 2016, "W4", "Kuomintang", "中國國民黨", 3280949, 26.91, 35, FALSE,
  "Taiwan", "2016-01-16", 2016, "W4", "New Power Party", "時代力量", 744315, 6.11, 5, FALSE,
  "Taiwan", "2016-01-16", 2016, "W4", "People First Party", "親民黨", 794838, 6.52, 3, FALSE,
  "Taiwan", "2016-01-16", 2016, "W4", "Non-Partisan Solidarity Union", "無黨團結聯盟", 77672, 0.64, 1, FALSE,
  "Taiwan", "2016-01-16", 2016, "W4", "New Party", "新黨", 510074, 4.18, 0, FALSE,
  "Taiwan", "2016-01-16", 2016, "W4", "Taiwan Solidarity Union", "台灣團結聯盟", 305675, 2.51, 0, FALSE,
  "Taiwan", "2016-01-16", 2016, "W4", "Green-Social Democratic Alliance", "綠黨社會民主黨聯盟", 308106, 2.53, 0, FALSE,
  "Taiwan", "2016-01-16", 2016, "W4", "Independents", NA, NA, NA, 1, FALSE
)

# =============================================================================
# COMBINE ALL ELECTIONS
# =============================================================================

# Standardize column names
thailand_elections <- bind_rows(thailand_2007, thailand_2011, thailand_2019) %>%
  rename(party_name_local = party_name_thai)

korea_elections <- bind_rows(korea_2004, korea_2008, korea_2012, korea_2020) %>%
  rename(party_name_local = party_name_korean)

taiwan_elections <- bind_rows(taiwan_2004, taiwan_2008, taiwan_2016) %>%
  rename(party_name_local = party_name_chinese)

# Combine all
all_elections <- bind_rows(
  thailand_elections,
  korea_elections,
  taiwan_elections
) %>%
  mutate(
    election_date = as.Date(election_date),
    # Add coalition labels
    coalition = case_when(
      country == "Thailand" & ruling_coalition ~ "Government",
      country == "Thailand" & !ruling_coalition ~ "Opposition",
      country == "South Korea" & ruling_coalition ~ "Government",
      country == "South Korea" & !ruling_coalition ~ "Opposition",
      country == "Taiwan" & ruling_coalition ~ "Pan-Green",
      country == "Taiwan" & !ruling_coalition ~ "Pan-Blue",
      TRUE ~ "Other"
    )
  ) %>%
  arrange(country, election_date, desc(seats))

# =============================================================================
# SUMMARY BY WAVE
# =============================================================================

wave_summary <- all_elections %>%
  group_by(country, abs_wave, election_year) %>%
  summarise(
    election_date = first(election_date),
    total_seats = sum(seats, na.rm = TRUE),
    ruling_seats = sum(seats[ruling_coalition], na.rm = TRUE),
    opposition_seats = sum(seats[!ruling_coalition], na.rm = TRUE),
    ruling_parties = paste(party_name[ruling_coalition], collapse = "; "),
    largest_ruling = party_name[ruling_coalition][which.max(seats[ruling_coalition])],
    largest_opposition = party_name[!ruling_coalition][which.max(seats[!ruling_coalition])],
    .groups = "drop"
  )

cat("\n========================================\n")
cat("Election Summary by ABS Wave\n")
cat("========================================\n\n")
print(wave_summary, n = 20)

# =============================================================================
# SAVE OUTPUTS
# =============================================================================

# Create output directory if needed
output_dir <- here::here("data", "processed")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Save detailed election data
saveRDS(all_elections, file.path(output_dir, "election_results_abs_waves.rds"))
write_csv(all_elections, file.path(output_dir, "election_results_abs_waves.csv"))

# Save wave summary
saveRDS(wave_summary, file.path(output_dir, "election_wave_summary.rds"))
write_csv(wave_summary, file.path(output_dir, "election_wave_summary.csv"))

cat("\n========================================\n")
cat("Files saved:\n")
cat("- election_results_abs_waves.rds\n")
cat("- election_results_abs_waves.csv\n")
cat("- election_wave_summary.rds\n")
cat("- election_wave_summary.csv\n")
cat("========================================\n")

# =============================================================================
# NOTES ON PARTY ALLIANCES AND WINNER/LOSER CODING
# =============================================================================

cat("\n========================================\n")
cat("NOTES ON PARTY ALLIANCES\n")
cat("========================================\n\n")

cat("THAILAND:\n")
cat("- 2007: PPP-led coalition (pro-Thaksin) vs Democrat-led opposition\n")
cat("- 2011: Pheu Thai (pro-Thaksin) majority government\n")
cat("- 2019: PPRP-led coalition (pro-military) vs Pheu Thai + Future Forward opposition\n")
cat("  NOTE: Future Forward dissolved in Feb 2020\n\n")

cat("SOUTH KOREA:\n")
cat("- 2004: Uri Party (progressive, pro-Roh) vs GNP (conservative)\n")
cat("- 2008: GNP (conservative, Lee MB) vs UDP (progressive opposition)\n")
cat("- 2012: Saenuri (conservative, Park GH) vs DUP (progressive opposition)\n")
cat("- 2020: Democratic Party (progressive, Moon JI) vs UFP (conservative opposition)\n\n")

cat("TAIWAN:\n")
cat("- Pan-Green coalition: DPP + TSU (independence-leaning)\
")
cat("- Pan-Blue coalition: KMT + PFP + NP (unification-leaning)\n")
cat("- 2004: DPP government (Chen Shui-bian), Pan-Blue opposition majority in LY\n")
cat("- 2008: KMT landslide (Ma Ying-jeou elected president same year)\n")
cat("- 2016: DPP landslide (Tsai Ing-wen elected president same day)\n")
