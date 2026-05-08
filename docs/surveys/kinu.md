# KINU Unification Perception Survey (통일의식조사)

**Status**: Complete (127 vars, 13 fielding waves 2014–2023, 13,030 respondents, South Korea only).

Annual 2014–2018, **biannual 2019–2021** (a/b sub-waves Apr/Sep, Apr/Jun, Nov/Apr, Oct/Apr), back to annual 2022–2023. The biannual fielding gives finer temporal resolution than KGSS for the 2019–2021 window — useful for localizing the 2018→2021 unification-disillusionment break.

## Pipeline

```bash
Rscript src/r/data_prep_modules/kinu/0_load_waves.R
Rscript src/r/data_prep_modules/kinu/2_harmonize_all.R
Rscript src/r/data_prep_modules/kinu/99_create_final_dataset.R
```

Source: `data/kinu/raw/kinu_2014-2023_en.sav` (n=13,030, 956 cols, 13 fielding waves), single cumulative SPSS split by year-code. Cross-referenced codebook: `data/kinu/raw/kinu_2014-2024_codebook_en.xlsx`.

## Loading

```r
d <- readRDS("data/processed/kinu_harmonized.rds")
# Or: arrow::read_parquet("data/processed/kinu_harmonized.parquet")
```

Wave keys: w2014, w2015, w2016, w2017, w2018, w2019a, w2019b, w2020a, w2020b, w2021a, w2021b, w2022, w2023.

## ⚠️ Critical caveats

- **Wave column is character** (`"2014"`, `"2019a"`, `"2023"` etc.); `year` and `fieldwork_month` are integer companions.
- **No weight column.** KINU publishes weighted percentages but ships unweighted microdata. Treat as unweighted; document the limitation in any paper.
- **2024 wave** is in the codebook (column "24") but not in the `.sav` file we hold. The verbatim dictionary flags this; harmonization currently runs through 2023.

## Variable categories

| Category | Variables | Scale |
|----------|-----------|-------|
| Unification (17) | uni_necessity (1–4 identity), uni_arg_* × 9 (1–5 agreement; pro/anti unification statements), uni_benefit_nation/self/nk (1–4), uni_post_*_conflict × 4 (1–5, post-unification conflict forecasts) | varies; all identity, higher = more intensity |
| Demographics (16) | age (continuous), age_5cat (1–5), birthyear, cohort (1=war gen … 7=Z gen), sex, region (19-cat sido), urban_rural (1–3 reversed), home_region, subjective_income_5pt, subjective_class_6pt (⚠ OPPOSITE direction from KGSS subjective_class_6pt), income_manwon (continuous), education (1–8), religion, religious_attendance (1–6 reversed), marital_status, employment | varies |
| North Korea (22) | nk_interest, nk_warmth_aid/cooperate/caution/hostile (4 × 0–10), nk_trust_kju_regime, nk_dialogue_kju, nk_pursues_unification, nk_wants_communist_unif, nk_denuke_possible (1–3), nk_nuke_war_likely (0–10), nk_nukes_concern/interest/impact (3 × 1–5), nk_def_introduce/next_door/prejudice/violent_inc/too_many_demands/mutual_benefits/jobs (7 × 1–5), nk_def_contact_freq (reversed) | varies |
| NK Policy (10) | nkpol_econ_exchange/use_nk_resources/sports_culture/humanitarian_aid/geumgang_tourism/kaesong_resume/defector_support (7 × 0–10), nkpol_sanctions (0–10), nkpol_us_china_posture (1–4 categorical), nkpol_public_opinion_reflected (1–4 reversed) | varies |
| National Attitudes (25) | natid_pride_overall + 10 domain-specific pride items (all 1–4), trust_general (0–10), trust_president/administration/courts/assembly/parties/media (6 × 0–10), patriot_flag/identity (2 × 1–5), multicult_race/religion/culture (3 × 1–5), sysjust_fair_society/best_country (2 × 1–9) | varies |
| Politics (15) | rwa_mighty_leader/criticize_authorities/strongest_method/law_and_order/obedience/deviant_groups/disciplined_citizens (7 × 1–5; full Altemeyer RWA battery), eval_democracy (0–10), eval_admin/eval_admin_unif_nk/eval_econ_satisfaction (3 × 1–4), econ_personal_year_change/econ_national_year_change (2 × 1–5), ideology_lc_self (0–10, higher=conservative), party_warmth_justice (0–100 thermometer) | varies |
| Security (16) | war_possibility_5pt (1–5), nk_nukes_unstoppable (1–5), us_alliance_necessity/us_forces_needed_now/us_forces_post_unification (3 × 1–4), sk_nuke_armament_support/us_nuke_deployment_support (2 × 1–4), us_vs_china_security/us_vs_china_economy (2 × 1–5 bipolar, 1=US-leaning, 5=China-leaning), country_warmth_us/china/japan/russia (4 × −5 to +5), leader_warmth_xi/putin/kju (3 × 0–100) | varies |
| Integration (6) | conflict_overall_severity, conflict_regional, conflict_class, conflict_ideological, conflict_generational, conflict_nk_unification (all 1–4 identity, higher = more serious) | 1–4 |
| Identifiers (3) | wave (string: "2014", "2019a", etc.), year (integer), fieldwork_month (Apr/Jun/Sep/Oct/Nov as integer) | varies |
| Country (1) | country = "KOR" (all rows) | string |

## Verbatim dictionary

`data/kinu/questionnaire_text/kinu_verbatim_items.csv` — Complete (929 raw vars, 13,020 rows; codebook-driven build via `src/scripts/build_kinu_verbatim.R` + alias map `raw_to_harmonized.csv`; covers 13 fielded waves + 2024 codebook column flagged as data-pending).

## Notes & gotchas

- Missing-value conventions: 9=n/a in 1–5 / 1–4 / 1–7 scales (per-variable handling); 99=n/a in 0–10 / 1–9 scales; 999=n/a in 0–100 thermometers.
- **KINU vs KGSS for unification analysis**: KINU `uni_necessity` (higher=pro-unification) and KGSS `pol_unification` (lower=pro-unification, OPPOSITE direction; reverse one before comparing). Both peak in 2018; KINU's biannual 2019–2021 fielding localizes the post-Pyongyang-summit decline more precisely than KGSS's 2018→2021 gap.
