# Audit findings — open for review

Last updated: 2026-08-09

This file records audit findings that need substantive judgment from Jeff. The audit infrastructure surfaces; this file tracks what remains to investigate. Update as items get resolved.

**Open right now: 22 findings + 16 framework tickets.** (The `int_year` finding is half-closed: W1 fixed 2026-08-09, W2 still open and not fixable from the data.)

| Bucket | Open |
|---|---|
| 🔴 Engine fault-injection hazards | 5 |
| 🔴 ABS `int_year` gap — W1 fixed, **W2 open** (new 2026-08-09) | 1 |
| 🔴 ABS `idnumber` — root cause fixed; **2 HK W5 duplicates need a decision** | 1 |
| 🔴 Residuals carried from resolved entries | 2 |
| 🟡 Check D binning seams | 8 |
| 📋 Residual systematic findings | 5 |
| 🛠 Framework tickets (not findings) | 16 |

Resolved items live in *Resolved findings (audit trail)* and *Resolved — full records* at the bottom. Per the convention at the end of this file, nothing is deleted.

---

## ⚠️ Standing warnings — re-run obligations

These are not tasks. They are conditions any downstream analysis must satisfy.

### ⚠️ BREAKING DATA CHANGE 2026-07-31 — WVS `freedom_vs_equality` was wrong in W2, now fixed

**Anything built on `freedom_vs_equality` before 2026-07-31 must be re-run. The W2 arm of this variable was not merely lossy, it was substantively wrong, and the error was silent.**

The two waves do not share a code order, and the spec assumed they did:

| wave | raw | 1 | 2 | 3 |
|---|---|---|---|---|
| W7 | `Q149` | Freedom | Equality | — |
| W2 | `V247` | Freedom | **Neither** | **Equality** |

Under `method: identity` with `valid_range: [1, 2]`, W2 produced:

| W2 raw | n | became | labelled |
|---|---|---|---|
| 1 Freedom | 10,455 | 1 | "Freedom" ✓ |
| 2 **Neither** | 2,029 | 2 | **"Equality"** ✗ |
| 3 **Equality** | 8,787 | **deleted** | — ✗ |

So W2 contained **no equality responses at all**, and the 2,029 cases sitting in the "Equality" slot were the people who refused the choice. Pooling W2 with W7 compared W7's equality camp against W2's *neither* camp. The spec's own note asserted "W2 code 3 (Neither) treated as NA", which had codes 2 and 3 backwards — so the bug was documented as intended behaviour, which is why it survived.

- **Now:** W2 uses an explicit recode (1→1, 2→NA, 3→2); W2 Equality reads 8,787. W7 is unchanged.
- **Direction of the error:** any W2 "equality" estimate was built on the wrong 2,029 respondents and understated the equality camp roughly 4×. Anything comparing W2↔W7 on this item is invalid, not just imprecise.
- **Found by:** out-of-range triage (`src/r/audit/03_oob_triage.R`) flagging the 8,787 deletions; confirmed against the raw SPSS value labels. No direction, battery, or label check could see it — the harmonized values were in range, internally consistent, and matched their (wrong) declared labels. This is the "wrong-but-consistent recode" class `docs/QA.md` names as uncovered.


---
## 🔴 High priority — open

### NEW 2026-08-09: ABS `int_year` — **W1 FIXED same day; W2 remains open and is NOT fixable from the data**

**W1 RESOLVED 2026-08-09.** Source repointed `ir007_3` → `yrsurvey` in
`src/config/abs/harmonize/demographics.yml`. The whole `ir007_*` interview-record block is empty for
Korea and Mongolia in the W1 merge; `yrsurvey` is populated 8/8 countries and agrees with `ir007_3`
wherever both exist. Re-harmonized and verified: **W1 int_year 78.3% → 100%**, all eight countries
at 100%, **2,649 respondents recovered** (Korea 1,500, Mongolia 1,144, plus 5 stray Thai cases).
Invariants after the rebuild: `int_year` 73 ok / 7 warn / 0 error — the warns are all "sparse levels"
(each wave spans a few years against a declared 2001–2025 range), which is structural and predates
this change. The three ABS error rows (`idnumber` w6, `gate_contact_influential` w2 ×2) are unrelated
and pre-existing; the latter is the documented post-hoc country substitution. Cost of the swap:
`yrsurvey` is year-only, so `int_day`/`int_month` stay on `ir007_1/_2` and remain NA for Korea and
Mongolia — the year is recoverable, the full date is not.

**W2 STILL OPEN, and no spec change can close it.** Verified column-by-column: the entire `ir9_*`
block (day, month AND year) is empty for **Korea, Philippines, Thailand and Singapore**, W2's merge
carries no `yrsurvey` equivalent, and no field anywhere in those rows holds a 2000–2010 value. Those
four countries have no interview date in the release at all. A year for them must come from ABS
fieldwork documentation, not from the data. **Do not assume a single W2 year** — the nine countries
that do report one spread across 2004–2008 (Mongolia/Taiwan/Indonesia/Vietnam 2006; Japan/HK/Malaysia
2007; Cambodia 2008; China splits 531 in 2007 and 4,508 in 2008). Suggested shape: a
`data/lookups/abs_fieldwork_years.csv` keyed country×wave with a `source` column, coalesced after
`ir9_3`, so the provenance stays visible rather than becoming constants buried in a spec.

Original finding below for the record.

- **What:** `int_year` is missing in **six country×wave cells**, not in any whole wave or year. Wave-level coverage is W1 78.3%, W2 74.6%, W3 94.8%, W4–W6 100%. The zero cells:

| Country | Wave(s) at 0% |
|---|---|
| Korea | **W1 and W2** |
| Mongolia | W1 |
| Philippines | W2 |
| Singapore | W2 and W3 |
| Thailand | W2 |

  Plus Mainland China W2 at 99% (a handful of cases). Everything else is 100%. The substantive columns are unaffected — `age` and the democracy-placement battery are fully populated in the cells that matter.
- **Why it bites:** birth year = `int_year - age` is the only route to a cohort variable, so any age-at-event / generational analysis silently returns all-NA for Korea and for Philippines W2. Found while building an authoritarian-memory cohort split: the first run produced empty cells for Korea in both waves and looked like a substantive absence rather than a harmonization gap.
- **The fix is available and exact.** ABS W1 raw (`data/abs/raw/wave1/Wave1_20170906.sav`) carries `yrsurvey`: Japan 2003, Hong Kong 2001, Korea 2003, Mainland China 2002, Mongolia 2003, Philippines 2002, Taiwan 2001, Thailand 2002. Map it into `int_year` for W1 across all countries.
- **W2 has no year variable at all** in `data/abs/raw/wave2/Wave2_20250609.sav`, yet W2 is 74.6% populated — so the values present for Japan, Taiwan, China, Indonesia, Malaysia, Vietnam, Cambodia and Hong Kong are arriving from somewhere else that has not been traced. **Find that source before trusting any W2 year**, then either extend it to Korea / Philippines / Thailand / Singapore or set W2 uniformly NA. The current country-patchy state is the worst option, because a wave that is three-quarters populated reads as complete and silently drops the four missing countries from any cohort analysis.
- **Observed year values contain no 2005, 2009, 2013 or 2017** — consistent with ABS fieldwork gaps rather than a defect, but worth confirming rather than assuming, since the four W2-missing countries are exactly the ones whose fieldwork year would sit at the W2 boundary.
- **Related, worth recording while here:** ABS W1 and W2 ship **no survey weights** — not a harmonization gap, the raw release files contain no weight variable (`weight` and `weight_cross` are populated W3+ only; `weight_cross` is W3/W4 only). Any W1/W2 analysis is unweighted by necessity. This is not fixable, only documentable, and belongs in `docs/surveys/abs.md`.


---

### ~~NEW 2026-08-09~~ **MOSTLY RESOLVED 2026-08-09**: ABS `idnumber` — 357 real IDs were being deleted as missing codes

**ROOT CAUSE FOUND AND FIXED.** The 357 NA `idnumber`s were not a data gap — they were real IDs
destroyed by a convention collision, in two layers:

1. `idnumber` used `use_convention: treat_as_na`, which deletes `[-1, 0, 7, 8, 9, 97, 98, 99, 1099]`.
   ABS numbers respondents serially from 1 per country-wave, so **every** cell contains a respondent
   7, 8, 9, 97, 98 and 99 — all six were NA'd, ~6-7 per cell across ~55 cells. Raw Korea W2 has
   1,212 rows and **zero** missing IDs. Repointed to a new `no_missing_codes` convention: a serial
   identifier has no missing codes.
2. That only got 357 → 160. The rest was `no_verify()` carrying its own hardcoded
   `missing_codes = c(-1, 97, 98, 99)`, which the engine never overrides with the declared
   convention. **This is finding #3 of the 2026-08-07 engine fault-injection entry, which assessed
   it as "No live exposure". It was live — here.** Default changed to `numeric(0)`; a function named
   `no_verify` and documented as returning values as-is must not delete anything. Verified safe for
   its only other consumer (KLoSA `iw_month` 3-12 / `iw_day` 1-31 contain none of those codes).

**Result after re-harmonize:** NA `idnumber` **357 → 0**; duplicate keys on country+wave+idnumber
**302 → 2**; ABS invariant errors 2 → 1.

**STILL OPEN — needs Jeff's decision.** Two Hong Kong W5 keys remain duplicated: `704273201`
(two rows identical across **all 308 columns**) and `704273901` (identical in 307 of 308, differing
only in the **weight factor**, 1.467 vs 1.394). Both are present in the raw ABS W5 release, not
created by our merge. Byte-identical answers to 300+ questions rule out two distinct respondents, so
these are duplicated records; the differing weight suggests duplication preceded weighting. **Not
deleted** — dropping respondent rows changes the sample and the weight totals, which is Jeff's call.
Options: drop one of each pair, keep and document, or query ABS.

Plain-English writeup for Jeff: `research-vault/ABS idnumber bug — why respondent IDs were
disappearing (2026-08-09).md`.

**Two framework questions this raises:**
1. Should the harmonizer mint a synthetic `row_uid`, so downstream code never needs `idnumber`?
2. Should an invariant assert uniqueness of the declared key? Nothing in the audit stack does, which
   is why 357 destroyed IDs and 302 collapsed keys were invisible until Jeff asked.

Original finding below for the record.

### ~~Original~~: ABS has NO unique row identifier — `idnumber` collides even within country×wave

Surfaced by Jeff while reviewing the `int_year` work ("the idnumbers are not unique from wave to
wave" / "don't rely on them being unique"). Verified, and the problem is one level worse than that.

- **`idnumber` is a per-country, per-wave sequential counter.** It restarts each wave, so the same
  value denotes different people in different waves — `idnumber = 1` appears in 7 countries in W1,
  11 in W2, 10 in W3, 12 in W4, 8 in W5, 5 in W6. ABS is a repeated cross-section, not a panel;
  there is no respondent to follow. Any join on `idnumber` fabricates links between unrelated people
  and will not error.
- **`country + wave + idnumber` is ALSO not unique.** 113,945 rows → 113,643 distinct triples. The
  302 extra rows decompose into **357 rows with NA `idnumber`** across 55 country×wave cells, plus
  **2 genuine duplicates in Hong Kong W5** (`704273201`, `704273901`, each twice). Excluding NA rows:
  113,588 rows → 113,586 distinct triples.
- **Consequence: `abs_harmonized.rds` has no unique row key.** Row position is the only identifier.

**Why this is a finding and not a note.** The audit layers check variable direction, ranges, labels
and coverage — none of them assert row-level uniqueness, so a downstream `left_join` on `idnumber`
would inflate row counts silently, and a `distinct()` on the triple would drop 302 real respondents.
Both are the "wrong-but-consistent" class `docs/QA.md` names as uncovered.

**Open questions for Jeff:**
1. Should the harmonizer **mint a synthetic `row_uid`** (survey + wave + country + row index) so
   downstream code has something safe to key on? Cheap, and removes the temptation.
2. The **2 Hong Kong W5 duplicates** — genuine duplicate records in the release, or a merge artefact
   on our side? Worth checking the raw W5 file before assuming ABS shipped them.
3. Should an **invariant check** assert uniqueness of whatever key we declare, so this cannot regress?

Recorded in `CLAUDE.md` gotchas 2026-08-09 so it binds future sessions regardless of this file.

---

### NEW 2026-08-07: engine fault-injection — Check E is structurally blind to non-identity methods, plus four latent hazards

Fault-injected `harmonize.R` + `.safe_npt` directly with adversarial inputs (script pattern preserved in this entry's commit). Findings, ranked:

**1. 🔴 The out-of-range log only ever sees `method: identity` deletions.** `.safe_npt`'s `TRUE ~ NA_real_` arm absorbs any out-of-domain value *inside* the fn; `method: recode` initialises output to NA and never logs unmapped values. By the time `valid_range` runs, the evidence is already `NA` — so Check E (layer 2b) structurally cannot see a deleted response category in ANY `r_function` or `recode` variable. Verified synthetically (stray code 5 on a 4-pt item: identity → logged; `safe_4pt_none` → 3 values deleted, 0 logged; `recode` → same) and in production: every row in `outputs/abs/oob_log.csv` is an identity path — `pol_news_follow`'s logged wave (w2) is an identity *exception*. **The WVS `freedom_vs_equality` bug was catchable only because that spec happened to use identity.** The same bug behind a `safe_*` fn would still be invisible today. Fix sketch: have `.safe_npt` attach an `n_absorbed` attribute (it knows exactly which values hit the fall-through arm) and have the engine log it; count unmapped values in the `recode` branch.
**2. 🔴 `.safe_npt` has no domain guard.** `safe_reverse_4pt` on a 5-pt raw silently deletes the 5s (unlogged, per #1); `safe_reverse_5pt` on a 4-pt raw silently SHIFTS to 2–5 — the `gov_leaders_abuse_power`/`party_closeness` class reproduced at engine level. The 08-range-report now catches this symptomatically (RANGE-VARIES-BY-WAVE, 26 variables); the engine could catch it at cause.
**3. 🟡 fn default `missing_codes` override the spec.** Spec declares missing = {7,8,9}; `safe_4pt_none`'s own default *also* deletes 0. The declared convention is not what governs — the union of convention + fn defaults is. **No live exposure** (0 specs pair a `safe_*` fn with a 0-based valid_range) but any future 0-valid scale through `safe_*` loses its zeros. Fix: engine passes the resolved convention codes INTO the fn instead of letting fn defaults apply.
**4. 🟡 `method: identity` on a character column compares lexicographically at the range gate.** Verified: with valid_range [1,50], "9" is deleted ("9" > "50" as strings) while "100" is kept. **No live exposure** — the one character column with a range (`country` w6) is converted by `recode_w6_country` before QC. Fix: coerce or refuse character at the QC step.
**5. ✅ FIXED in this commit: `.validate_semantic_label` crashed on labels-without-label columns.** `attr(data[[v]], "label")` partial-matched the value-label vector → `is.na()` length > 1 → hard error under R ≥ 4.2. Now `exact = TRUE` + `[1]`. Zero current exposure (`validate_all` appears in no spec) but it was a crash waiting for the first user of a documented feature.
**6. 🟡 `harmonize_all` converts a crashed variable into a warning and drops it.** 2 variables in, 1 out, no error — a spec crash makes its variable silently absent from the harmonized file. The freshness/invariant layers do not flag a variable that simply is not there. Consider collecting errors and failing at the end.


---
### Still open, carried from resolved entries below

Two residuals whose parent findings are fixed and filed in *Resolved — full records*:

- **ABS W6: 87 label-conflicting columns remain unverifiable by construction.** The W6 label-metadata restore (2026-08-05) recovered 156 of 488 columns; 87 are left unlabelled because countries disagree code-for-code and the merge reports rather than silently resolves them. Direction cannot be checked for those until someone decides how to reconcile country-specific label text. Full record: *ABS W6 label metadata dropped by our own merge*.
- **Convention-collision check audits identity waves only.** `check_convention_collisions.R` cannot see convention codes colliding with an `r_function`'s expected raw input — the `govt_anticorrupt_effort` case. Needs an fn-input-domain check against the registry's `input_scale`. Full record: *Convention-collision class*.


---

## 🟡 Medium priority (2026-07-22) — Check D sweep findings needing editorial judgment

First all-survey bin-width parity sweep surfaced these beyond the W5 class above. Each is a real cross-wave binning seam; decide fix vs exempt-with-reason (`src/config/_audit/bin_width_exemptions.yml`). Already exempted as documented: afro/wvs `education_level`, lbs `crime_victim` (2024), ipus `uni_view` (2019 restructure).
- **abs `hh_income_sat`** — w4 is a 3-pt instrument (`safe_reverse_3pt`), w5/w6 collapse 5→4 (`collapse_5pt_to_4pt_then_reverse`), w2/w3 native 4-pt. Three different binnings across waves.
- **abs behavioral binarizations w5/w6** — `gate_contact_*`, `gate_petition`, `gate_demonstration` (`recode_contact_to_binary_5pt`, `1:3|0:2`), `community_leader_contact` (5→3 with both poles merged, w5/w6). Deliberate design, but wave-asymmetric; verify earlier waves' native categories match the chosen thresholds, then exempt with reason.
- **abs one-wave collapses** — `corrupt_witnessed` (w3/w4 binarizations differ from each other), `corrupt_local_govt`/`corrupt_national_govt` (w6), `govt_anticorrupt_effort` (w2), `gov_elections_real_choice` (w5), `current_status_unemployed` (w3), `pol_discuss` (w1), `news_internet` (w4 vs w5/w6), `sm_express_political` (w4), `govt_withholds_info` (w5/w6), `intl_*_world_influence` (w5 10→6), `procedural_preference_index` (w5), `glob_cultural_defense`/`glob_trade_protection` (w5/w6 binary vs 4-pt earlier).
- **ipus `urban_rural` w2008** — bottom-merge `1:2` (also the one remaining IPUS L3 error from 2026-05-12).
- **arab-barometer `employment_status` w5/w7/w8** — 8 source categories into 3 bins vs finer elsewhere (nominal-ish; may just need exemption).
- **afro `turnout` w5** — six non-voter categories merged to 0 vs fewer elsewhere.
- **wvs `corrupt_national_govt` w3** — 4-pt identity vs a wider-binned modal elsewhere; check which wave is actually the odd one.
- **abs `dem_essential_harmonized` w2/w5** — `warn` (all-width-1 cardinality drift 4/5/6-target across waves; derived-variable domain drift, not a merge).


---
## 📋 Residual systematic findings (post-fixes)

These are categories where the audit infrastructure is doing its job but the remaining signal needs a YAML hardening pass.

### ABS missing_codes residue
After the bulk-add of `missing.use_convention` (commit pending), ABS F4 missing_codes fails dropped from 931 → 54. The residual 54 are real cases where:
- Some variable's codebook has missing codes the YAML's chosen convention doesn't cover.
- Or per-variable `missing.codes:` overrides are incomplete.

Worth a one-pass review to either tighten conventions or add per-variable `missing.codes:` entries.

### KINU missing_codes residue
KINU's residual after bulk-add: 1097 → 409. Higher than ABS because KINU questionnaire layout uses 9/99/9999 inconsistently across waves. Each spec's `missing_conventions:` block needs to capture all the codes used. Worth a per-spec review.

### IPUS missing_codes residue
IPUS residual: 61 → 18. Manageable. Likely related to the wave-specific KOSSDA recoding markers (5.5).

### ABS value_labels surface mismatches
~140 fail rows from cosmetic differences:
- "60+" vs "over 60"
- `dem_statement_*` family: YAML uses analytical shorthand ("Statement A/B/C") while codebook stores full statement text
- `cohort` "Millennials" (YAML) vs "Millenials" (codebook typo)

These are not bugs — the YAML's labels are reasonable. Could be silenced by either tightening F4's fuzzy match or accepting the surface noise.

### AFRO `age_cohort` (separate from the false-positive case)
The false-positive Spearman ρ ≈ 0.965 was resolved (commit `b6b315e` added the function to F4's skip list). But: any genuine off-by-one in the bin boundaries would have been hidden by the same cap. Worth a one-time hand verification of the age→cohort mapping at boundary ages (29/30, 39/40, 49/50, 59/60) using a few country/round samples.


---
## 🛠 Open audit framework work (incomplete tickets — not findings)

These are framework tickets that haven't shipped yet. Each is in `audit/02-implementation-tickets.md` if you want to dispatch a fresh agent.

### Phase B (deferred)
- B5: Make `valid_range` mandatory (no longer warn on missing — error)
- B6: Require `qc.validate.phrase` for `safe_reverse_*` rules
- See memory file: `~/.claude/projects/-Users-jeffreystark-Development-Research-survey-data-prep/memory/project_audit_phase_b_deferred.md`

### Phase D (partial — D1-D4 + D8-D9 done)
- D5: Undeclared-reversal scan (variables with `method: identity` whose anchor correlation is opposite the expected sign)
- D6: Per-country sign-disagreement explicit module (partly subsumed by D3 but a dedicated CLI would help)
- D7: `qc.wave_direction_flip:` schema support (declare wave-specific anchor direction reversals)
- D10: Cross-survey `authoritarianism` anchor (currently only ABS-side via `democratic_attitudes`)

### Phase F Tier 3 (deferred)
- KGSS PDF extraction (Korean cumulative codebook)
- KIPA-corruption PDF extraction (per-year Korean + English)
- LBS PDF extraction (per-year Spanish + English, ~24 years × 2 langs)
- AFRO PDF extraction (R1 + R9 + per-round)
- WVS PDF extraction (7 wave codebooks)
- Arab Barometer PDF extraction
- KAMOS PDF extraction

ABS Tier 2 done (SPSS metadata, 99.6% coverage). Tier 1 (KINU + IPUS xlsx) done. Tier 3 is the long tail.

### Phase H (CI integration)
- ~~H1: Local audit orchestrator (`make audit`)~~ — **DONE 2026-08-03.** `run_all.R`
  already existed; the ticket's remaining part was the convention wrapper. `Makefile`
  adds `make audit` / `audit-quick` / `audit-specs` / `audit-report` / `check-r`
  (`make audit SURVEY=abs` narrows to one survey). Thin wrappers only — no logic in
  the Makefile, so `make` and a bare `Rscript` call stay interchangeable.
- **H2: PARTIAL 2026-08-03** — `.github/workflows/audit.yml` gates every check that
  works from the source tree alone: R parse over 124 files, Layer 1 schema validation
  for all 12 surveys, recoding-registry drift. Runs on PR + push to main, blocking.
  **It cannot do what the ticket asked.** The ticket says CI should run
  `run_all.R --survey abs`, but `*.sav` and `data/processed/*.rds` are gitignored and
  the raw data is licensed — a runner has no data, so L2/L3/L4/L5/L6 are unrunnable
  in CI and are skipped by the new `--specs-only` flag (which also suppresses the
  exit-2 "prereqs missing", since on a clean checkout that is the expected state).
  Verified by cloning to a data-free tree: exit 0 clean; malformed YAML → exit 1;
  schema violation (`method: nonexistent_method_xyz`) → exit 1. **Untested against a
  live runner** — the workflow has never executed; first PR proves it.
  To close H2 as specified you need data on the runner: a self-hosted runner with a
  data mount, or committing `data/processed/*.rds` (check licences first).
- H3: Per-layer gating policy — **partly moot until H2 is closed.** The layers that
  the ticket wants split into block-vs-warn (L1/L3/L4/L6 block, L2/L5 warn) are, apart
  from L1, exactly the layers CI cannot run. Everything CI runs today is blocking.
- H4: Audit-pass certificate generator for tagged releases


---
## ✅ Resolved findings (audit trail)

For the record — items the audit caught and that have been investigated/fixed.

| Date | Variable | Outcome | Commit |
|---|---|---|---|
| 2026-05-09 | ABS W6 builder hazard | Fixed (delegate + guard) | `5e02866` |
| 2026-05-09 | `compute_procedural_index` missing from registry | Added | `34ff235` |
| 2026-05-09 | Duplicate `id: hh_income_sat` across two ABS specs | Removed from `demographics.yml` | `48ac398` |
| 2026-05-09 | `dem_extent_current` "critical citizens" pattern in anchor | Anchor sign demoted to `either` | `27131d1` |
| 2026-05-10 | ABS `hh_income_sat` W5 value-5 leakage + W2 stale output | Function fix + pipeline rerun | `2d8a7e3` |
| 2026-05-10 | ABS W1 fractional dem-rating values | Type changed `ordinal → continuous` (later refined per `dem_extent_current` finding) | `2d8a7e3` |
| 2026-05-10 | AFRO `age_cohort` ρ 0.965 false positive | Added to F4 skip list (5-bin discretization ceiling) | `b6b315e` |
| 2026-05-10 | IPUS `uni_timing` 13-26% coverage loss across 2007-2014 | Raw scale is 6-cat not 5; fixed mapping | `b6b315e` |
| 2026-05-10 | KINU `urban_rural` "directional swap" | F4 false positive (post-harmonization labels vs raw codebook); F4 fixed to skip non-identity methods | `f624cfd` |
| 2026-05-10 | `dem_extent_current` Frankenstein scale (W1 10pt vs W2-W6 4pt) | Verified against W2 codebook + .doc questionnaire; W1=null, type=ordinal, scale 1-4, reverse-coded | `66d1ed8` |
| 2026-05-12 | AFRO `dem_satisfaction` "Country is not a democracy" responders silently dropped | Split into sister binary `dem_country_not_democracy` (R1-R9); 4,898 cases across rounds now captured instead of NA-coerced. R9's 932 cases were also being silently dropped under identity+range-coerce. | `dda1b22` |
| 2026-05-12 | KINU `home_region` over-claim `[1,19]` | Narrowed to `[1,18]` (raw `home` only has 18 codes — 17=NK, 18=Foreign). KINU has TWO region coding schemes; `home` and `region` are NOT parallel despite identical 1-16 codes. | _this commit_ |
| 2026-05-12 | KINU `cohort` apparent over-claim `[1,7]` | Confirmed AGAINST narrowing after investigation. The xlsx codebook documents codes 1-6 only, but the raw .sav has code 7 ("Z generation") with 290 observations across 2014-2023. xlsx is incomplete; the YAML's [1,7] reflects reality. Kept at [1,7] with caveat note. | `7021664` |
| 2026-05-12 | IPUS `uni_view` Frankenstein scale (2019 questionnaire restructure conflated with pre-2019) | Per-wave recode for 2019-2024 collapses post-2019 codes 1+2 → harmonized 1, shifts 3→2, 4→3, 5→4. Fixes wrong YAML label "Should not happen" (actual label = "not very interested in unification"). Preserves the post-2019 "not interested" group previously silently NA-coerced by valid_range [1,4]. IPUS L3 errors: 7 → 1. | `6b72f17` |
| 2026-05-12 | KINU codebook extractor incomplete vs .sav labels | Rebuilt from xlsx to .sav source (haven::read_sav). Captures cohort code 7 ("Z generation") and other previously-omitted codes. F4 valid_range fails for KINU: 26 → 0. | `bfd2062` |
| 2026-07-31 | WVS `freedom_vs_equality` W2 code order | Explicit per-wave recode (1→1, 2→NA, 3→2); W2 Equality reads 8,787. **Standing re-run obligation** — kept at the top of this file, not archived. | see Standing warnings |
| 2026-07-31 | Five remaining out-of-range findings (abs `hh_generations`, afro `urban_rural`, afro `bribe_police`, arab-barometer `dem_feature_1st`) | Closed with fixes, not exemptions; 9,052 respondent-values recovered in total. Three deliberate bin-width seams recorded in `bin_width_exemptions.yml`. | see full record |
| 2026-08-06 | Four ABS direction bugs from the label-recon SKIP list (`govt_responds_people`, `access_identity_document`, `access_public_school`, `party_closeness`) | Specs fixed and ABS re-harmonized; correlations flipped as predicted. | see full record |
| 2026-08-06 | ABS label-reconciliation backlog — 18 errors to 0 | Seven variables triaged per wave against raw value labels; 8 of 373 columns changed, 113,945 rows unchanged. Per-wave pattern: three of eight were wrong in only some waves. | see full record |
| 2026-08-06 | Four ABS W6 COVID items inverted (`covid_govt_handling`, `covid_trust_govt_info`, `income_fairness`, `covid_livelihood_impact`) | `safe_4pt_none` → `safe_reverse_4pt`, W6 only; 4 of 373 columns changed. Paper 01b double-reversal hazard verified cleared 2026-08-08. | see full record |
| 2026-08-05 | ABS W6 label metadata dropped by our own merge — 192 skips | `build_abs_w6.R` re-attaches value labels after `bind_rows`; 156 columns restored, 61 skips → ok. **87 conflicting columns remain open** — see High priority. | see full record |
| 2026-08-08 | Convention-collision class — missing codes deleting valid responses | 13 specs fixed + 7 red flags raw-label-verified; ~2,476 respondent-values recovered, ABS recovers ~60k `dem_rating_*` 7–9. Guardrail `check_convention_collisions.R` wired into `run_all.R`. **Identity-waves-only blind spot remains open** — see High priority. | see full record |
| 2026-08-08 | ABS W5 6→4pt pole-merge — 18 W5 items with wider top/bottom bins | Native W5-only companions `<id>_w5_6pt` added; seam documented in `docs/surveys/abs.md` and CLAUDE.md. Paper 05 should switch its W5 analysis to the companions. | see full record |


---
## ✅ Resolved — full records

Detailed records of findings that have been fixed. Kept in full because several
document *why* a fix took the shape it did, and because the one-line trail table
above cannot hold that. Ordered newest first.

### ~~NEW 2026-07-22~~ **RESOLVED 2026-08-08**: ABS W5 6→4pt pole-merge class — 18 W5 items with structurally wider top/bottom bins (Check D)

**Fixed per the preferred remedy in the artefact memo.** All 18 items now
have native W5-only companion columns `<id>_w5_6pt` (1–6, `safe_reverse_6pt`,
higher = more trust; `econ_family_income_fair_w5_6pt` higher = fairer —
raw-label-verified against the W5 merge .sav). The seam is documented in
`docs/surveys/abs.md` ("W5 trust seam") and the CLAUDE.md gotchas; the
verbatim dictionary's 18 W5 `response_scale` rows now show the real 6-pt
card (plus 18 new companion rows); the 4-pt items are exempted in
`bin_width_exemptions.yml` with pointers. Rule: W5 LEVELS → companions;
cross-wave → 4-pt W4↔W6 bypassing W5; W4→W5/W5→W6 4-pt change scores are
artefactual. Paper 05 should switch its W5 analysis to the companions.
Original finding below for the record.
- **What:** ABS W5 fielded several batteries on 6-point bipolar scales, collapsed 6→4 by merging both poles (`safe_6pt_to_4pt` / `collapse_6pt_to_4pt_reverse`: native 6,5→4; 2,1→1). W5's top bin absorbs two native categories vs one in every other wave → W5 top-box shares/means mechanically inflated ~2.4–4.6× (verified for the trust battery, every country). Direction checks pass this legitimately; found via paper 05's bug report (`paper-bank-05_thailand_trust_collapse/claudedocs/ABS-W5-trust-harmonization-artefact.md`), now caught by the new bin-width parity check (Check D, `src/r/audit/04_bin_width_parity.R`).
- **Affected (all w5, signature `4:2|3:1|2:1|1:2`):** the 13 institutional-trust items (`trust_president/courts/national_government/political_parties/parliament/civil_service/military/police/local_government/election_commission/newspapers/ngos/television`), the 4 social-trust items (`trust_acquaintances/neighbors/relatives/strangers`), and `econ_family_income_fair`.
- **Deliberately NOT exempted** (decision 2026-07-22): stays red in `run_all` until the seam is fixed/documented. Preferred fix per the artefact memo: expose native W5 6-pt companion columns (`*_w5_6pt`), document the seam in CLAUDE.md gotchas + docs/surveys/abs.md, fix the verbatim dictionary's W5 `response_scale` rows (they wrongly show the harmonized 4-pt scale).
- **Downstream:** any use of ABS W5 trust *levels*, W4→W5 or W5→W6 change scores. W4↔W6 comparisons bypass the seam.

---

### NEW 2026-08-07: Convention-collision class — missing codes deleting valid responses (FIXED for 13 specs 2026-08-07; the 7 red flags raw-label-verified and RESOLVED 2026-08-08 — check now reads 0 errors / 11 exempt)

**The class.** `harmonize_variable()` applies the resolved missing codes to
RAW values before anything else. On `method: identity` waves the raw scale is
the harmonized scale, so any convention code inside `qc.valid_range` silently
converts real answers to NA — invisible to the range check (already NA) and
to the oob log (removed as "missing", never coerced). Same failure mode as
the AFRO `education_5cat` bug fixed 2026-07-09.

**Fixed 2026-08-07** (new per-scale conventions, all codebook-verified unless
noted; every repoint carries a `# FIX 2026-08-07` comment):
- **ABS** — 1–10 democracy/ladder items lost ratings 7/8/9 (`dem_rating_*`,
  8 vars in `democracy.yml`, staircase + `subjective_social_status` +
  `hh_size` + `religiosity_practice`); `problem_most_important` lost
  categories 7/8/9 (farming/famine/drought; w3 missing = 97/98/99, w4–w6 =
  997/998/999); six `action_*_w1` items lost code 9 = **"Never done"** — the
  entire non-participant group; `govt_anticorrupt_effort` lost raw W2 0
  ("doing this quite effectively") because the convention NA'd it **before**
  `recode_w2_anticorrupt` could map 0→1 (see `treat_as_na_keep0` +
  `qc.coverage_missing_codes_by_wave` there — the engine's
  missing-before-recode ordering is the general hazard).
- **KIPA** — the drafted fix (four 0–10 economic evaluations losing ratings
  8/9, ~19k values) was DROPPED at apply time 2026-08-08: `src/config/kipa/`
  was removed in 04c5320 as a never-wired false start, so there is no live
  spec to fix. If those specs are ever revived, the fix pattern is: 0–10
  items need `treat_as_na_0_10: [98, 99]`, not `treat_as_na: [8, 9, 98, 99]`
  (the original patch file was deleted after apply).
- **KINU** — `region`/`home_region` code 9 = **Gangwon** deleted in all 13
  waves; `employment` 9 = student; `income_manwon` 9/99 = real amounts;
  thirteen 0–10 NK items lost value 9 (.sav n/a = 99); four 0–100
  thermometers lost reading 99 (.sav n/a = 999).
- **Arab Barometer** — `dem_extent_country`/`dem_suitable_country` lost the
  0 anchor and 8/9. **Codebook caveat**: AB has no Tier-3 extract yet;
  98/99-as-missing is assumed. Verify when the AB codebooks land.

**Data rebuilt 2026-08-08 for ALL affected surveys.** ABS and KINU (whose
2026-08-07 spec fixes had never been re-harmonized) rebuilt and verified:
KINU recovers 406 Gangwon respondents (region 9, all 13 waves) + 829
students; ABS recovers ~60k `dem_rating_*` ratings of 7–9 (USA alone
33,248) and the `action_*_w1` non-participant group (11,674 on
`action_contact_party_w1`). The six drift-only surveys (wvs, lbs, afro,
kamos, ipus, klosa) rebuilt **byte-identical** — their staleness was
`recoding.R` hash drift only. Freshness: 16/16 FRESH.

**The 7 red flags — raw-label-verified and RESOLVED 2026-08-08** (verdicts
from the raw .sav value labels + observed counts; ~2,476 respondent-values
recovered; kgss, kipa_corruption and arab-barometer re-harmonized and
spot-checked against raw counts):
1. `kgss/religion_beliefs prayer_frequency` — **convention bug.** 8=once a
   week, 9=several times a week are REAL points on the 11-pt ISSP scale
   (missing there is -8/-1/88/98/99). Repointed → `treat_as_na_11pt`.
   Recovered 443 (2008: 77+118; 2018: 58+190).
2. `kgss/social_inequality ineq_fair_continuum` — **convention bug.** 8/9
   are literal points on the 1–10 INCMFAIR continuum (DK/refusal is 88,
   which sits OUTSIDE [1,10] — the spec note claiming otherwise was wrong).
   Repointed → `treat_as_na_10pt`. Recovered 683 (2011: 260+93; 2014:
   228+102).
3. `kipa_corruption/demographics education` — **valid_range over-claim.**
   Real ladders: 2004–09 1–4, 2010–21 1–6, 2022–23 1–5; 9=무응답; no real
   8/9 anywhere. Narrowed → [1, 6]. ⚠️ NEW FINDING while verifying, FIXED
   same day: the code frames were misaligned across eras — not just
   2022–23 (4=대졸, 5=대학원 read as 2010–21's 4=대학중퇴, 5=대졸) but
   also 2004–09 (3=대졸, 4=대학원 read as 3=전문대졸, 4=대학중퇴). All
   waves now recoded onto the 2010–21 native 6-cat frame via by_wave
   recodes (2004–09: 3→5, 4→6; 2022–23: 4→5, 5→6), verified cell-by-cell
   against raw counts. Two structural caveats remain, documented in the
   spec note: pre-2010 "대졸" includes 전문대졸 (harmonized 5 is broader
   there; 3/4 cannot occur), and 2022–23 dropped 대학중퇴 (4 cannot occur
   there).
4. `kipa_corruption/demographics income` — **both, wave-dependent.** 8 is a
   REAL top bracket in every wave 2008–23 (600만원+/700만원+; the shared
   convention deleted the entire top tail, 1,274 respondents) and 9 is a
   REAL bracket in 2022–23 (800~900만원, 76). But 9 = 무응답 in 2004–21
   raw labels. Fix: new `treat_as_na_income` (no 8/9) +
   `valid_range_by_wave` ([1,6]/[1,8]/[1,10] per bracket scheme) so the
   2004–21 무응답 9s are range-coerced to NA and declared via
   `coverage_missing_codes_by_wave` (only 6 exist, all w2007). Recovered
   1,350.
5. `arab-barometer/demographics education_level` — **valid_range
   over-claim.** All six waves top out at 7=MA and above; W2's 9=declined
   (n=26) is genuine missing. Narrowed → [1, 7]. This also settles the
   2026-08-07 "verify when AB codebooks land" caveat for this variable:
   the embedded .sav labels were checked directly.
6. + 7. `arab-barometer/meanings_of_democracy dem_feature_1st/2nd` —
   **neither: phantom codes.** 8/9 are unlabeled and unobserved (n=0) in
   both waves; real codes are 1–6 + W2's 10 (providing jobs) + W3's 7
   (Other); DK/refused are the 5-digit 99994–99999 markers. Repointed →
   `treat_as_na_features` (= shared convention minus 8/9), so junk 8/9
   would now surface in the oob log instead of silently vanishing.
   Recovered 0 by construction.

**Exempted with reasons** (see
`src/config/_audit/convention_collision_exemptions.yml`): all `age` top-code
collisions (ABS w2 labels 97–99 as DK/refuse — removing them would inject
refusals as ages), zero survey weights, ABS `religion` (range spans the
label space; narrowing it is the real fix, tracked here), IPUS
`nk_sk_relations` recode midpoints. Two side-notes captured in the
exemption reasons: ABS w1 codes real ages to 109 (top-coerced by the
[17, 99] range) and AFRO's 101 age code needs per-round provenance.

**Guardrail.** `src/r/audit/check_convention_collisions.R` — cross-cutting,
YAML-only, wired into `run_all.R` (runs under `make audit` and
`make audit-specs`/CI), exemptions file above, report at
`audit/reports/convention_collisions.csv`, fault-injection tests in
`test_convention_collisions.R`. **Known blind spot:** it audits identity
waves only; convention codes colliding with an `r_function`'s expected raw
input (the `govt_anticorrupt_effort` case) need a future fn-input-domain
check against the registry's `input_scale`.

### NEW 2026-08-05: four ABS W6 items inverted — the COVID `safe_4pt_none` battery
Found by sweeping W6-mapped variables against the country-file labels directly (bypassing the merge that was eating the metadata).

| variable | src | raw | declared | fn | empirical r vs `trust_national_government` |
|---|---|---|---|---|---|
| `covid_govt_handling` | q142 | 1=positive | 1=negative | `safe_4pt_none` | **−0.428** |
| `covid_trust_govt_info` | q141 | 1=positive | 1=negative | `safe_4pt_none` | **−0.410** |
| `income_fairness` | q163 | 1=positive | 1=negative | `safe_4pt_none` | **−0.230** |
| `covid_livelihood_impact` | q140 | 1=positive | 1=negative | `safe_4pt_none` | −0.072 (anchor inappropriate; label evidence stands) |

Control: the five `covid_restrict_*` items use `safe_reverse_3pt` and check out (`covid_restrict_lockdown` r = **+0.158**). So the defect is specific to the W6-only `safe_4pt_none` items, and it is the same class as `govt_responds_people` — declared labels written as if a reversal were applied, `fn` left at identity.

**`covid_trust_govt_info` was invisible to layer 3 even after the W6 label restore**, because q141 is one of the columns countries disagree on — see below. A label conflict was hiding a direction bug.

**⚠️ q141 carries a genuine cross-country code conflict.** Eleven countries code "This is not the government's responsibility" as **5** with 97="Do not understand"; **Taiwan uses 97** for that substantive option. With `valid_range: [1,4]` both are dropped, so 13 substantive responses (12 Taiwan + 1 Singapore) are deleted. Small in volume, but it is the same "substantive option treated as missing" class as the WVS `freedom_vs_equality` and KIPA bribery bugs — and it is why q141's labels could not be merged.

**⚠️ Paper 01b is compensating for this.** Its `17_sdb_inventory.R` declares `positive_pole = 4` for `covid_govt_handling` and `covid_trust_info`, and reports r = −.56..−.58 between `govt_responds_people` and `covid_govt_handling`. On the repo's harmonized data that pair is **+0.389** pre-fix (−0.389 post-fix), i.e. the opposite sign — consistent with 01b reversing the COVID items in its own pipeline. **If these four are fixed upstream, 01b will double-reverse**, exactly like the Class B papers after the `system_deserves_support` fix in June. Coordinate the paper-side change with the spec change.

**FIXED 2026-08-06** (`safe_4pt_none` -> `safe_reverse_4pt`, all four, W6-only). Re-harmonized and verified: exactly 4 of 373 columns changed, distributions mirrored, and every correlation against `trust_national_government` flipped sign (-0.428 -> +0.428, -0.410 -> +0.410, -0.230 -> +0.230) while the untouched control `covid_restrict_lockdown` held at +0.158. Strict reversal now reports `expected=-1 pearson=-1 ok` for all four. `covid_livelihood_impact` and `income_fairness` moved to `ok_match` in layer 3; `covid_govt_handling` and `covid_trust_govt_info` remain `skip` there, because q141/q142 are label-conflict columns the W6 merge still cannot reconcile — fixed in data, unverifiable by the checker.

~~⚠️ PAPER 01b MUST BE UPDATED BEFORE ITS NEXT RUN~~ — **ALREADY DONE (verified 2026-08-08)**: 01b's `00_data_preparation.R` removed the `5 - x` compensation when the upstream fix landed (its comments document the double-reversal hazard explicitly), and `17_sdb_inventory.R`'s `positive_pole = 4` declarations now match the corrected orientation. Remaining 01b action: plain re-run against the rebuilt `abs_harmonized.rds`, and push its unpushed commits.

~~**Still open:** `sm_express_political` (w6 q52b) is a fifth case with identical evidence~~ — **RESOLVED 2026-08-06**: fixed in the label-reconciliation backlog clear above (w6 default -> `safe_reverse_4pt`).

---

### ✅ CLEARED 2026-08-06: the ABS label-reconciliation backlog — 18 errors to 0

All seven variables triaged against their raw value labels, per wave, and fixed. Two distinct defects, not one:

**Identity where a reversal was needed** (raw runs opposite the declared labels):
| variable | waves | fix |
|---|---|---|
| `econ_family_income_fair_6pt` | w4 | `identity` -> `safe_reverse_6pt` |
| `gov_elections_real_choice` | all | -> `safe_reverse_4pt`; the w5 collapse mapping carried the same inversion and was flipped too (1:4,2:3,3:2,4:1,5:1) |
| `sat_president_govt` | w3-w6 | per-wave exceptions; **w1 was already correct** and left alone |
| `sm_express_political` | w6 | default -> `safe_reverse_4pt` |

**Reversal where identity was needed** (declared labels MATCH the raw, so reversing broke the match):
| variable | waves | fix |
|---|---|---|
| `govt_should_censor_ideas` | all six | `safe_reverse_4pt` -> `identity` |
| `no_accountability_between_elections` | w2-w6 | `safe_reverse_4pt` -> `identity` |
| `efficacy_ability_participate` | w1 only | w1 exception `identity`; w2-w6 reversal is correct |
| `demo_political_equality` | w1 only | w1 exception `identity`; same shape as above |

**Verified:** exactly 8 of 373 columns changed, 113,945 rows unchanged, strict reversal 562/562 ok, and every correlation against the trust composite flipped as predicted — `sat_president_govt` -0.54 to **+0.54** (w3) and -0.56 to **+0.56** (w6), `gov_elections_real_choice` -0.28 to **+0.28**, `no_accountability_between_elections` -0.11 to **+0.11**. ABS `run_all` fails 84 -> 66 (the residue is bin-width 56 + anchor 7 + invariants 3, none of them direction).

**Note the per-wave pattern.** Three of the eight were wrong in only *some* waves — ABS flipped the raw coding of these items between waves, exactly as it did for `party_closeness`. A blanket fix would have broken the waves that were already right. Any future direction fix must check per wave before touching the default.

---

### ~~NEW 2026-08-04~~ **RESOLVED 2026-08-06**: four ABS direction bugs found via the label-recon SKIP list — specs fixed AND re-harmonized

*(Heading corrected 2026-08-09: it read "RE-HARMONIZE PENDING" long after the re-harmonize landed on 2026-08-06, per the entry's own final bullet. Left stale, it invites someone to redo finished work.)*
- **`govt_responds_people` (all waves).** Raw is 1=Very responsive → 4=Not responsive at all in every wave, i.e. opposite the spec's own labels, and `fn` was `safe_4pt_none` (identity). The item was stored backwards against its labels and against every other ABS attitude battery. Found empirically by **paper 01b** (r = −.56..−.58 against `covid_govt_handling`, `covid_trust_info`, `institutional_trust_index`, `dem_satisfaction`, in all three countries). Fixed → `safe_reverse_4pt`.
- **`access_identity_document`, `access_public_school` (W4-only).** Raw labels byte-identical to the declared labels (1=Very difficult → 4=Very easy) yet `fn: safe_reverse_4pt`. Their sibling `access_healthcare` had the correct per-wave treatment (`identity` for W2–W4, reverse for W5/W6), so the battery was right for one variable and wrong for these two. Fixed → `method: identity`.
- **`party_closeness` (w1, w2) — the worst of the four.** ABS flipped the raw order mid-series: w1/w2 are 1=Just a little close → 3=Very close (ascending), w3–w5 are 1=Very close → 3=Just a little close (descending). One `safe_reverse_3pt` was applied to all, so **w1/w2 are stored inverted against w3–w5** and any cross-wave trend on party closeness reads a spurious flip at the w2→w3 seam. Fixed via per-wave `exceptions:` (identity for w1/w2). **w6 RESOLVED 2026-08-05:** all twelve W6 country `.sav` files label q55 as 1=Very close → 3=Just a little close, i.e. descending like w3–w5, so the reversing default is correct for w6 and it needs no exception.
- ~~⚠️ ALL FOUR ARE SPEC-ONLY SO FAR~~ — **RESOLVED: ABS re-harmonized 2026-08-06** (the backlog-clear verification below counted these columns among the 8-of-373 changed and the correlations flipped as predicted). Freshness reports ABS FRESH as of the 2026-08-08 rebuild.

### ✅ Resolved 2026-07-31 — the other five out-of-range findings

Closed with real fixes, not exemptions; 9,052 respondent-values recovered in total (incl. the WVS 8,787). Three deliberately created bin-width seams, each recorded with a reason in `src/config/_audit/bin_width_exemptions.yml`:

- **abs `hh_generations` w6** — Japan-only `10 = "Single"` (107) was deleted; folded into 1 ("One generation").
- **afro `urban_rural` w6/w7** — `460 = "Peri-Urban"` (128) was deleted; folded into 3 ("Semi-Urban"). Same leak as the code-3 bug fixed 2026-05-14, one code further out.
- **afro `bribe_police` w2** — Mozambique-only `4 = "Always"` (30) was deleted; folded into 3 ("Often"). ⚠️ The only one of the five that loses real resolution: R2 Mozambique's top box is now wider than other rounds'. Revisit if a paper leans on that cell.
- **arab-barometer `dem_feature_1st` w2** — 52 country-specific extension codes now declared as intentional drops, matching the twin `dem_feature_2nd`, which had carried the declaration alone.

---

### NEW 2026-08-05: ABS W6 label metadata is dropped by our own merge — 192 skips, the layer's biggest blind spot
- **What:** `04_label_reconciliation.R` reads ABS labels from `data/processed/w{n}.rds`. For w6 that file retains value labels on **0 of 488 columns**, so every W6 variable reports `too_few_labels` and is never direction-checked.
- **It is not an ABS limitation.** All twelve W6 country files (`data/abs/raw/wave6/*.sav`) carry complete value labels — verified variable-by-variable for q55 across all 12. Our merge step drops them.
- **Scale:** 221 `too_few_labels` skips, **192 in w6**, 193 distinct variables. W6 is effectively unverifiable for direction today.
- **Why it matters now:** this is exactly how `govt_responds_people` w6 stayed unverified — I had to confirm its orientation empirically (correlation against trust anchors) because the metadata the check needed was thrown away upstream.
- **FIXED 2026-08-05.** `src/scripts/build_abs_w6.R` now captures each country's value labels before the strip and re-attaches them after `bind_rows` — the **attribute only**, never the `haven_labelled` class, so values and types are untouched (verified: 0 of 488 columns changed value, 0 changed type). Restored on 156 columns; 87 left unlabelled because countries disagree code-for-code (reported, not silently resolved — cf. the Thailand `REGION` 803/804 swap); 245 were never labelled.
- **Yield: 61 skips → `ok`, 7 skips → `error`.** ABS layer 3 went 326/18/789 to 387/25/721. Four of the new errors extend known backlog variables into W6 (`gov_elections_real_choice`, `govt_should_censor_ideas`, `no_accountability_between_elections`, `sat_president_govt`); **three are new and untriaged**: `covid_livelihood_impact`, `income_fairness`, `sm_express_political`.
- **Still open:** the 87 conflicting columns are unverifiable by construction until someone decides how to reconcile country-specific label text. That is the next tranche of this same gap.

**Why nothing caught them.** Layer 3 classifies direction with a regex polarity lexicon; unknown vocabulary → `skip`. ABS layer 3 is **322 ok / 22 error / 789 skip**, with 281 skips for `no_classifiable_poles` across 140 variables. `docs/QA.md` states this blind spot correctly and warns that **`skip` is not a pass** — the failure is that nobody worked the skip list. Adding `responsive` + `well` families to the lexicon converted `govt_responds_people` from skip to error (18 → 22 ABS error rows); the other three were found by an exact-sequence rule that needs no vocabulary at all. Both are scoped in `docs/superpowers/specs/2026-08-04-qa-validation-design.md`.

**`docs/QA.md`'s "18 error rows / 7 variables" still holds.** The lexicon addition pushed ABS to 22 errors, then fixing `govt_responds_people` returned it to 18 (ok 322 → 326). The other three fixes are invisible to layer 3 — they are the exact-sequence class it cannot yet see — so they are corrected in the specs while still reporting `skip`.

---

### ✅ Resolved 2026-05-12 — the four medium-priority KINU/IPUS/AFRO items (was: Medium priority — real but minor)

### ~~NEW 2026-05-12: KINU codebook extractor should read from .sav labels~~ — **RESOLVED 2026-05-12**
- **Resolution:** Rebuilt `src/r/audit/extractors/kinu_codebook.R` to source from `data/kinu/raw/kinu_2014-2023_en.sav` via `haven::read_sav()`, mirroring the ABS pattern. Year column (1-13) maps to wave keys via `.KINU_YEAR_TO_WAVE`. Per (variable × wave) emits rows only where the variable has non-NA observations.
- **Outcome:** Cohort code 7 (Z generation) now captured. F4 valid_range fails for KINU dropped 26 → 0 (cohort + home_region both reconcile cleanly). Rows 17,230 → 16,900; unique variables 912 → 901; missing-code detection slightly more aggressive (.sav exposes more codes than xlsx).
- **Tradeoff documented:** question_text now comes from the .sav variable label (haven attr) which may be terser than the xlsx's full question wording. Accepted for label accuracy.
- **Commit:** `bfd2062`.


> **All 4 medium-priority items investigated 2026-05-11.** Full evidence + recommended fixes in [`audit/findings_medium_2026-05-11.md`](audit/findings_medium_2026-05-11.md). Summary entries below — read the findings doc before editing.

### ~~KINU `cohort` valid_range over-claim~~ — **RESOLVED 2026-05-12 (different reason)**
- **What happened:** Investigation initially concluded code 7 was never observed (xlsx codebook only documents codes 1-6, and the codebook parquet F-KINU extracted matched). On the basis of that conclusion, narrowed `valid_range` from [1,7] to [1,6]. Re-running validation surfaced 12 NEW coverage errors (1-4% loss across waves). Checking the .sav directly revealed **the raw KINU .sav DOES have code 7 ("Z generation") with 290 cases across 2014-2023 (growing from 19 in 2014 to 41 in 2023)**. The xlsx codebook is incomplete relative to the .sav.
- **Resolution:** Reverted to [1, 7]. Added a CODEBOOK CAVEAT comment in the YAML documenting the xlsx-vs-.sav gap.
- **Meta-finding:** The KINU codebook extractor (which reads from xlsx) is incomplete relative to .sav labels. This affects F4 reconciliation quality for KINU. See new "KINU codebook extractor should read from .sav labels" entry below.
- **Commit:** _this commit_ — cohort kept at [1,7] after empirical verification against raw .sav.

### ~~KINU `home_region` valid_range over-claim~~ — **RESOLVED 2026-05-12**
- **What happened:** YAML claimed `valid_range: [1, 19]`. Raw `home` in .sav has only codes 1-18 (1-16 sido, 17=North Korea, 18=Foreign). Code 19 not declared in .sav labels, not observed in data.
- **Resolution:** Narrowed `valid_range` to [1, 18]. Removed `19: "..."` from scale.labels. Updated description.
- **Note:** KINU has TWO region coding schemes — demographics-region (used by `home` raw, 18 codes) and basic-region (used by `region` raw, 19 codes with Sejong=17 and NK=19). The two are NOT parallel despite identical-looking sido codes 1-16.
- **Commit:** _this commit_.

### ~~IPUS `uni_view` — Frankenstein scale across the 2019 questionnaire restructure~~ — **RESOLVED 2026-05-12**
- **What happened:** IPUS restructured response options in 2019, splitting "ASAP at any cost" (pre-2019 code 1) into two separate codes (1 = "at any cost", 2 = "ASAP"), pushing all subsequent codes down by one. The identity-method harmonization silently conflated the two schemes. Plus the YAML's `scale.labels.4 = "Should not happen"` was fabricated — no "opposed to unification" category exists in either scheme; the actual label is "not very interested in unification" (apathy).
- **Resolution:** Per-wave recode mappings for w2019-w2024 collapse codes 1+2 → harmonized 1 (treating the 2019 split as granularity within the "should happen" group rather than a new conceptual category) and shift 3→2, 4→3, 5→4. Pre-2019 waves (w2007-w2018) keep identity method. YAML labels corrected. Audit impact: IPUS L3 errors dropped 7 → 1 (the remaining 1 is `urban_rural w2008`, unrelated).
- **Substantive caveat documented in YAML:** the 1+2 collapse loses the post-2019 finer-grained distinction between "at any cost" and "ASAP". Researchers who need that distinction should consume raw `uni02_01` directly. Distribution sanity-check confirmed n_4 ("not very interested") is now properly preserved at 69-132 cases per wave post-2019 (previously silently NA-coerced by valid_range [1,4]).
- **Commit:** _this commit_.

### ~~AFRO `dem_satisfaction` W2 coverage loss~~ — **RESOLVED 2026-05-12**
- **Resolution:** Split off "Country is not a democracy" responses into a sister variable `dem_country_not_democracy` (binary) rather than just declaring them as missing. Preserves the substantive signal instead of hiding it.
- **What changed:**
  - New binary variable `dem_country_not_democracy` covers R1-R9 (R10 pending YAML mapping). Captures 4,898 respondents across all rounds who said their country is not a democracy (R1=436, R2=355, R3=391, R4=407, R5=965, R6=1054, R7=839, R8=849, R9=932). The R9 932-case group was a particularly important catch — previously silently NA-coerced by the engine's valid_range [1,4] under identity harmonization.
  - `dem_satisfaction` now declares `coverage_missing_codes_by_wave: [0]` for w2-w9, making the intent visible to the audit.
- **Audit impact:** AFRO L3 errors dropped 53 → 45. The 8 dem_satisfaction coverage errors are gone; new variable validates clean.
- **Commit:** (pending) — same commit that lands this update.


---
## How to use this file

When you investigate something here:
1. Move the entry from "open" to "Resolved findings" with the resolving commit hash.
2. If a new finding shows up, add to the appropriate priority bucket.
3. Don't delete entries — preserve the trail.

This file is intentionally NOT in `audit/`; it lives at the repo root so it's visible and harder to forget about.
