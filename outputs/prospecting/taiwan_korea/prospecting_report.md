# Slope Prospector v2: Summary Report
Date: 2026-02-22
Input: outputs/prospecting/taiwan_korea/taiwan_korea_means.csv
Normalization: minmax

## Coverage
- Countries: 2
- Variables: 299
- Waves: 6

## Findings — Individual Variables
- Outlier slopes (|z| > 2.0): 0
- Of which non-linear trajectory: 0
- Structural breaks (p < .05): 11
- Opposite-direction variable pairs: 6582
- Variables with non-linear trajectory (all): 44

## Top Outliers (by |z-score|)
- None found

## Findings — Concept Groups
- Groups defined: 19
- Group × country pairs assessed: 38
- Divergent groups (mixed direction): 24
- Cross-group divergences flagged: 140
- Cross-group, opposite direction: 102

## Top Divergent Concept Groups
- Korea | government_responsiveness: mean slope=0.095 coherence=0.50 rising=[govt_withholds_info] falling=[govt_responds_people]
- Korea | accountability_perceptions: mean slope=0.071 coherence=0.60 rising=[gov_courts_powerless; gov_elections_real_choice; gov_no_accountability_between_elections] falling=[gov_leaders_abuse_power]
- Taiwan | accountability_perceptions: mean slope=-0.017 coherence=0.40 rising=[gov_courts_powerless; gov_no_accountability_between_elections] falling=[gov_elections_real_choice; gov_leaders_abuse_power]
- Taiwan | corruption: mean slope=-0.003 coherence=0.75 rising=[govt_anticorrupt_effort] falling=[corrupt_local_govt; corrupt_national_govt; corrupt_witnessed]
- Korea | political_action_voting: mean slope=-0.110 coherence=0.75 rising=[voted_last_election] falling=[attended_campaign_rally; persuaded_others_vote; voting_frequency]
- Taiwan | rule_of_law: mean slope=0.047 coherence=0.40 rising=[gov_ethnic_equality; rich_poor_treated_equally] falling=[gov_economic_equality; gov_free_to_organize]
- Taiwan | media_and_information: mean slope=-0.058 coherence=0.50 rising=[political_interest] falling=[news_internet]
- Taiwan | democracy_assessment_empirical: mean slope=-0.011 coherence=0.50 rising=[democracy_satisfaction] falling=[dem_country_present_govt; dem_extent_current]
- Korea | democracy_assessment_empirical: mean slope=-0.014 coherence=0.50 rising=[democracy_satisfaction] falling=[dem_country_future; dem_extent_current]
- Korea | political_efficacy: mean slope=0.001 coherence=0.50 rising=[democracy_efficacy; efficacy_no_influence] falling=[efficacy_ability_participate]

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

## Narrative Patterns Detected
- **Korea** → Economic Pessimism Decoupling: Present economic conditions stable while outlook deteriorates
- **Korea** → Output Legitimacy Signature: Economic satisfaction rising while democratic quality assessment is flat/falling
- **Taiwan** → Corruption Normalization: Witnessed corruption falls while perceived systemic corruption stays high
- **Taiwan** → Output Legitimacy Signature: Economic satisfaction rising while democratic quality assessment is flat/falling

## Country Clusters
- Clustering not run or insufficient countries

## Files
- outputs/prospecting/taiwan_korea/outlier_slopes.csv        (slopes + CIs + nonlinear flag)
- outputs/prospecting/taiwan_korea/structural_breaks.csv
- outputs/prospecting/taiwan_korea/divergent_pairs.csv
- outputs/prospecting/taiwan_korea/acceleration.csv
- outputs/prospecting/taiwan_korea/slope_groups.csv          (+ coherence_score column)
- outputs/prospecting/taiwan_korea/slope_divergence.csv
- outputs/prospecting/taiwan_korea/country_clusters.csv
- outputs/prospecting/taiwan_korea/narrative_patterns.csv
- outputs/prospecting/taiwan_korea/heatmap_slopes.png
- outputs/prospecting/taiwan_korea/cluster_dendrogram.png
- outputs/prospecting/taiwan_korea/dashboard_*.png           (one per country)

## REMINDER
These are PUZZLES, not findings. Each outlier or divergent group needs:
1. A check of the political timeline — is there a real-world explanation?
2. A check of survey methodology — did sampling or questions change?
3. A theoretical framework — why would this pattern exist?
Only then does it become a paper.
