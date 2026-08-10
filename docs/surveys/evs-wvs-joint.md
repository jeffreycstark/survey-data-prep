# Joint EVS/WVS 2017–2022 (ZA7505 / WVSA joint release v5.0.0)

**Status: Complete for the paper-26-adjacent CEE design** (24 vars). Built
2026-08-10 for the trust-typology → participation-withdrawal design.

## What this is

The pooled EVS 2017 + WVS7 common core: **156,658 respondents, 92
country-surveys, fieldwork 2017–2023** (internal version stamp `5-0-0
(2024-06-24)`), one cross-sectional "wave" (`joint2017_2022`). Source:
`data/wvs/raw/evs_wvs_joint/EVS_WVS_Joint_Spss_v5_0.sav`. `uniqid` is fully
unique — the cleanest native key in the bank. **Separate survey from `wvs`**
(which harmonizes the WVS longitudinal per-wave files); do not row-bind the
two — WVS7 respondents appear in both.

## CEE coverage

22 post-communist countries: PL HU CZ SK RO BG HR SI EE LV LT RS BA MK AL ME
UA BY RU GE AM AZ. ⚠️ Several (incl. **RU, RS, RO**) were fielded by BOTH
studies — two independent samples per country. Keep `study` (1=EVS, 2=WVS) in
every pooled model; treat the two samples as distinct surveys of one country.

## The design measures (verified 2026-08-10)

- **Independent — trust typology.** `trust_government`, `trust_parliament`,
  `trust_parties` (E069 confidence, reversed → higher = more trust, 1–4) and
  `trust_elections` = **E265_01 "votes are counted fairly"** (reversed →
  higher = more perceived integrity). ⚠️ There is NO confidence-in-elections
  item in the joint file (WVS7's Q76 didn't survive the common core) — the
  procedural-integrity item is the substitute, fielded by BOTH studies
  (EVS 88% / WVS 91%). `trust_election_officials` (E265_06) is the secondary
  integrity measure; the other six E265 items exist raw, unharmonized.
- **Dependent — withdrawal repertoire.** `action_petition/_boycott/
  _demonstration/_strike` (E025–E028) keep the NATIVE 3-level ordinal:
  **1=Have done, 2=Might do, 3=Would never do — higher = more withdrawal**,
  a deliberate exception to the bank's higher-is-more-participation habit
  (the paper leads with the would-never category as the dispositional
  withdrawal measure). CEE would-never shares: petition 42%, boycott 65%,
  demonstration 53%, strike 73%.
- **Third arm.** `dem_strong_leader` (E114, reversed → higher = MORE
  pro-strong-leader). CEE r with trust_elections = −0.11.
- **Controls.** `gender` (1=male), `age`, `education_isced` (0–8),
  `income_decile` (loader-coalesced from study-split X047_WVS7/X047E_EVS5;
  89% CEE coverage), `urban_size` (1–5), `pol_interest` (reversed → higher =
  more interested), `ideology_lr` (1–10, higher = right; ~72% CEE coverage —
  the leakiest control).
- **Country-level controls join at paper time**: `v2x_polyarchy` from
  `data/processed/vdem_core.rds` on ISO (joint carries ISO2 `country`,
  V-Dem carries ISO3 `country_text_id` — convert via `countrycode`) × `year`.
  ⚠️ V-Dem's `e_gdppc` (now in vdem_core) **ends at 2019**; for the 2020–2023
  fieldwork years take GDP pc from World Bank WDI instead.

## Weights

`weight` (gwght, within-country equilibrated) and `weight_pop` (pwght);
multiply the two for pooled cross-country analysis.

## Missing scheme

All negative (−1 dk, −2 no answer, −3 n/a, −4 not asked, −5 other) —
collision-free by design. IDs carry no missing codes.

Pipeline: `src/r/data_prep_modules/evs_wvs_joint/`; specs in
`src/config/evs_wvs_joint/harmonize/` (identifiers, trust, political_action,
demographics). Key declared in `key_declarations.yml` (`uniqid`).
