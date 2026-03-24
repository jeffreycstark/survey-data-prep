# TASK: Split KIPA trust composite into trust and honesty sub-items

**Requested by**: paper-bank/papers/08b_sk_institutional_trust_asymmetry
**Priority**: Next pipeline run
**Date**: 2026-03-24

---

## What to do

The current `kipa_trust_harmonized.rds` exports a single composite trust score per institution (e.g., `trust_central_govt`, `trust_national_assembly`). That composite averages two distinct sub-batteries from the raw KIPA/KSIS data:

- **q35**: `기관별 신뢰 정도` — institutional trust/confidence level (performance dimension)
- **q36**: `기관별 청렴도` — institutional integrity/honesty (procedural dimension)

These need to be exported as **separate columns** in the harmonized output. The composite can be removed from the harmonized file — paper-specific composites should be constructed downstream in `paper-bank`.

---

## Raw variable mapping

Both batteries use the same institution suffix numbering:

| Suffix | Institution (Korean) | Institution (English) | Harmonized column stem |
|--------|--------------------|-----------------------|----------------------|
| 1 | 중앙정부 부처 | Central government | `central_govt` |
| 2 | 국회 | National Assembly | `national_assembly` |
| 3 | 법원 | Courts | `courts` |
| 4 | 검찰 | Prosecution | `prosecution` |
| 5 | 경찰 | Police | `police` |
| 6 | 지방자치단체 | Local government | `local_govt` |
| 7 | 공기업 | Public enterprises | `public_enterprises` |
| 8 | 군대 | Military | `military` |
| 9 | 노동조합단체 | Labor unions | `labor_unions` |
| 10 | 시민단체 | Civic organizations | `civic_orgs` |
| 11 | TV방송사 | TV broadcasters | `tv` |
| 12 | 신문사 | Newspapers | `newspapers` |
| 13 | 교육기관 | Education | `education` |
| 14 | 의료기관 | Medical | `medical` |
| 15 | 대기업 | Large corporations | `large_corps` |
| 16 | 종교기관 | Religious | `religious` |
| 17 | 금융기관 | Financial | `financial` |

---

## Output schema

Replace the current single `trust_*` columns with two columns per institution:

```
trust_central_govt      →  trust_central_govt       (from q35_1)
                            honesty_central_govt     (from q36_1)
trust_national_assembly →  trust_national_assembly   (from q35_2)
                            honesty_national_assembly (from q36_2)
... etc for all 17 institutions
```

Scale: All items are 1–4 (fully distrust/dishonest to fully trust/honest). No rescaling needed for years where both batteries exist.

---

## Year-by-year availability

| Year | Trust battery (q35) | Honesty battery (q36) | Notes |
|------|--------------------|-----------------------|-------|
| 2011 | Different naming (T13 series) | Not available | Trust items in T13_1 through T13_14 with different institution ordering. No honesty battery. Needs separate mapping. |
| 2013 | q35_1 through q35_6 (partial) | Not available | Only 6 institutions covered |
| 2014 | Not available | q36_1 through q36_12 (partial) | Only honesty, no trust |
| 2015 | q35_1 through q35_6 (partial) | q36_1 through q36_12 (partial) | Both present but partial coverage |
| 2016 | q35_1 through q35_9 (partial) | q36_1 through q36_7 (partial) | Both present but partial coverage |
| 2017 | q35_1 through q35_8 (partial) | q36_1 through q36_6 (partial) | Both present but partial coverage |
| 2018 | q35_1 through q35_17 (full) | q36_1 through q36_17 (full) | Full coverage both batteries |
| 2019 | q35_1 through q35_17 (full) | q36_1 through q36_17 (full) | Full coverage both batteries |
| 2020 | q35_1 through q35_9 (partial) | q36_1 through q36_10 (partial) | Both present but partial coverage |
| 2021 | q35_1 through q35_17 (full) | q36_1 through q36_17 (full) | Full coverage both batteries |
| 2022 | q35_1 through q35_17 (full) | q36_1 through q36_17 (full) | Full coverage both batteries |
| 2023 | q35_1 through q35_5 (partial) | q36_1 through q36_15 (partial) | Trust very partial; honesty more complete |
| 2024 | Different naming (q31 series) | Different construct (q36 = 공정한 업무수행 = fairness, not 청렴도) | Trust in q31_1 through q31_17. q36 changed meaning — do NOT map as honesty. |

**Recommendation**: For years where an item is not available, export as `NA`. Do not impute or composite. The downstream paper scripts handle missingness.

---

## Special cases

### 2011
Trust items are in T13_1 through T13_14 with a different institution ordering:
- T13_1 = 기업 (corporations), T13_2 = 금융기관, T13_3 = 종교단체, T13_4 = 시민단체, T13_5 = 노동조합, T13_6 = 언론, T13_7 = 교육기관, T13_8 = 의료기관, T13_9 = 정당, T13_10 = 중앙정부, T13_11 = 지방자치단체, T13_12 = 국회, T13_13 = 법원, T13_14 = 군대

Scale in 2011 is 1–5 (not 1–4). The current harmonization pipeline linearly rescales to 1–4. Continue that for trust items. No honesty battery exists for 2011.

### 2024
Trust items moved to q31_1 through q31_17 (same institution ordering as q35). Map these to `trust_*` columns.

The q36 battery in 2024 changed construct from 청렴도 (integrity/honesty) to 공정한 업무수행 (fairness of job performance). **Do not** map 2024 q36 to `honesty_*` columns — it's a different construct. Export `honesty_*` as `NA` for 2024.

---

## What to remove

Once the split columns are in place, **remove** the current composite `trust_*` columns that average trust + honesty. Any paper that needs a composite can construct it downstream. The current composites silently average two conceptually distinct dimensions, which masks the trust-honesty differential that is analytically meaningful for at least one paper (08b).

---

## Verification

After the pipeline runs, the 2021 wave should produce values matching Rich (2024):
- `trust_national_assembly` ≈ 2.18 (job performance)
- `honesty_national_assembly` ≈ 2.11 (honesty/integrity)
- `trust_central_govt` ≈ 2.55
- `honesty_central_govt` ≈ 2.49

If the split values don't match these approximately, check the item mapping.
