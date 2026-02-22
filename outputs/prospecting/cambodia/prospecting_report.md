# Slope Prospector v2: Summary Report
Date: 2026-02-22
Input: outputs/prospecting/cambodia/cambodia_means.csv
Normalization: minmax

## Coverage
- Countries: 1
- Variables: 264
- Waves: 4

## Findings — Individual Variables
- Outlier slopes (|z| > 2.0): 0
- Of which non-linear trajectory: 0
- Structural breaks (p < .05): 0
- Opposite-direction variable pairs: 4128
- Variables with non-linear trajectory (all): 13

## Top Outliers (by |z-score|)
- None found

## Findings — Concept Groups
- Groups defined: 19
- Group × country pairs assessed: 19
- Divergent groups (mixed direction): 14
- Cross-group divergences flagged: 70
- Cross-group, opposite direction: 35

## Top Divergent Concept Groups
- Cambodia | political_action_voting: mean slope=-0.005 coherence=0.50 rising=[voted_last_election; voting_frequency] falling=[attended_campaign_rally; persuaded_others_vote]
- Cambodia | political_efficacy: mean slope=-0.001 coherence=0.50 rising=[efficacy_no_influence; efficacy_politics_complicated] falling=[democracy_efficacy; efficacy_ability_participate]
- Cambodia | rule_of_law: mean slope=-0.041 coherence=0.60 rising=[rich_poor_treated_equally] falling=[gov_basic_necessities; gov_ethnic_equality; gov_free_to_organize]
- Cambodia | economic_present: mean slope=0.030 coherence=0.50 rising=[hh_income_sat; subjective_social_status] falling=[econ_family_now; econ_national_now]
- Cambodia | institutional_trust_intermediary: mean slope=-0.073 coherence=0.57 rising=[trust_courts; trust_newspapers] falling=[trust_election_commission; trust_ngos; trust_parliament; trust_television]
- Cambodia | social_trust: mean slope=-0.047 coherence=0.67 rising=[trust_govt_do_right; trust_relatives] falling=[trust_acquaintances; trust_generalized_binary; trust_generalized_ordinal; trust_neighbors]
- Cambodia | economic_outlook: mean slope=0.108 coherence=0.50 rising=[econ_family_outlook] falling=[]
- Cambodia | democracy_assessment_empirical: mean slope=-0.125 coherence=0.75 rising=[democracy_satisfaction] falling=[dem_country_future; dem_country_present_govt; dem_extent_current]
- Cambodia | authoritarian_support: mean slope=0.200 coherence=0.75 rising=[expert_rule; single_party_rule; strongman_rule] falling=[]
- Cambodia | institutional_trust_executive: mean slope=0.036 coherence=0.50 rising=[trust_local_government; trust_police] falling=[trust_civil_service]

## Top Cross-Group Divergences (opposite direction)
- Cambodia: [authoritarian_support] RISING (0.200) vs [regime_comparative] FALLING (-0.315) | Δ=0.515
- Cambodia: [authoritarian_support] RISING (0.200) vs [media_and_information] FALLING (-0.281) | Δ=0.481
- Cambodia: [economic_outlook] RISING (0.108) vs [regime_comparative] FALLING (-0.315) | Δ=0.422
- Cambodia: [economic_outlook] RISING (0.108) vs [media_and_information] FALLING (-0.281) | Δ=0.389
- Cambodia: [authoritarian_support] RISING (0.200) vs [corruption] FALLING (-0.167) | Δ=0.367
- Cambodia: [authoritarian_support] RISING (0.200) vs [democracy_support_normative] FALLING (-0.152) | Δ=0.352
- Cambodia: [institutional_trust_executive] RISING (0.036) vs [regime_comparative] FALLING (-0.315) | Δ=0.350
- Cambodia: [economic_present] RISING (0.030) vs [regime_comparative] FALLING (-0.315) | Δ=0.345
- Cambodia: [authoritarian_support] RISING (0.200) vs [democracy_assessment_empirical] FALLING (-0.125) | Δ=0.325
- Cambodia: [institutional_trust_executive] RISING (0.036) vs [media_and_information] FALLING (-0.281) | Δ=0.317

## Narrative Patterns Detected
- **Cambodia** → Demobilization Sequence: Contacting/protest collapsing while authoritarian support rises
- **Cambodia** → Hollow Citizenship: Voting stable/rising while contacting and protest fall sharply

## Country Clusters
- Clustering not run or insufficient countries

## Files
- outputs/prospecting/cambodia/outlier_slopes.csv        (slopes + CIs + nonlinear flag)
- outputs/prospecting/cambodia/structural_breaks.csv
- outputs/prospecting/cambodia/divergent_pairs.csv
- outputs/prospecting/cambodia/acceleration.csv
- outputs/prospecting/cambodia/slope_groups.csv          (+ coherence_score column)
- outputs/prospecting/cambodia/slope_divergence.csv
- outputs/prospecting/cambodia/country_clusters.csv
- outputs/prospecting/cambodia/narrative_patterns.csv
- outputs/prospecting/cambodia/heatmap_slopes.png
- outputs/prospecting/cambodia/cluster_dendrogram.png
- outputs/prospecting/cambodia/dashboard_*.png           (one per country)

## REMINDER
These are PUZZLES, not findings. Each outlier or divergent group needs:
1. A check of the political timeline — is there a real-world explanation?
2. A check of survey methodology — did sampling or questions change?
3. A theoretical framework — why would this pattern exist?
Only then does it become a paper.
