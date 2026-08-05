# Audit findings — open for review

Last updated: 2026-07-31

This file records audit findings that need substantive judgment from Jeff. The audit infrastructure surfaces; this file tracks what remains to investigate. Update as items get resolved.

---

## ⚠️ BREAKING DATA CHANGE 2026-07-31 — WVS `freedom_vs_equality` was wrong in W2, now fixed

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

## ✅ Resolved 2026-07-31 — the other five out-of-range findings

Closed with real fixes, not exemptions; 9,052 respondent-values recovered in total (incl. the WVS 8,787). Three deliberately created bin-width seams, each recorded with a reason in `src/config/_audit/bin_width_exemptions.yml`:

- **abs `hh_generations` w6** — Japan-only `10 = "Single"` (107) was deleted; folded into 1 ("One generation").
- **afro `urban_rural` w6/w7** — `460 = "Peri-Urban"` (128) was deleted; folded into 3 ("Semi-Urban"). Same leak as the code-3 bug fixed 2026-05-14, one code further out.
- **afro `bribe_police` w2** — Mozambique-only `4 = "Always"` (30) was deleted; folded into 3 ("Often"). ⚠️ The only one of the five that loses real resolution: R2 Mozambique's top box is now wider than other rounds'. Revisit if a paper leans on that cell.
- **arab-barometer `dem_feature_1st` w2** — 52 country-specific extension codes now declared as intentional drops, matching the twin `dem_feature_2nd`, which had carried the declaration alone.

---

## 🔴 High priority — likely real bugs

### NEW 2026-08-04: four ABS direction bugs found via the label-recon SKIP list — specs fixed, RE-HARMONIZE PENDING
- **`govt_responds_people` (all waves).** Raw is 1=Very responsive → 4=Not responsive at all in every wave, i.e. opposite the spec's own labels, and `fn` was `safe_4pt_none` (identity). The item was stored backwards against its labels and against every other ABS attitude battery. Found empirically by **paper 01b** (r = −.56..−.58 against `covid_govt_handling`, `covid_trust_info`, `institutional_trust_index`, `dem_satisfaction`, in all three countries). Fixed → `safe_reverse_4pt`.
- **`access_identity_document`, `access_public_school` (W4-only).** Raw labels byte-identical to the declared labels (1=Very difficult → 4=Very easy) yet `fn: safe_reverse_4pt`. Their sibling `access_healthcare` had the correct per-wave treatment (`identity` for W2–W4, reverse for W5/W6), so the battery was right for one variable and wrong for these two. Fixed → `method: identity`.
- **`party_closeness` (w1, w2) — the worst of the four.** ABS flipped the raw order mid-series: w1/w2 are 1=Just a little close → 3=Very close (ascending), w3–w5 are 1=Very close → 3=Just a little close (descending). One `safe_reverse_3pt` was applied to all, so **w1/w2 are stored inverted against w3–w5** and any cross-wave trend on party closeness reads a spurious flip at the w2→w3 seam. Fixed via per-wave `exceptions:` (identity for w1/w2). **w6 RESOLVED 2026-08-05:** all twelve W6 country `.sav` files label q55 as 1=Very close → 3=Just a little close, i.e. descending like w3–w5, so the reversing default is correct for w6 and it needs no exception.
- **⚠️ ALL FOUR ARE SPEC-ONLY SO FAR.** `abs_harmonized.rds` still holds the old values until ABS is re-harmonized. Freshness (layer 6d) should now report ABS STALE.

### NEW 2026-08-05: ABS W6 label metadata is dropped by our own merge — 192 skips, the layer's biggest blind spot
- **What:** `04_label_reconciliation.R` reads ABS labels from `data/processed/w{n}.rds`. For w6 that file retains value labels on **0 of 488 columns**, so every W6 variable reports `too_few_labels` and is never direction-checked.
- **It is not an ABS limitation.** All twelve W6 country files (`data/abs/raw/wave6/*.sav`) carry complete value labels — verified variable-by-variable for q55 across all 12. Our merge step drops them.
- **Scale:** 221 `too_few_labels` skips, **192 in w6**, 193 distinct variables. W6 is effectively unverifiable for direction today.
- **Why it matters now:** this is exactly how `govt_responds_people` w6 stayed unverified — I had to confirm its orientation empirically (correlation against trust anchors) because the metadata the check needed was thrown away upstream.
- **Fix:** preserve labels through the w6 merge (or have the loader read the country files directly, as the wvs/lbs loaders read their `.sav`). Highest-yield single change available to layer 3. `docs/QA.md` §3 previously misattributed this to ABS; corrected 2026-08-05.

**Why nothing caught them.** Layer 3 classifies direction with a regex polarity lexicon; unknown vocabulary → `skip`. ABS layer 3 is **322 ok / 22 error / 789 skip**, with 281 skips for `no_classifiable_poles` across 140 variables. `docs/QA.md` states this blind spot correctly and warns that **`skip` is not a pass** — the failure is that nobody worked the skip list. Adding `responsive` + `well` families to the lexicon converted `govt_responds_people` from skip to error (18 → 22 ABS error rows); the other three were found by an exact-sequence rule that needs no vocabulary at all. Both are scoped in `docs/superpowers/specs/2026-08-04-qa-validation-design.md`.

**`docs/QA.md`'s "18 error rows / 7 variables" still holds.** The lexicon addition pushed ABS to 22 errors, then fixing `govt_responds_people` returned it to 18 (ok 322 → 326). The other three fixes are invisible to layer 3 — they are the exact-sequence class it cannot yet see — so they are corrected in the specs while still reporting `skip`.

---


### NEW 2026-07-22: ABS W5 6→4pt pole-merge class — 18 W5 items with structurally wider top/bottom bins (Check D)
- **What:** ABS W5 fielded several batteries on 6-point bipolar scales, collapsed 6→4 by merging both poles (`safe_6pt_to_4pt` / `collapse_6pt_to_4pt_reverse`: native 6,5→4; 2,1→1). W5's top bin absorbs two native categories vs one in every other wave → W5 top-box shares/means mechanically inflated ~2.4–4.6× (verified for the trust battery, every country). Direction checks pass this legitimately; found via paper 05's bug report (`paper-bank-05_thailand_trust_collapse/claudedocs/ABS-W5-trust-harmonization-artefact.md`), now caught by the new bin-width parity check (Check D, `src/r/audit/04_bin_width_parity.R`).
- **Affected (all w5, signature `4:2|3:1|2:1|1:2`):** the 13 institutional-trust items (`trust_president/courts/national_government/political_parties/parliament/civil_service/military/police/local_government/election_commission/newspapers/ngos/television`), the 4 social-trust items (`trust_acquaintances/neighbors/relatives/strangers`), and `econ_family_income_fair`.
- **Deliberately NOT exempted** (decision 2026-07-22): stays red in `run_all` until the seam is fixed/documented. Preferred fix per the artefact memo: expose native W5 6-pt companion columns (`*_w5_6pt`), document the seam in CLAUDE.md gotchas + docs/surveys/abs.md, fix the verbatim dictionary's W5 `response_scale` rows (they wrongly show the harmonized 4-pt scale).
- **Downstream:** any use of ABS W5 trust *levels*, W4→W5 or W5→W6 change scores. W4↔W6 comparisons bypass the seam.

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

## 🟡 Medium priority — real but minor (review when convenient)

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

## How to use this file

When you investigate something here:
1. Move the entry from "open" to "Resolved findings" with the resolving commit hash.
2. If a new finding shows up, add to the appropriate priority bucket.
3. Don't delete entries — preserve the trail.

This file is intentionally NOT in `audit/`; it lives at the repo root so it's visible and harder to forget about.
