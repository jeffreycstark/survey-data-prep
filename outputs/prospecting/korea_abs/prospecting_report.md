# Slope Prospector: Summary Report
Date: 2026-02-19
Input: /Users/jeffreystark/Development/Research/survey-data-prep/data/interim/abs_means_long.csv

## Coverage
- Countries: 16
- Variables: 288
- Waves: 6

## Findings
- Outlier slopes (|z| > 2.0): 76
- Structural breaks (p < .05): 0
- Opposite-direction pairs: 67033

## Top Outliers (by |z-score|)
- Vietnam | age: slope = -0.920, z = -2.87 (FALLING)
- Thailand | dem_country_present_govt: slope = -0.751, z = -2.87 (FALLING)
- Malaysia | urban_rural: slope = 0.155, z = 2.85 (RISING)
- Hong Kong | dem_vs_econ: slope = 0.370, z = 2.84 (RISING)
- Japan | efficacy_no_influence: slope = -0.095, z = -2.76 (FALLING)
- Vietnam | military_rule: slope = 0.150, z = 2.75 (RISING)
- Cambodia | hh_generations: slope = -0.163, z = -2.64 (FALLING)
- Hong Kong | action_demonstration: slope = -1.329, z = -2.64 (FALLING)
- Cambodia | gov_basic_necessities: slope = -0.143, z = -2.64 (FALLING)
- Cambodia | people_have_necessities: slope = -0.143, z = -2.64 (FALLING)

## Top Divergent Pairs
- Hong Kong: action_contact_media (-1.472) vs age (+1.236)
- China: action_petition (-1.534) vs age (+1.142)
- China: action_contact_media (-1.531) vs age (+1.142)
- Japan: action_contact_media (-1.408) vs age (+1.189)
- Hong Kong: action_petition (-1.349) vs age (+1.236)
- Hong Kong: action_demonstration (-1.329) vs age (+1.236)
- China: age (+1.142) vs news_internet (-1.383)
- Taiwan: action_contact_media (-1.069) vs age (+1.358)
- Singapore: action_contact_media (-1.454) vs education_years (+0.849)
- Korea: action_contact_media (-0.808) vs age (+1.394)

## Files
- /Users/jeffreystark/Development/Research/survey-data-prep/outputs/prospecting/korea_abs/outlier_slopes.csv
- /Users/jeffreystark/Development/Research/survey-data-prep/outputs/prospecting/korea_abs/structural_breaks.csv
- /Users/jeffreystark/Development/Research/survey-data-prep/outputs/prospecting/korea_abs/divergent_pairs.csv
- /Users/jeffreystark/Development/Research/survey-data-prep/outputs/prospecting/korea_abs/acceleration.csv
- /Users/jeffreystark/Development/Research/survey-data-prep/outputs/prospecting/korea_abs/heatmap_slopes.png

## REMINDER
These are PUZZLES, not findings. Each outlier needs:
1. A check of the political timeline — is there a real-world explanation?
2. A check of survey methodology — did sampling/questions change?
3. A theoretical framework — why would this pattern exist?
Only then does it become a paper.
