library(tidyverse)

# Create party crosswalk table
party_crosswalk <- tribble(
  ~country, ~code, ~wave, ~party_name, ~party_lineage, ~coalition,

  # TAIWAN - Codes are mostly stable
  # Pan-Blue
  "Taiwan", 701, "W2", "KMT", "KMT", "pan_blue",
  "Taiwan", 701, "W3", "KMT", "KMT", "pan_blue",
  "Taiwan", 701, "W4", "KMT", "KMT", "pan_blue",
  "Taiwan", 701, "W5", "Kuomintang (KMT)", "KMT", "pan_blue",
  "Taiwan", 701, "W6", "Kuomintang (KMT)", "KMT", "pan_blue",

  "Taiwan", 703, "W2", "New Party", "New Party", "pan_blue",
  "Taiwan", 703, "W3", "New Party", "New Party", "pan_blue",
  "Taiwan", 703, "W4", "New Party", "New Party", "pan_blue",
  "Taiwan", 703, "W5", "New Party", "New Party", "pan_blue",
  "Taiwan", 703, "W6", "New Party", "New Party", "pan_blue",

  "Taiwan", 704, "W2", "PFP", "People First Party", "pan_blue",
  "Taiwan", 704, "W3", "People First Party", "People First Party", "pan_blue",
  "Taiwan", 704, "W4", "People First Party", "People First Party", "pan_blue",
  "Taiwan", 704, "W5", "People First Party", "People First Party", "pan_blue",
  "Taiwan", 704, "W6", "People First Party", "People First Party", "pan_blue",

  # Pan-Green
  "Taiwan", 702, "W2", "DPP", "DPP", "pan_green",
  "Taiwan", 702, "W3", "DPP", "DPP", "pan_green",
  "Taiwan", 702, "W4", "DPP", "DPP", "pan_green",
  "Taiwan", 702, "W5", "Democratic Progressive Party (DPP)", "DPP", "pan_green",
  "Taiwan", 702, "W6", "Democratic Progressive Party (DPP)", "DPP", "pan_green",

  "Taiwan", 705, "W2", "TSU", "Taiwan Solidarity Union", "pan_green",
  "Taiwan", 705, "W3", "Taiwan Solidarity Union", "Taiwan Solidarity Union", "pan_green",
  "Taiwan", 705, "W4", "Taiwan Solidarity Union", "Taiwan Solidarity Union", "pan_green",
  "Taiwan", 705, "W5", "Taiwan Solidarity Union", "Taiwan Solidarity Union", "pan_green",
  "Taiwan", 705, "W6", "Taiwan Solidarity Union", "Taiwan Solidarity Union", "pan_green",

  # Code 706 changes meaning
  "Taiwan", 706, "W2", "Other", NA, "other",
  "Taiwan", 706, "W3", "Other", NA, "other",
  "Taiwan", 706, "W4", "Green Party", "Green Party", "pan_green",
  "Taiwan", 706, "W5", "New Power Party", "New Power Party", "pan_green",
  "Taiwan", 706, "W6", "New Power Party", "New Power Party", "pan_green",

  # Code 707 changes meaning
  "Taiwan", 707, "W4", "Civic Party", "Civic Party", "other",
  "Taiwan", 707, "W6", "Taiwan Peoples Party (TPP)", "TPP", "neutral",

  "Taiwan", 708, "W6", "Taiwan Radical Wings", "Taiwan Radical Wings", "other",
  "Taiwan", 709, "W6", "Others", NA, "other",
  "Taiwan", 799, "W5", "Others", NA, "other",

  # SOUTH KOREA - Codes change meaning significantly
  # Code 301 - changes between progressive and conservative!
  "Korea", 301, "W2", "Uri Party", "Uri/Democratic lineage", "progressive",
  "Korea", 301, "W3", "Uri Party", "Uri/Democratic lineage", "progressive",
  "Korea", 301, "W4", "Saenuri Party", "Grand National/Saenuri lineage", "conservative",
  "Korea", 301, "W5", "Democratic Party of Korea", "Uri/Democratic lineage", "progressive",
  "Korea", 301, "W6", "Democratic Party", "Uri/Democratic lineage", "progressive",

  # Code 302 - also changes!
  "Korea", 302, "W2", "Grand National Party", "Grand National/Saenuri lineage", "conservative",
  "Korea", 302, "W3", "Grand National Party", "Grand National/Saenuri lineage", "conservative",
  "Korea", 302, "W4", "New Politics Alliance for Democracy", "Uri/Democratic lineage", "progressive",
  "Korea", 302, "W5", "Liberty Korea Party", "Grand National/Saenuri lineage", "conservative",
  "Korea", 302, "W6", "People Power Party", "Grand National/Saenuri lineage", "conservative",

  # Code 303
  "Korea", 303, "W2", "Democratic Party", "Minor progressive", "progressive",
  "Korea", 303, "W3", "Democratic Party", "Minor progressive", "progressive",
  "Korea", 303, "W4", "Justice Party", "Justice Party", "progressive",
  "Korea", 303, "W5", "BAREUNMARAE Party", "Centrist split", "conservative",
  "Korea", 303, "W6", "Justice Party", "Justice Party", "progressive",

  # Code 304
  "Korea", 304, "W2", "Democratic Labor Party", "Labor/Justice lineage", "progressive",
  "Korea", 304, "W3", "Democratic Labor Party", "Labor/Justice lineage", "progressive",
  "Korea", 304, "W5", "Party for Democracy and Peace", "Minor progressive", "progressive",

  # Code 305
  "Korea", 305, "W2", "People First Party", "People First Party", "conservative",
  "Korea", 305, "W3", "People First Party", "People First Party", "conservative",
  "Korea", 305, "W5", "Justice Party", "Justice Party", "progressive",

  "Korea", 306, "W2", "Other Parties", NA, "other",
  "Korea", 306, "W3", "Other Parties", NA, "other",
  "Korea", 306, "W5", "ETC", NA, "other",

  "Korea", 307, "W3", "Liberty Forward Party", "Liberty Forward Party", "conservative",
  "Korea", 308, "W3", "Future hope solidarity", "Minor", "other",
  "Korea", 309, "W3", "Creative Korea Party", "Minor", "other",
  "Korea", 310, "W3", "New Progressive Party", "Labor/Justice lineage", "progressive",
  "Korea", 311, "W3", "Peoples Participation Party", "Minor progressive", "progressive",

  # THAILAND - Major changes due to coups/dissolutions
  # Code 801 - Democrat Party is stable
  "Thailand", 801, "W2", "Prajadhipat", "Democrat Party", "anti_thaksin",
  "Thailand", 801, "W3", "Prajadhipat", "Democrat Party", "anti_thaksin",
  "Thailand", 801, "W4", "Democrat Party", "Democrat Party", "anti_thaksin",
  "Thailand", 801, "W5", "Democrat Party", "Democrat Party", "anti_thaksin",
  "Thailand", 801, "W6", "Democrat Party", "Democrat Party", "anti_thaksin",

  # Code 802 - Pro-Thaksin lineage (conceptually stable)
  "Thailand", 802, "W2", "Thai Rak Thai", "Pro-Thaksin", "pro_thaksin",
  "Thailand", 802, "W3", "Thai Rak Thai", "Pro-Thaksin", "pro_thaksin",
  "Thailand", 802, "W4", "Pheu Thai Party", "Pro-Thaksin", "pro_thaksin",
  "Thailand", 802, "W5", "Pheu Thai Party", "Pro-Thaksin", "pro_thaksin",
  "Thailand", 802, "W6", "Pheu Thai Party", "Pro-Thaksin", "pro_thaksin",

  # Code 803 - Changes significantly
  "Thailand", 803, "W2", "Chart Thai", "Chart Thai", "other",
  "Thailand", 803, "W3", "Chart Thai", "Chart Thai", "other",
  "Thailand", 803, "W4", "Phumjai Thai Party", "Bhumjaithai", "other",
  "Thailand", 803, "W5", "Pracharat Party", "Pro-Military", "pro_military",
  "Thailand", 803, "W6", "Palang Pracharath Party", "Pro-Military", "pro_military",

  # Code 804 - Changes significantly
  "Thailand", 804, "W2", "Mahachon", "Mahachon", "other",
  "Thailand", 804, "W3", "Mahachon", "Mahachon", "other",
  "Thailand", 804, "W4", "Chart Thai Pattana", "Chart Thai Pattana", "other",
  "Thailand", 804, "W5", "Future Forward Party", "Progressive opposition", "progressive",
  "Thailand", 804, "W6", "Move Forward Party", "Progressive opposition", "progressive",

  # Code 805
  "Thailand", 805, "W2", "Other Party", NA, "other",
  "Thailand", 805, "W3", "Other Party", NA, "other",
  "Thailand", 805, "W4", "Pheu Pandin Party", "Pheu Pandin", "pro_thaksin",
  "Thailand", 805, "W5", "Bhumjaithai Party", "Bhumjaithai", "other",
  "Thailand", 805, "W6", "Chartthaipattana Party", "Chart Thai Pattana", "other",

  # Code 806
  "Thailand", 806, "W3", "Pheu Thai", "Pro-Thaksin", "pro_thaksin",
  "Thailand", 806, "W5", "Puea Pandin Party", "Pheu Pandin", "other",
  "Thailand", 806, "W6", "Thai Liberal Party", "Thai Liberal Party", "other",

  # Code 807-809 (W3 only)
  "Thailand", 807, "W3", "Bhumjai Thai", "Bhumjaithai", "other",
  "Thailand", 808, "W3", "Chart Thai Pattana", "Chart Thai Pattana", "other",
  "Thailand", 809, "W3", "Pua Paendin", "Pheu Pandin", "other",

  "Thailand", 899, "W5", "Others", NA, "other"
)

# Save crosswalk
saveRDS(party_crosswalk, "data/processed/party_id_crosswalk.rds")
write_csv(party_crosswalk, "data/processed/party_id_crosswalk.csv")

cat("Party crosswalk created with", nrow(party_crosswalk), "mappings\n")
cat("\nSummary by country and wave:\n")
party_crosswalk %>%
  count(country, wave) %>%
  pivot_wider(names_from = wave, values_from = n) %>%
  print()

cat("\nCoalition assignments:\n")
party_crosswalk %>%
  filter(!is.na(coalition)) %>%
  count(country, coalition) %>%
  print(n = 20)
