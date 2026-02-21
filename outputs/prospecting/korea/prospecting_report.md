# Slope Prospector: Summary Report
Date: 2026-02-21
Input: outputs/prospecting/korea/korea_means.csv

## Coverage
- Countries: 1
- Variables: 284
- Waves: 6

## Findings — Individual Variables
- Outlier slopes (|z| > 2.0): 0
- Structural breaks (p < .05): 3
- Opposite-direction variable pairs: 6175

## Top Outliers (by |z-score|)
- None found

## Top Divergent Pairs (variable level)
- Korea: action_resolve_local (-0.478) vs employed (+0.500)
- Korea: action_resolve_local (-0.478) vs parents_staircase (+0.500)
- Korea: action_resolve_local (-0.478) vs dem_equal_media_access (+0.500)
- Korea: action_resolve_local (-0.478) vs econ_generation_opportunity (+0.500)
- Korea: employed (+0.500) vs trad_motherinlaw_obey (-0.367)
- Korea: parents_staircase (+0.500) vs trad_motherinlaw_obey (-0.367)
- Korea: dem_equal_media_access (+0.500) vs trad_motherinlaw_obey (-0.367)
- Korea: econ_generation_opportunity (+0.500) vs trad_motherinlaw_obey (-0.367)
- Korea: action_contact_media (-0.358) vs employed (+0.500)
- Korea: action_contact_media (-0.358) vs parents_staircase (+0.500)

## Findings — Concept Groups
- Groups defined: 19
- Group × country pairs assessed: 19
- Divergent groups (mixed direction): 10
- Cross-group divergences flagged: 71
- Cross-group, opposite direction: 55

## Top Divergent Concept Groups
- Korea | government_responsiveness: mean slope = 0.035, rising=[govt_withholds_info], falling=[govt_responds_people]
- Korea | accountability_perceptions: mean slope = 0.074, rising=[gov_courts_powerless; gov_elections_real_choice; gov_no_accountability_between_elections], falling=[gov_leaders_abuse_power; gov_legislature_oversight]
- Korea | rule_of_law: mean slope = 0.017, rising=[gov_basic_necessities; rich_poor_treated_equally], falling=[gov_economic_equality; gov_ethnic_equality; gov_free_to_organize]
- Korea | political_action_voting: mean slope = -0.144, rising=[voted_last_election], falling=[attended_campaign_rally; persuaded_others_vote; voting_frequency]
- Korea | social_trust: mean slope = -0.080, rising=[trust_govt_do_right; trust_neighbors; trust_relatives], falling=[trust_acquaintances; trust_generalized_binary; trust_generalized_ordinal]
- Korea | political_efficacy: mean slope = 0.038, rising=[democracy_efficacy; efficacy_no_influence], falling=[efficacy_ability_participate; efficacy_politics_complicated]
- Korea | corruption: mean slope = -0.071, rising=[govt_anticorrupt_effort], falling=[corrupt_local_govt; corrupt_national_govt; corrupt_witnessed]
- Korea | democracy_assessment_empirical: mean slope = -0.006, rising=[dem_country_present_govt; democracy_satisfaction], falling=[dem_country_future; dem_extent_current]
- Korea | institutional_trust_intermediary: mean slope = -0.042, rising=[trust_courts; trust_political_parties; trust_television], falling=[trust_election_commission; trust_newspapers; trust_ngos; trust_parliament]
- Korea | institutional_trust_executive: mean slope = 0.078, rising=[trust_civil_service; trust_local_government; trust_national_government; trust_police; trust_president], falling=[trust_military]

## Top Cross-Group Divergences (opposite direction)
- Korea: [economic_present] RISING (0.145) vs [regime_comparative] FALLING (-0.268) | Δ=0.413
- Korea: [democratic_satisfaction] RISING (0.125) vs [regime_comparative] FALLING (-0.268) | Δ=0.393
- Korea: [institutional_trust_executive] RISING (0.078) vs [regime_comparative] FALLING (-0.268) | Δ=0.346
- Korea: [accountability_perceptions] RISING (0.074) vs [regime_comparative] FALLING (-0.268) | Δ=0.342
- Korea: [economic_outlook] FALLING (-0.172) vs [economic_present] RISING (0.145) | Δ=0.317
- Korea: [political_efficacy] RISING (0.038) vs [regime_comparative] FALLING (-0.268) | Δ=0.307
- Korea: [government_responsiveness] RISING (0.035) vs [regime_comparative] FALLING (-0.268) | Δ=0.303
- Korea: [democratic_satisfaction] RISING (0.125) vs [economic_outlook] FALLING (-0.172) | Δ=0.297
- Korea: [regime_comparative] FALLING (-0.268) vs [rule_of_law] RISING (0.017) | Δ=0.286
- Korea: [democracy_support_normative] FALLING (-0.127) vs [economic_present] RISING (0.145) | Δ=0.272

## Files
- outputs/prospecting/korea/outlier_slopes.csv
- outputs/prospecting/korea/structural_breaks.csv
- outputs/prospecting/korea/divergent_pairs.csv
- outputs/prospecting/korea/acceleration.csv
- outputs/prospecting/korea/slope_groups.csv
- outputs/prospecting/korea/slope_divergence.csv
- outputs/prospecting/korea/heatmap_slopes.png

## REMINDER
These are PUZZLES, not findings. Each outlier or divergent group needs:
1. A check of the political timeline — is there a real-world explanation?
2. A check of survey methodology — did sampling/questions change?
3. A theoretical framework — why would this pattern exist?
Only then does it become a paper.
