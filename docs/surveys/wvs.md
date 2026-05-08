# World Values Survey (WVS)

**Status**: Complete (62 vars, 7 waves, 446,767 respondents, 108 countries).

## Pipeline

```bash
Rscript src/r/data_prep_modules/wvs/2_harmonize_all.R
Rscript src/r/data_prep_modules/wvs/99_create_final_dataset.R
```

W1-W5 are SPSS `.sav`; W6-W7 are parquet.

## Loading

```r
d <- readRDS("data/processed/wvs_harmonized.rds")
# Or: arrow::read_parquet("data/processed/wvs_harmonized.parquet")
```

Country identifier: `country` (3-letter ISO alpha codes, e.g. "USA", "CHN", "DEU").

## Variable categories

| Category | Variables | Scale |
|----------|-----------|-------|
| Institutional Trust (19) | trust_churches, trust_armed_forces, trust_press, trust_television, trust_labor_unions, trust_police, trust_courts, trust_government, trust_political_parties, trust_parliament, trust_civil_service, trust_universities, trust_elections (W7), trust_major_companies, trust_banks, trust_environmental_orgs, trust_womens_orgs, trust_charitable_orgs, trust_united_nations | 1-4, higher=more trust; W1-W7 (most items) |
| Social Trust (7) | trust_generalized_binary (1-2, W1-W7), trust_family, trust_neighborhood, trust_people_personally, trust_first_time, trust_another_religion, trust_another_nationality (W5-W7) | 1-4, higher=more trust |
| Democratic Attitudes (3) | dem_importance_democracy (W5-W7), dem_how_democratic (W5-W7), dem_satisfaction_political_system (W7) | 1-10, higher=more |
| Democratic Support (5) | dem_strong_leader (W3-W7), dem_experts_rule (W3-W7), dem_army_rule (W3-W7), dem_democratic_system (W3-W7), dem_religious_law (W7) | 1-4, higher=more support for that system |
| Life Satisfaction (2) | happiness (W1-W7), life_satisfaction (W1-W7) | 1-4 / 1-10, higher=better |
| Political Engagement (2) | pol_interest (W1-W7), pol_discuss_friends (W1-W4, W7) | 1-4 / 1-3, higher=more |
| Political Action (5) | action_petition (W1-W7), action_boycotts (W1-W7), action_demonstrations (W1-W7), action_strikes (W1-W4, W6), action_other_protest (W5-W6) | 1-3, higher=more active |
| Media Consumption (9) | info_newspaper, info_magazines (W6), info_television, info_radio, info_mobile_phone, info_email, info_internet, info_social_media (W7), info_talk_friends | 1-5, higher=more frequent; W6-W7 only (W1-W5 incompatible scales) |
| National Identity (1) | national_pride (W1-W7) | 1-4, higher=more proud |
| Demographics (7) | sex (W1-W7), age (W1-W7), education_level (W2-W7, 1-3 harmonized), income_scale (W1-W7, 1-10), social_class (W2-W7), marital_status (W1-W7), employment_status (W1-W7) | varies |
| Derived (1) | education_level_01 (0-1 rescaled from education_level) | 0-1 continuous |
| Weights (1) | weight | continuous, mean ~1; wave-specific raw sources |

## Verbatim dictionary

`data/wvs/questionnaire_text/wvs_verbatim_items.csv` — Complete (79 vars, 7 waves, 553 rows).
