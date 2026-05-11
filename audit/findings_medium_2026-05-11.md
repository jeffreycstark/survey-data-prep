# Medium-priority audit findings — investigation report

Date: 2026-05-11
Investigates the four items from `JEFF_MUST_INVESTIGATE.md` 🟡 Medium-priority section.

**Summary of recommendations:**

| # | Item | Verdict | Suggested action |
|---|---|---|---|
| 1 | KINU `cohort` [1,7] | Stale claim. Code 7 never observed in any of 14 waves. | Narrow YAML `valid_range` to `[1, 6]` OR leave [1,7] and add a YAML note for future Z-generation. |
| 2 | KINU `home_region` [1,19] | Stale claim. Code 19 never observed; codebook tops out at 18=foreign. | Narrow YAML `valid_range` to `[1, 18]`. |
| 3 | IPUS `uni_view` valid_range | **Bigger than expected.** Not a range issue — a wave-mismatched-scale issue. 2019-2024 introduced a 5-cat scheme; identity harmonization silently conflates two different schemes. | Add a recode mapping to align 5-cat to 4-cat. Same shape as the `dem_extent_current` fix. |
| 4 | AFRO `dem_satisfaction` W2 coverage loss | **Not a bug — intentional**. The recode explicitly drops raw 0 ("Country is not a democracy") as NA. Audit flags it as loss because YAML doesn't declare the intent. | Add `qc.coverage_missing_codes: [0]` to silence the false-positive coverage warning. |

---

## Finding 1 — KINU `cohort` valid_range [1,7] vs codebook [1,6]

**Codebook evidence** (`data/kinu/codebook/kinu_codebook.parquet`, raw_var=`cohort`):

| Code | Label | Waves observed |
|---|---|---|
| 1 | war generation | all 14 (w2014-w2024 in 13 panel waves; 14 codebook rows) |
| 2 | industrial generation | all 14 |
| 3 | 386 generation | all 14 |
| 4 | X generation | all 14 |
| 5 | IMF generation | all 14 |
| 6 | Millenials *(codebook typo for "Millennials")* | all 14 |
| 7 | — | **never observed** |

Code 7 was never observed and is not declared in the codebook. The YAML's `valid_range: [1, 7]` is purely anticipatory (presumably waiting for KINU to add a "Z generation" code in future waves).

**Side observation:** F4 already flagged the codebook's spelling "Millenials" — codebook typo, not a YAML bug.

**Recommendation.** Two options, your call:

- **Strict / observed-only:** narrow to `valid_range: [1, 6]`. F4 valid_range fail disappears. Re-narrow if KINU adds a 7th category later.
- **Anticipatory / kept:** leave as `[1, 7]` but add a YAML note "code 7 reserved for Z generation if KINU adds it; not observed through 2024". The F4 audit fail can be silenced with `qc.coverage_missing_codes: []` (already does nothing) OR `qc.skip_level_preservation: true`.

I lean toward **strict** — the principle "self-contained and explicit" you set for missing-conventions arguably extends to range claims. Anticipatory claims hide intent; you can widen the range when the data actually shows up.

---

## Finding 2 — KINU `home_region` valid_range [1,19] vs codebook [1,18]

**Codebook evidence** (raw_var=`home`):

```
1  Seoul         10 Chungbuk        17 North Korea
2  Busan         11 Chungnam        18 foreign
3  Daegu         12 Jeonbuk         19 — never observed
4  Incheon       13 Jeonnam
5  Gwangju       14 Gyeongbuk
6  Daejeon       15 Gyeongnam
7  Ulsan         16 Jeju
8  Gyeonggi
9  Gangwon
```

18 codes total: 1-16 Korean sido, 17 = North Korea, 18 = foreign. **No code 19 anywhere in the codebook.**

**Recommendation.** Narrow `valid_range` to `[1, 18]`. Simple stale-claim fix. No substantive ambiguity (unlike cohort, where "Z generation" is a plausible future code; here, code 19 has no obvious semantic candidate).

---

## Finding 3 — IPUS `uni_view` is a Frankenstein (much bigger than the F4 finding suggested)

**F4 originally reported:** "code 4 absent from 12 waves." That was misleading.

**Codebook reality** (raw `a13` for 2007/2009/2010, `b07` for 2008, `uni02` for 2011-2018, `uni02_01` for 2019-2024):

### 2007-2018 — 4-category scheme

| Code | Korean label | English gloss |
|---|---|---|
| 1 | 어떠한 대가를 치르더라도 가능한 한 빨리 통일되는 것이 좋다 | Unify ASAP at any cost |
| 2 | 통일을 서두르기보다 여건이 성숙되기를 기다려야 한다 | Wait for conditions to mature |
| 3 | 현재대로가 좋다 | Status quo is fine |
| 4 | 통일에 대한 관심이 별로 없다 | Not very interested in unification |

### 2019-2024 — **5-category scheme** (category restructure)

| Code | Korean label | English gloss |
|---|---|---|
| 1 | 어떠한 대가를 치르더라도 통일되는 것이 좋다 | Unify at any cost |
| 2 | 가능한 빨리 통일되는 것이 좋다 | Unify ASAP |
| 3 | 여건이 성숙되기를 기다려 점진적으로 통일되는 것이 좋다 | Wait for conditions, gradual |
| 4 | 현재대로가 좋다 | Status quo is fine |
| 5 | 통일에 대한 관심이 별로 없다 | Not very interested |

**What happened in 2019:** the "ASAP at any cost" category (previously code 1) was **split into two** ("at any cost" + "ASAP"), pushing all subsequent categories down by one. So:

- pre-2019 code 1 ≈ post-2019 codes 1+2 (collapsed)
- pre-2019 code 2 ≈ post-2019 code 3
- pre-2019 code 3 ≈ post-2019 code 4
- pre-2019 code 4 ≈ post-2019 code 5

**The YAML's current state** (`unification.yml` lines 83-122):

```yaml
- id: uni_view
  type: categorical
  scale:
    labels:
      1: "Should happen as soon as possible"
      2: "Should wait for conditions to mature"
      3: "Status quo is fine"
      4: "Should not happen"
  harmonize:
    default:
      method: identity
  qc:
    valid_range: [1, 4]
```

**Three issues** the audit + this investigation surface:

1. **Identity-method silently conflates two schemes.** Pre-2019 code 4 ("not very interested in unification") and post-2019 code 4 ("status quo is fine") are different categories. Anyone using this variable cross-wave is operating on label-incompatible data.

2. **Post-2019 code 5 is silently dropped.** The valid_range [1,4] coerces the entire "not very interested" group to NA — same shape as the IPUS `uni_timing` bug from commit `b6b315e`. Coverage loss for that group is real, just smaller (~5-15% of late-wave respondents based on typical distributions).

3. **The YAML's labels don't match either codebook reality.** Label 4 = "Should not happen" doesn't appear in either scheme. The closest pre-2019 is "not very interested" (apathy, not opposition); the closest post-2019 is also "not very interested" (now code 5). There is no "should not happen" / "opposed to unification" category in IPUS uni_view.

**Recommendation.** Same shape as the `dem_extent_current` fix (commit `66d1ed8`) and the `uni_timing` fix (`b6b315e`): make this an explicit recode that aligns to a single harmonized scale.

```yaml
harmonize:
  default:
    method: identity   # 2007-2018: already 1-4, passes through
  exceptions:
    w2019: { method: recode, mapping: {1: 1, 2: 1, 3: 2, 4: 3, 5: 4} }   # collapse 1+2 → 1
    w2020: { method: recode, mapping: {1: 1, 2: 1, 3: 2, 4: 3, 5: 4} }
    w2021: { method: recode, mapping: {1: 1, 2: 1, 3: 2, 4: 3, 5: 4} }
    w2022: { method: recode, mapping: {1: 1, 2: 1, 3: 2, 4: 3, 5: 4} }
    w2023: { method: recode, mapping: {1: 1, 2: 1, 3: 2, 4: 3, 5: 4} }
    w2024: { method: recode, mapping: {1: 1, 2: 1, 3: 2, 4: 3, 5: 4} }
```

Then update `scale.labels` to:
- 1: "Should happen (any pace)"
- 2: "Wait for conditions to mature"
- 3: "Status quo is fine"
- 4: "Not very interested in unification"

(Note: NOT "Should not happen". IPUS has no "opposed to unification" category — that's a YAML interpretation error worth correcting.)

**Caveat — substantive interpretation question:** the 2007-2018 code 1 ("at any cost ASAP") combines "unify at any cost" + "ASAP" into one option. The 2019-2024 codes 1+2 split them. Collapsing 1+2 back to harmonized 1 ASSUMES respondents who chose "at any cost" in pre-2019 would have chosen either "at any cost" or "ASAP" (codes 1 or 2) in post-2019 — i.e., the split is purely about giving more granularity to the "should happen" group, not about creating a new conceptual category. That's the most plausible interpretation but worth your judgment before implementing.

---

## Finding 4 — AFRO `dem_satisfaction` W2 coverage loss

**Codebook evidence** (`data/afro/raw/round2/merged_r2_data.sav`, q40):

| Raw code | Label | Count |
|---|---|---|
| -1 | Missing | 26 |
| **0** | **Country is not a democracy** | **355** |
| 1 | Not at all satisfied | 3,539 |
| 2 | Not very satisfied | 5,274 |
| 3 | Fairly satisfied | 8,995 |
| 4 | Very satisfied | 3,842 |
| 9 | Don't Know | 2,269 |
| 98 | Refused | 1 |

n_total = 24,301

**The recode function** (`src/r/utils/recoding.R:recode_afro_dem_sat`):

```r
recode_afro_dem_sat <- function(x, ...) {
  missing_codes <- c(-1, 0, 8, 9, 98, 99, 998, 999)
  ...
  case_when(
    x %in% missing_codes ~ NA_real_,    # 0 explicitly listed
    x %in% 1:4 ~ x,
    TRUE ~ NA_real_
  )
}
#' 0 is treated as missing because it means "country is not a democracy"
```

**Verdict.** The 1.6% coverage loss is **intentional**, not a bug. The 355 R2 respondents who said "my country is not a democracy" are deliberately dropped — the assumption being that satisfaction-with-democracy is undefined if the respondent doesn't perceive their country as democratic.

**Why the audit flags it.** F4's coverage check counts (raw_valid − harmonized_valid). It doesn't know that the YAML/recode intends to drop the 355 cases. The YAML's `missing_conventions.treat_as_na.codes` doesn't include 0 (because 0 ISN'T treated as missing for other variables — it would be wrong to declare it globally), and there's no per-variable `qc.coverage_missing_codes: [0]` to declare the intent.

**Recommendation.** Add the declaration so the audit becomes accurate:

```yaml
- id: dem_satisfaction
  ...
  qc:
    valid_range: [1, 4]
    coverage_missing_codes: [0]    # ← add this
    coverage_missing_codes_by_wave:
      w2: [0]
      w3: [0]
      w4: [0]
      w5: [0]
      w6: [0]
      w7: [0]
      w8: [0]
      # w9 doesn't use recode_afro_dem_sat (identity); 0 may behave differently
```

(Validate against R9 separately — different recode applies there.)

After this, F4's coverage check for AFRO dem_satisfaction should report `ok` and the "1.6% loss" warning goes away.

**Substantive flag for your judgment:** the question "what does 'satisfied with democracy' mean for someone who says 'my country is not a democracy'?" is genuinely contested in the comparative-democracy literature. The current treat-as-NA approach is one defensible choice; others would map 0 → 1 (lowest satisfaction) or treat the 0 group as a separate binary "no_democracy" variable. Worth a comment in the YAML explaining the choice — it's not obviously right, just consistent.

---

## What this report does NOT do

- **No YAML edits.** This is investigation only. Apply the fixes via the README's Section A runbook when you're ready.
- **No re-extraction of codebooks.** All findings used the existing `data/<survey>/codebook/*.parquet` artifacts plus one direct read of `data/afro/raw/round2/merged_r2_data.sav` for the AFRO recode confirmation.
- **No anchor file updates.** None of these findings affect anchor signs.

## Next steps

When you tackle these:
1. Apply YAML edits per recommendations above.
2. Re-run the affected survey's pipeline (Section A of README).
3. Re-run audit: `Rscript src/r/audit/run_all.R --survey <survey>` to verify the F4 / E2 errors are resolved.
4. Move each entry in `JEFF_MUST_INVESTIGATE.md` from "open" to "Resolved findings" with the resolving commit hash.
