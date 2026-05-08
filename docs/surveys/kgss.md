# Korea General Social Survey (KGSS)

**Status**: Complete (187 vars, 17 survey years 2003–2025, 23,282 respondents, South Korea only). No 2015, 2017, 2019–2020, 2022, 2024. `pol_govt_eval` (CURGOV) dropped in 2025.

## Pipeline

```bash
Rscript src/r/data_prep_modules/kgss/0_load_waves.R
Rscript src/r/data_prep_modules/kgss/2_harmonize_all.R
Rscript src/r/data_prep_modules/kgss/99_create_final_dataset.R
```

Source file: `data/kgss/raw/kor_data_CUM0074.sav` (n=23,282, 3,491 cols, 2003–2025). The loader splits this cumulative file by year.

## Loading

```r
d <- readRDS("data/processed/kgss_harmonized.rds")
# Or: arrow::read_parquet("data/processed/kgss_harmonized.parquet")
```

Country identifier: `country` = "KOR" (all rows).
Wave column: `wave` = calendar year integer (2003, 2004, …, 2025), **not** a sequential wave index.

## ⚠️ Scale warning

`conf_*` variables are **1–3** (not 1–4 like ABS/WVS/LBS trust vars); do not compare without rescaling.

## Variable categories

| Category | Variables | Scale |
|----------|-----------|-------|
| Institutional Confidence (20) | conf_business, conf_legislature, conf_judiciary, conf_science, conf_military, conf_finance, conf_bluehouse, conf_civil_society, conf_clergy, conf_education, conf_labor, conf_press, conf_television, conf_medicine, conf_govt_national, conf_govt_local, conf_research, conf_prosecutors, conf_statistics, conf_election_commission | 1–3, higher=more confidence |
| Social Trust (3) | trust_fair (1–3), trust_generalized (1–4), trust_reliable (0–10) | varies; higher=more trust |
| Political Attitudes (9) | pol_govt_eval, pol_econ_sat (1–5 higher=worse), pol_ideology (1–5 liberal–conservative), pol_national_pride (1–4 higher=less proud), pol_econ_prospect, pol_pol_prospect (1–5 higher=worse), pol_northkorea_view, pol_nk_defectors, pol_unification | varies |
| Political Behavior / Partisanship (9) | party_id, party_pref (nominal year-specific codes — NOT comparable across waves), voted_presidential, voted_general, voted_local (1=voted, 2=did not), pol_satisfaction, econ_hh_satisfaction, econ_hh_outlook, pol_outlook (all 1–5 reversed, higher=better) | varies |
| Civic Attitudes — ISSP Citizenship (20) | cit_virtue_paytaxes, cit_virtue_obeylaws, cit_virtue_watchgov, cit_virtue_helpkr, cit_right_solok, cit_right_minorities, cit_right_polopts, cit_right_oppsegov (1–7 higher=more important), pol_efficacy_internal, pol_efficacy_external (1–5 reversed, higher=more efficacy), dem_now, dem_10yrs_past, dem_10yrs_future (0–10 higher=more democratic), action_petition, action_boycott, action_demonstration, action_rally, action_contact_gov (1–4 reversed, higher=more active), admin_service (1–4 reversed, higher=better), admin_corruption (1–5 higher=more corrupt) | varies |
| Role of Government (18) | gov_resp_jobs, gov_resp_prices, gov_resp_healthcare, gov_resp_elderly, gov_resp_industry, gov_resp_unemploy, gov_resp_incomegap, gov_resp_students, gov_resp_housing, gov_resp_environment (1–4 reversed, higher=more state role; 2006/2016 only), gov_spend_environment, gov_spend_health, gov_spend_police, gov_spend_education, gov_spend_defense, gov_spend_pension, gov_spend_unemployment, gov_spend_culture (1–5 reversed, higher=spend more; 7 waves 2006/2014/2016/2018/2021/2023/2025) | varies |
| National Identity — ISSP (32) | **General pride (5, 2003/2013/2023)**: natid_korean_over_other, natid_shame, natid_world_like_kr, natid_kr_better_than_most, natid_right_or_wrong (1–5 reversed, higher=more agreement; `natid_shame` inversely valenced). **Domain pride (10, 2003/2013/2023/2025)**: pride_democracy, pride_pol_influence, pride_economy, pride_social_security, pride_science, pride_sports, pride_arts, pride_military, pride_history, pride_fairness (1–4 reversed, higher=more proud). **"True Korean" criteria (6, 2003/2010/2013/2023)**: truekr_born_here, truekr_citizenship, truekr_ancestors, truekr_feels_kr, truekr_respects_law, truekr_confucian (1–4 reversed, higher=more important). **International relations (6, 2003/2013/2021/2023)**: intl_limit_imports, intl_world_govt_env, intl_own_way, intl_no_foreign_land, intl_kr_tv, intl_foreign_co_harmful (1–5 reversed, higher=agree). **Immigration (5, 2003/2010/2013/2023)**: imm_crime, imm_help_econ, imm_take_jobs, imm_cultural_contrib (1–5 reversed, higher=agree), imm_limit_number (1–5 identity, higher=want fewer immigrants — scale direction differs from other imm_* items) | varies |
| Corruption / Bribery / 청탁 (12) | **Govt anti-corruption performance (3)**: corr_anticorrupt_policy (2003–2010), corr_tax_fairness_policy (2003–2010), corr_election_transparency (2004/2014) — all 1–5 reversed, higher=better govt performance. **Corruption perceptions (5)**: corr_politicians (2006/2014/2016), corr_officials (2006/2014/2016), corr_officials_bribe (2006/2016) — 1–5 identity, higher=MORE corruption; corr_cant_succeed_without (2009/2014), corr_bribe_success (2009/2014/2021/2023/2025, **5 waves**) — 1–5 reversed, higher=more cynical. **청탁 / patronage (4, all 2006 only)**: corr_receive_requests, corr_have_connections (1–4 identity); corr_officials_fair (1–5 reversed, higher=more fair), corr_officials_nepotism (1–4 reversed, higher=LESS nepotism). **⚠ Directions are mixed across this module — read each variable's note** | varies |
| Social Inequality — ISSP (6) | ineq_gap_too_large (4 waves: 2003/2009/2011/2014, 1–5 reversed, higher=more agrees gap too large), ineq_success_factor (3 waves: 2003/2014/2016, 1–3 categorical; NOT ordinal), ineq_fair_continuum (2 waves: 2011/2014, 1–10 higher=more meritocratic preference), ineq_perc_income, ineq_perc_jobs, ineq_perc_law (3 waves each: 2005/2009/2014, 1–5 higher=perceives more inequality) | varies; ISSP rotation |
| Social Conflict — ISSP (4) | conflict_richpoor, conflict_workingclass_middleclass, conflict_labor_management, conflict_top_bottom (3 waves each: 2003/2009/2014; raw CON{WLTH,CLASS,UNION,SOC}; reversed) | 1–4, higher=perceives more serious conflict |
| Family / Gender Roles — ISSP (6) | gender_breadwinner_norm (4 waves: 2003/2008/2012/2018, raw HUBBYWRK + HBBYWK08 combined), gender_workmom_family_suffers (3 waves: 2003/2012/2016, FAMSUFFR), gender_both_earn / gender_woman_homemaker_pref / gender_divorce_best_solution / gender_cohab_no_marriage_ok (2 waves each: 2003/2012; raw TWOINCS, HOMEKID, DIVBEST, COHABOK). All 5pt reversed; higher=stronger agreement with stated proposition. ⚠ 7-pt SEXROLE1/2/123 deferred — no safe_reverse_7pt helper yet. | 1–5, higher=stronger agreement |
| Health (1) | srhealth (11 waves: 2006/2007/2009/2010/2011/2012/2013/2016/2018/2023/2025; combines HEALTHY + HEALR + HEALTH23 — all symmetric 5pt; 2021 HEALTH21 EXCLUDED, asymmetric scale) | 1–5, higher=better self-rated health |
| Environment — ISSP (19) | env_concern_overall (3 waves: 2010/2014/2021, 1–5 identity higher=more concerned; ⚠ note other env items run OPPOSITE direction). Willingness battery (4): env_pay_higher_prices, env_pay_higher_taxes, env_lower_living_standard, env_growth_needs_protection (3 waves each, 1–5 reversed). Personal-action battery (5, 2 waves 2010/2021): env_too_difficult, env_do_right_costly, env_other_things_more_imp, env_meaningless_alone, env_threats_exaggerated (1–5 reversed). Modern-life/progress (5, 2-3 waves): env_modern_life_harms, env_future_concern, env_progress_harms, env_growth_harms, env_science_can_solve. Pollution-threat (4, 3 waves each: 2010/2014/2021): env_threat_cars, env_threat_industry, env_threat_chemicals, env_threat_water. | varies; ISSP rotation |
| Religion beliefs — ISSP (10) | religiosity_intensity (17 waves, religious-only subset, 1–3 reversed). God beliefs (4, 2 waves 2008/2018): god_belief_certainty (1–6 identity), god_belief_history (1–4 categorical), prayer_frequency (1–11 identity), spirituality_orientation (1–4 categorical). Specific-belief battery (5, 2 waves 2008/2018, 1–4 reversed): belief_afterlife, belief_heaven, belief_hell, belief_religious_miracles, belief_ancestors_supernatural. Substantive: clear 2008→2018 secularization signal (god_belief_certainty 3.69→3.36; all 5 RELNW items decline). | varies; ISSP rotation |
| Wellbeing (3) | wb_happiness (6 waves: 2009/2010/2016/2021/2023/2025, 1–5 reversed higher=happier), wb_life_satisfaction (6 waves: 2006/2009/2016/2021/2023/2025, 1–5 reversed higher=more satisfied), wb_financial_satisfaction (14 waves: 2003-2025 with gaps at 2007/2013/2014, 1–5 reversed higher=more satisfied) | 1–5, higher=better |
| Demographics (12) | age, sex, education, marital_status, employment, income, region, urban_rural, religion, religious_attendance, subjective_class_6pt (1–6 higher=lower class), subjective_rank_10pt (1–10 higher=higher class) | varies |
| Identifiers (3) | resp_id (within-year), yr_resp_id (cross-year unique, format YYYYnnnnn), questionnaire_form (1=A, 2=B; 2016+ only) | nominal |
| Weight (1) | weight | continuous, mean=1; raw: FINALWT (range ~0.29–5.29) |

## Verbatim dictionary

`data/kgss/questionnaire_text/kgss_verbatim_items.csv` — Complete (97 vars, 1,601 rows; covers 17 years/2003–2025; includes social_conflict (4), srhealth (1), family_gender (6) added 2026-04, environment (19) + religion_beliefs (10) added 2026-05).

## Notes & gotchas

- Missing-value conventions: -8=DK, -1=IAP treated as NA; legacy 88/98/99 sentinels also treated as NA in newer specs.
- `conf_bluehouse` = confidence in the Blue House (Korea's presidential executive office).
- **No interview date variable** exists in the cumulative file; year is the only temporal identifier.
- ⚠️ **`party_id` / `party_pref` caveats**: NOMINAL raw codes that DIFFER per wave (Korean party system reshuffles regularly — Saenuri dissolved 2017, 조국혁신당 emerged 2024). Use within a single wave or construct per-wave camp mappings for longitudinal analysis.
- **Widest-coverage variables by module**: `gov_spend_*` items (7 waves: 2006/2014/2016/2018/2021/2023/2025); `pol_satisfaction`, `econ_hh_satisfaction`, `econ_hh_outlook` (10+ waves each); `wb_financial_satisfaction` (14 waves: best wellbeing time series). Social inequality items are ISSP-rotation (3–4 waves) — sparse by design.
