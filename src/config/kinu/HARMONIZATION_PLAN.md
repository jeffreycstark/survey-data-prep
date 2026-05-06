# KINU Unification Survey: Harmonization Plan

**Source files**:
- `data/kinu/raw/kinu_2014-2023_en.sav` (13,030 rows × 956 cols, 13 waves)
- `data/kinu/raw/kinu_2014-2024_codebook_en.xlsx` (cross-referenced codebook, 930 var-rows × 14 wave cols + Item / Response / Comments)

**Survey**: Korea Institute for National Unification (KINU) Unification Perception Survey (통일의식조사). Annual since 2014, biannual 2019–2021. Sample: ~1,000 South Korean adults aged 19+ per wave.

**Pipeline scaffolding** (already created):
- `src/r/data_prep_modules/kinu/0_load_waves.R` — splits the .sav by `year` integer code into 13 named waves (`w2014`, …, `w2019a`, `w2019b`, …, `w2023`) + exports `KINU_WAVE_TO_YEAR` and `KINU_WAVE_TO_MONTH` lookups.
- `src/r/data_prep_modules/kinu/2_harmonize_all.R` — thin wrapper calling the shared harmonization engine on `src/config/kinu/harmonize/`.
- `src/r/data_prep_modules/kinu/99_create_final_dataset.R` — combines per-wave masters → `data/processed/kinu_harmonized.{rds,parquet}`. Adds `country=KOR`, `year` (calendar year integer), `fieldwork_month` (Apr/Sep/Jun/Nov for sub-waves).
- `src/config/kinu/harmonize/` — empty; YAMLs go here.

---

## Wave structure

| Wave key | Calendar year | Fieldwork month | n |
|---|---|---|---|
| w2014  | 2014 | (Apr inferred) | 1,000 |
| w2015  | 2015 | – | 1,000 |
| w2016  | 2016 | – | 1,000 |
| w2017  | 2017 | – | 1,000 |
| w2018  | 2018 | Apr | 1,002 |
| w2019a | 2019 | Apr | 1,003 |
| w2019b | 2019 | Sep | 1,007 |
| w2020a | 2020 | Jun | 1,003 |
| w2020b | 2020 | Nov | 1,005 |
| w2021a | 2021 | Apr | 1,003 |
| w2021b | 2021 | Oct | 1,006 |
| w2022  | 2022 | Apr | 1,000 |
| w2023  | 2023 | Apr | 1,001 |

Total: **13,030** respondents across 13 wave files (2014–2023). The 2024 codebook column is for a wave not in this dataset; treat as future data.

KGSS-style decision: keep `wave` as a string column (`"2014"`, `"2019a"`, `"2023"`) so sub-waves are distinguishable, with `year` (integer) and `fieldwork_month` (integer) as the analytic companions.

---

## Codebook structure (key advantage)

Each row = one raw variable. Wave-presence columns (`14` … `24`) use ○ (asked) / X (not asked) markers. The codebook also carries `Item Label`, `Item` (verbatim Korean→English question), `Response` (verbatim scale), and `Comments`. **This is the cleanest cross-reference structure of any survey we've onboarded** — verbatim dictionary generation can be near-fully automated (see "Verbatim dictionary builder" below).

**Concept groups in the codebook** (930 variables total):

| Group | n vars | Theme | YAML file (proposed) |
|---|---|---|---|
| security | 258 | War probability, threat perception, alliance | `security.yml` (large; may split into `security_threat.yml` + `security_alliance.yml`) |
| attitudes | 223 | National pride, civic identity | `national_attitudes.yml` |
| North Korea | 125 | NK perception, NK info sources | `north_korea.yml` |
| politics | 93 (+1 mislabeled "정치") | SK direction, ideology | `politics.yml` |
| Unification | 79 | Necessity, expected benefits/costs | `unification.yml` |
| integration | 57 | Post-unification cohabitation concerns | `integration.yml` |
| policy | 57 | NK policy preferences | `nk_policy.yml` |
| demographics | 22 | Age, gender, region, marital, etc. | `demographics.yml` |
| Basic | 15 | id, year, fieldwork dates | `identifiers.yml` (some auto-handled) |
| 정치 | 1 | (Korean-named typo of `politics`) | merge into `politics.yml` |

The "정치" group has a single var (`pt1809`) clearly mislabeled — should be merged into `politics`.

---

## Directionality rule

**Project-wide rule** (per user feedback): *higher numeric value = more intensity*. Apply this consistently in the harmonized output.

**KINU's good news**: most KINU items already follow this rule. Examples surveyed:

| Variable | Raw scale | Direction | Harmonization |
|---|---|---|---|
| `uni01` (necessity of unification) | 1=strongly unnecessary → 4=strongly necessary | ✓ already correct | identity |
| `nk01` (interest in NK) | 1=not interested at all → 4=very interested | ✓ already correct | identity |
| `at01` (national pride) | 1=not proud at all → 4=very proud | ✓ already correct | identity |
| `se01` (SK security) | 1=very unstable → 5=very stable | ✓ "more security" higher | identity |
| `se02` (war possibility) | 1=never worried → 5=very worried | ✓ "more worry" higher | identity |
| Standard agreement (60 items) | 1=strongly disagree → 5=strongly agree | ✓ correct | identity |
| 0–10 support scales (28 items) | 0=oppose very strongly → 10=support very strongly | ✓ correct | identity |
| 0–100 thermometers (30 items) | 0=not at all → 100=to a very great extent | ✓ correct | identity |

Implication: **harmonization is mostly identity recoding**, not reversal. The bulk of the work is:
1. Missing-value handling (9 / 99 → NA)
2. Per-wave variable name aliasing (where a question's raw var changed across waves)
3. Sub-wave merging where appropriate (or keeping distinct, when wording diverged)
4. Documenting every direction decision in the YAML `note:` field

Cases where reversal *will* be needed: items where the natural Korean phrasing places the most-positive endpoint at code 1. Each YAML must check the `Response` field in the codebook before deciding.

---

## Special handling

### Missing codes
KINU uses simple sentinels:
- `9` for n/a within 1-point-something scales (like 1–4 or 1–5)
- `99` for n/a within 0-10 or 0-100 scales

No -1 / -8 / -9 like KGSS. Cleaner. Standard `missing_conventions: treat_as_na: codes: [9, 99]` per YAML.

### No weight variable
The codebook contains **no weight column**. KINU's published reports use weights (post-stratified by region × age × gender) but the microdata file ships unweighted. Two options:
- **A**: Treat KINU as unweighted in `kinu_harmonized` (mark `weight = 1` in the final-dataset script, document the limitation).
- **B**: Construct a post-stratification weight from KOSIS national age × gender × region marginals at fieldwork time. ~1 day of work; defensible methodologically; but requires per-wave calibration.

Recommendation: **A for now**, document clearly. If a paper requires comparable weighted estimates, build B as a follow-up.

### Sub-wave merging strategy
For 2019/2020/2021 sub-waves, the harmonization should keep `w2019a` and `w2019b` as distinct waves in the YAML `source:` map. When a question wording is identical across the two sub-waves, it is fine to use the same raw variable name in both keys. When the wording or response scale differs, harmonize them as separate items first (with notes documenting the divergence) before considering whether to combine.

### Variable-name churn across waves
Spot-checking the codebook shows many variables get renamed across waves (e.g., `int01` "hindrance to integration (2014)" vs `int0201` for the 2015+ version). The codebook's `Item Label` column is the authoritative cross-reference. **A given harmonized concept may map to 3–5 different raw variable names across the 13 waves.** This is similar to KGSS's `HEALTHY/HEALR/HEALTH23` pattern.

---

## Proposed YAML organization (drafting order)

### Phase 1 — Identifiers & demographics (low risk, high reuse)
1. **`identifiers.yml`** — id, fieldwork date variables. Mostly identity.
2. **`demographics.yml`** — gender, age, age_rge, cohort, birthyear, region, reg_size, dist, type, type20, marital. Standardize age coding; add `urban_rural` derivation if reg_size supports it.

### Phase 2 — Flagship unification series (compares to KGSS pol_unification candidate)
3. **`unification.yml`** — start with `uni01` (necessity of unification, 13 waves). Add the `uni0201–uni0220` sub-item battery (reasons unification is/isn't necessary). Add `uni0301–uni0303` (timing of unification preferred). This file alone will support a Korean-journal paper analogous to candidate #1 in `outputs/prospecting/korea_paper_candidates.md`.

### Phase 3 — North Korea perception
4. **`north_korea.yml`** — `nk01` (interest in NK), `nk02` (info sources, nominal — handle with `categorical` type), favorability/threat items. Look for items parallel to KGSS `pol_northkorea_view` (4-pt favorability) so we can triangulate the 2018 Pyongyang summit honeymoon paper (candidate #2).

### Phase 4 — NK policy preferences
5. **`nk_policy.yml`** — `pc0101–pcXXXX` series. These are 0=oppose / 10=support style scales; useful for sentiment toward sanctions, exchange, humanitarian aid, etc.

### Phase 5 — Politics & national attitudes
6. **`politics.yml`** — `pt0X` series including ideology, SK direction (sk performing well vs declining), party preferences. Merge the `정치` typo group.
7. **`national_attitudes.yml`** — `at0X` series for national pride and civic identity.

### Phase 6 — Security & integration (largest groups, most heterogeneous)
8. **`security_threat.yml`** — perceived threat from NK, China, Japan, US (likely a multi-target battery). Watch for the 1=Not threatening → 7=Extremely threatening 7-point scales and the 0–100 thermometers — different files if scale heterogeneity is severe.
9. **`security_alliance.yml`** — US alliance, China relations, deterrence. Defer if security-threat is already dense.
10. **`integration.yml`** — `int0X` series on hindrances to post-unification integration. Some items repeat for 2014 only (`old_*` style — see `int01` 2014 vs `int0201` 2015+).

### Phase 7 — Validation
After Phases 1–4 are done, run the harmonization pipeline + the slope prospector on the new KINU output. Compare the KINU `uni01` trajectory to the KGSS `pol_unification` trajectory; expect both to show a 2018 peak and post-2018 decline, but with KINU's biannual 2019–2021 fieldwork providing finer resolution that KGSS lacks.

---

## Verbatim dictionary builder (proposed)

Because the codebook is already in the cross-referenced format the project expects, we can semi-automate dictionary generation. Plan a script `src/scripts/build_kinu_verbatim.R` that:

1. Reads `data/kinu/raw/kinu_2014-2024_codebook_en.xlsx`.
2. For each variable × wave-column pair:
   - If `○`: emit a row with `wave=wXXXX`, `question_id=Variable`, `harmonized_name=` (filled by aliasing CSV; placeholder = raw var), `section=Group`, `stem_text="(see Comments column)"`, `item_text=Item`, `response_scale=Response`, `notes=Comments`.
   - If `X`: emit a row with `notes="Not included in this wave"` and the rest blank.
3. Outputs `data/kinu/questionnaire_text/kinu_verbatim_items.csv`.
4. Re-runs idempotently as YAMLs are drafted (the aliasing CSV grows; the codebook is fixed).

Aliasing CSV (`data/kinu/questionnaire_text/raw_to_harmonized.csv`):
| raw_variable | harmonized_name | yaml_file |
|---|---|---|
| uni01 | uni_necessity | unification.yml |
| nk01 | nk_interest | north_korea.yml |
| at01 | natid_pride_overall | national_attitudes.yml |
| ... | ... | ... |

This separates two concerns: the codebook (fixed source of truth) and the harmonized naming (which evolves with the YAMLs).

---

## Open questions / risks before drafting YAMLs

1. **Confirm year-code mapping for waves 1–4** (2014–2017). Loader assumes 1=2014, 2=2015, 3=2016, 4=2017 but this is inferred from the sequential codes 5–13 (which have explicit labels). Verify against KINU's published reports.
2. **2024 codebook column** — codebook has data for `24` that is not in the .sav we hold. Either request the 2024 file from KINU or KOSSDA, or strip the 2024 column from the verbatim build.
3. **Sub-wave question stability** — for items present in `19a` AND `19b`, are wording and response scales identical? Codebook's `Comments` field should flag changes; need to walk through to be sure before harmonizing as one variable.
4. **Direction edge cases** — confirm by spot-check that the dozen most common Response strings all have the most-intensity-end at the high numeric end. Several integration items use "1=very, 4=moderate, 7=very" 7-point bipolar scales (e.g., 1=very weak → 7=very strong) — these are fine; but some bipolar scales have neutral midpoints which means "intensity" is genuinely two-tailed (e.g., 1=very negative, 50=neither, 100=very positive). For these, the rule "higher = more intensity" is meaningless without a substantive direction choice. Flag in YAML notes.
5. **Free-text variables** (`uni04_open`, `uni08_open`) — out of scope for harmonization; ignore.

---

## Comparison to other surveys

KINU sits alongside KGSS as a Korea-only longitudinal series, but with a sharper unification/NK focus and finer 2019–2021 temporal resolution. The two surveys ask analogous questions about unification and NK perception, but with different question wording and scales:

| Concept | KGSS variable | KINU variable | Comparable? |
|---|---|---|---|
| Necessity of unification | `pol_unification` (1=necessary, 4=oppose) | `uni01` (1=strongly unnecessary, 4=strongly necessary) | Yes — opposite directions; harmonize so higher=more pro-unification (KGSS reverses, KINU identity) |
| View of NK | `pol_northkorea_view` (1=positive, 4=negative) | TBD (likely a thermometer or threat scale; pick parallel item) | Yes after harmonization |
| NK defectors | `pol_nk_defectors` | TBD | Probably parallel |

This means the KINU + KGSS pair could anchor a strong triangulation strategy for the candidate paper #1 (post-2018 unification disillusionment) and #2 (Pyongyang summit honeymoon) in the prospector memo.

---

## Per-group inventory (from codebook reconnaissance)

Built via `tmp/kinu_group_survey.R`; full per-variable detail in
`data/kinu/questionnaire_text/kinu_variable_inventory.csv`.

| Group | Total vars | 8+ wave coverage | YAML status |
|---|---|---|---|
| security | 258 | 1 | sparse longitudinally — only one fully-covered item; defer or harvest few-wave items selectively |
| attitudes | 223 | 48 | rich; covers domain-pride battery, institutional trust, post-materialism, SDO, system justification |
| North Korea | 125 | 34 | rich; covers NK image (4-item 0–10 thermometer × 13 waves), interest, regime trust, refugee perception, neighbor perception |
| politics | 94 | 19 | covers ideology, SK direction, party preference (mostly categorical) |
| Unification | 79 | 19 | **DONE** (17 harmonized in unification.yml) |
| integration | 57 | 6 | mostly social-conflict items (int0501–int0505 + int04, all 1-4 scale, 8–10 waves) |
| policy | 57 | 10 | NK policy preferences (0–10 scales) |
| demographics | 22 | 14 | core respondent attributes |
| Basic | 15 | 12 | id, age, gender, region, year (some auto-handled by loader) |

## Status of each YAML (drafting order)

1. **`unification.yml`** ✅ done (17 vars)
2. **`demographics.yml`** ← in progress; covers age, sex, age_5cat, cohort, birthyear, region, urban_rural, subjective_income_5pt, subjective_class_6pt, religion, religious_attendance, marital_status, education, employment, home_region, income (manwon, continuous)
3. **`north_korea.yml`** — flagships: nk0401–nk0404 (NK image 0–10 thermometer × 4 facets, 13 waves), nk01 interest (12 waves), nk05 trust in Kim Jong-Un (11w), nk06 dialogue/compromise (11w), nk0701–nk0708 perception items, nk0801–nk0807 refugee perception, nk1201–1203 nuke-feelings, nk21a–f neighbor perception
4. **`nk_policy.yml`** — pc0101–pc0108 (8 items, 0–10 oppose-support scales, 8–12 waves): economic exchange, sports/culture, sanctions, humanitarian aid, denuclearization
5. **`national_attitudes.yml`** — at01 (overall pride, 13w), at0201–at0210 (domain pride × 10 facets, 12w each), at06 (general trust, 11w 0–10), at0701–at0706 (institutional trust battery, 9w 0–10), at1201–at1206 (post-materialism), at1701–at1703 (multiculturalism), at19a–at19h (SDO), at2801–at2804 (system justification)
6. **`politics.yml`** — pt* SK-direction series (only 2015–2017), ideology, party preference (categorical), efficacy/satisfaction items; merge the lone `pt1809` from the 정치 typo group
7. **`security_threat.yml`** — *sparse;* most security items are wave-specific. Likely to be a small file with the 1 fully-covered item plus selected 5–7-wave items
8. **`integration.yml`** — int0501–int0505 + int04 (social conflict perception 1–4 scales, 8–10 waves)
9. (defer) `security_alliance.yml` — alliance/deterrence items if not absorbed by security_threat
10. **`backfill verbatim` + CLAUDE.md** — once YAMLs done
11. **`prospector run + memo addendum`** — final step

## Per-YAML wave-coverage summary (going in)

For each YAML, I aim for 8+ wave coverage as the inclusion threshold; a "narrow" YAML (5–7 wave items only) is acceptable when the substantive value is high (e.g., the post-Pyongyang-summit window).

## Estimated effort

| Phase | Specs | Effort |
|---|---|---|
| 1 demographics | 1 YAML, ~14 vars | 0.5 day |
| 2 unification | 1 YAML, 17 vars | DONE |
| 3 NK perception | 1 YAML, ~15–20 vars | 0.5 day |
| 4 NK policy | 1 YAML, ~10 vars | 0.5 day |
| 5 national attitudes | 1 YAML, ~30 vars | 1 day (largest) |
| 6 politics | 1 YAML, ~10–15 vars | 0.5 day |
| 7 security threat | 1 YAML, ~5–10 vars (sparse) | 0.5 day |
| 8 integration | 1 YAML, ~6 vars | 0.5 day |
| Verbatim backfill + CLAUDE.md | 1 R script + edits | 0.5 day |
| Prospector + memo addendum | – | 0.5 day |
| **Total to fully-harmonized KINU** | ~9 YAMLs, ~110 vars | **~5 days** |

A "minimum-viable-KINU" (demographics + unification + NK perception + NK policy) is ~2 days and would already enable the unification-disillusionment / Pyongyang-summit papers with full subgroup decomposition.
