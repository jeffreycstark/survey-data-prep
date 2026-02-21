# Slope Prospector: Summary Report
Date: 2026-02-21
Input: outputs/prospecting/taiwan_korea/taiwan_korea_means.csv

## Coverage
- Countries: 2
- Variables: 299
- Waves: 6

## Findings — Individual Variables
- Outlier slopes (|z| > 2.0): 0
- Structural breaks (p < .05): 11
- Opposite-direction variable pairs: 12797

## Top Outliers (by |z-score|)
- None found

## Top Divergent Pairs (variable level)
- Taiwan: action_resolve_local (-0.469) vs econ_distribution_fair (+0.500)
- Taiwan: action_resolve_local (-0.469) vs main_earner (+0.500)
- Korea: action_resolve_local (-0.445) vs parents_staircase (+0.500)
- Korea: intl_china_asia_goodharm (-0.438) vs parents_staircase (+0.500)
- Korea: action_resolve_local (-0.445) vs dem_equal_media_access (+0.479)
- Korea: dem_equal_media_access (+0.479) vs intl_china_asia_goodharm (-0.438)
- Taiwan: action_contact_media (-0.345) vs econ_distribution_fair (+0.500)
- Taiwan: action_contact_media (-0.345) vs main_earner (+0.500)
- Taiwan: action_resolve_local (-0.469) vs glob_immigration_policy (+0.359)
- Korea: parents_staircase (+0.500) vs trad_longterm_relation (-0.323)

## Findings — Concept Groups
- Groups defined: 19
- Group × country pairs assessed: 38
- Divergent groups (mixed direction): 21
- Cross-group divergences flagged: 140
- Cross-group, opposite direction: 102

## Top Divergent Concept Groups
- Korea | government_responsiveness: mean slope = 0.095, rising=[govt_withholds_info], falling=[govt_responds_people]
- Korea | accountability_perceptions: mean slope = 0.071, rising=[gov_courts_powerless; gov_elections_real_choice; gov_no_accountability_between_elections], falling=[gov_leaders_abuse_power; gov_legislature_oversight]
- Taiwan | accountability_perceptions: mean slope = -0.017, rising=[gov_courts_powerless; gov_no_accountability_between_elections], falling=[gov_elections_real_choice; gov_leaders_abuse_power; gov_legislature_oversight]
- Taiwan | corruption: mean slope = -0.003, rising=[govt_anticorrupt_effort], falling=[corrupt_local_govt; corrupt_national_govt; corrupt_witnessed]
- Korea | political_action_voting: mean slope = -0.110, rising=[voted_last_election], falling=[attended_campaign_rally; persuaded_others_vote; voting_frequency]
- Taiwan | rule_of_law: mean slope = 0.047, rising=[gov_basic_necessities; gov_ethnic_equality; rich_poor_treated_equally], falling=[gov_economic_equality; gov_free_to_organize]
- Taiwan | media_and_information: mean slope = -0.058, rising=[pol_discuss; political_interest], falling=[news_internet; pol_news_follow]
- Taiwan | democracy_assessment_empirical: mean slope = -0.011, rising=[dem_country_future; democracy_satisfaction], falling=[dem_country_present_govt; dem_extent_current]
- Korea | democracy_assessment_empirical: mean slope = -0.014, rising=[dem_country_present_govt; democracy_satisfaction], falling=[dem_country_future; dem_extent_current]
- Korea | political_efficacy: mean slope = 0.001, rising=[democracy_efficacy; efficacy_no_influence], falling=[efficacy_ability_participate; efficacy_politics_complicated]

## Top Cross-Group Divergences (opposite direction)
- Taiwan: [economic_retrospective] RISING (0.115) vs [regime_comparative] FALLING (-0.170) | Δ=0.285
- Taiwan: [democratic_satisfaction] RISING (0.103) vs [regime_comparative] FALLING (-0.170) | Δ=0.273
- Korea: [democratic_satisfaction] RISING (0.100) vs [economic_outlook] FALLING (-0.159) | Δ=0.259
- Taiwan: [economic_present] RISING (0.089) vs [regime_comparative] FALLING (-0.170) | Δ=0.258
- Korea: [economic_outlook] FALLING (-0.159) vs [government_responsiveness] RISING (0.095) | Δ=0.254
- Korea: [economic_outlook] FALLING (-0.159) vs [economic_present] RISING (0.091) | Δ=0.250
- Taiwan: [authoritarian_support] FALLING (-0.126) vs [economic_retrospective] RISING (0.115) | Δ=0.242
- Taiwan: [democracy_support_normative] RISING (0.068) vs [regime_comparative] FALLING (-0.170) | Δ=0.238
- Korea: [accountability_perceptions] RISING (0.071) vs [economic_outlook] FALLING (-0.159) | Δ=0.231
- Taiwan: [authoritarian_support] FALLING (-0.126) vs [democratic_satisfaction] RISING (0.103) | Δ=0.230

## Files
- outputs/prospecting/taiwan_korea/outlier_slopes.csv
- outputs/prospecting/taiwan_korea/structural_breaks.csv
- outputs/prospecting/taiwan_korea/divergent_pairs.csv
- outputs/prospecting/taiwan_korea/acceleration.csv
- outputs/prospecting/taiwan_korea/slope_groups.csv
- outputs/prospecting/taiwan_korea/slope_divergence.csv
- outputs/prospecting/taiwan_korea/heatmap_slopes.png

## REMINDER
These are PUZZLES, not findings. Each outlier or divergent group needs:
1. A check of the political timeline — is there a real-world explanation?
2. A check of survey methodology — did sampling/questions change?
3. A theoretical framework — why would this pattern exist?
Only then does it become a paper.
