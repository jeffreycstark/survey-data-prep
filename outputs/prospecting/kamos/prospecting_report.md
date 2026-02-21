# Slope Prospector: Summary Report
Date: 2026-02-21
Input: outputs/prospecting/kamos/kamos_means.csv

## Coverage
- Countries: 1
- Variables: 29
- Waves: 2

## Findings — Individual Variables
- Outlier slopes (|z| > 2.0): 0
- Structural breaks (p < .05): 0
- Opposite-direction variable pairs: 199

## Top Outliers (by |z-score|)
- None found

## Top Divergent Pairs (variable level)
- Korea_KAMOS: econ_equality (-0.333) vs econ_family (+0.333)
- Korea_KAMOS: econ_equality (-0.333) vs econ_national (+0.333)
- Korea_KAMOS: econ_equality (-0.333) vs employment (+0.333)
- Korea_KAMOS: econ_equality (-0.333) vs marital_status (+0.333)
- Korea_KAMOS: econ_equality (-0.333) vs national_pride (+0.333)
- Korea_KAMOS: econ_equality (-0.333) vs pol_satisfaction (+0.333)
- Korea_KAMOS: econ_equality (-0.333) vs region (+0.333)
- Korea_KAMOS: econ_equality (-0.333) vs social_mobility (+0.333)
- Korea_KAMOS: econ_equality (-0.333) vs social_mobility_next_gen (+0.333)
- Korea_KAMOS: econ_family (+0.333) vs education (-0.333)

## Findings — Concept Groups
- Groups defined: 9
- Group × country pairs assessed: 9
- Divergent groups (mixed direction): 2
- Cross-group divergences flagged: 24
- Cross-group, opposite direction: 17

## Top Divergent Concept Groups
- Korea_KAMOS | national_identity: mean slope = 0.000, rising=[national_pride], falling=[subjective_class]
- Korea_KAMOS | political_attitudes: mean slope = -0.111, rising=[pol_satisfaction], falling=[ideology; pol_system_pref]

## Top Cross-Group Divergences (opposite direction)
- Korea_KAMOS: [economic_equality_conflict] FALLING (-0.333) vs [economic_present] RISING (0.333) | Δ=0.667
- Korea_KAMOS: [economic_equality_conflict] FALLING (-0.333) vs [social_mobility] RISING (0.333) | Δ=0.667
- Korea_KAMOS: [economic_present] RISING (0.333) vs [institutional_trust_civil_society] FALLING (-0.333) | Δ=0.667
- Korea_KAMOS: [economic_present] RISING (0.333) vs [institutional_trust_executive] FALLING (-0.333) | Δ=0.667
- Korea_KAMOS: [economic_present] RISING (0.333) vs [institutional_trust_legislative] FALLING (-0.333) | Δ=0.667
- Korea_KAMOS: [economic_present] RISING (0.333) vs [social_trust] FALLING (-0.333) | Δ=0.667
- Korea_KAMOS: [institutional_trust_civil_society] FALLING (-0.333) vs [social_mobility] RISING (0.333) | Δ=0.667
- Korea_KAMOS: [institutional_trust_executive] FALLING (-0.333) vs [social_mobility] RISING (0.333) | Δ=0.667
- Korea_KAMOS: [institutional_trust_legislative] FALLING (-0.333) vs [social_mobility] RISING (0.333) | Δ=0.667
- Korea_KAMOS: [social_mobility] RISING (0.333) vs [social_trust] FALLING (-0.333) | Δ=0.667

## Files
- outputs/prospecting/kamos/outlier_slopes.csv
- outputs/prospecting/kamos/structural_breaks.csv
- outputs/prospecting/kamos/divergent_pairs.csv
- outputs/prospecting/kamos/acceleration.csv
- outputs/prospecting/kamos/slope_groups.csv
- outputs/prospecting/kamos/slope_divergence.csv
- outputs/prospecting/kamos/heatmap_slopes.png

## REMINDER
These are PUZZLES, not findings. Each outlier or divergent group needs:
1. A check of the political timeline — is there a real-world explanation?
2. A check of survey methodology — did sampling/questions change?
3. A theoretical framework — why would this pattern exist?
Only then does it become a paper.
