# LBS Variable Review: WVS Mapping Assessment

This document categorizes all WVS trust + democracy variables by their mappability to LBS (Latinobarometro).

**Waves**: w1=2015, w2=2016, w3=2018, w4=2020, w5=2023

---

## 1. Successfully Mapped Variables

### Institutional Trust (9 variables)
All mapped with `safe_reverse_4pt`. LBS raw: 1=A lot → 4=No trust. Target: 1=No trust → 4=A lot.

| Variable | WVS Equivalent | LBS Waves | Notes |
|---|---|---|---|
| trust_churches | trust_churches | All 5 | Direct match |
| trust_armed_forces | trust_armed_forces | All 5 | Direct match |
| trust_police | trust_police | All 5 | Direct match |
| trust_courts | trust_courts | All 5 | LBS says "Judiciary" vs WVS "courts" — same concept |
| trust_government | trust_government | All 5 | Direct match |
| trust_political_parties | trust_political_parties | All 5 | Direct match |
| trust_parliament | trust_parliament | All 5 | LBS says "National Congress/Parliament" |
| trust_elections | trust_elections | All 5 | LBS says "Electoral Institution" |
| trust_president | *LBS-specific* | w4-w5 | Not in WVS. Included as bonus variable. |

### Social Trust (1 variable)

| Variable | WVS Equivalent | LBS Waves | Notes |
|---|---|---|---|
| trust_generalized_binary | trust_generalized_binary | All 5 | Identity mapping, same 1-2 coding as WVS |

### Democratic Attitudes (4 variables)

| Variable | WVS Equivalent | LBS Waves | Notes |
|---|---|---|---|
| dem_support_preferable | *Partial: dem_importance_democracy* | All 5 | 1-3 nominal, NOT 1-10 scale. See Scale Mismatch below. |
| dem_satisfaction | *Partial: dem_satisfaction_political_system* | All 5 | 1-4 ordinal, NOT 1-10 scale. See Scale Mismatch below. |
| dem_how_democratic_10pt | dem_how_democratic | w1-w2 | Comparable 1-10 scale but only 2 waves |
| dem_how_democratic_qual | *Related* | w3-w4 | 1-4 qualitative, not comparable to WVS 1-10 |
| dem_best_system | *No WVS equivalent* | All 5 | Churchill quote (agree/disagree). LBS-specific framing. |

### Democratic Support (3 variables)

| Variable | WVS Equivalent | LBS Waves | Notes |
|---|---|---|---|
| dem_nondem_ok | *Partial: dem_strong_leader* | w2, w4-w5 | Agree/disagree vs WVS good/bad. See Questionable Mapping. |
| dem_military_support | *Partial: dem_army_rule* | w4-w5 | Binary vs WVS 1-4. See Scale Mismatch. |
| dem_solves_problems | *Partial: dem_democratic_system* | w4-w5 | Agree/disagree vs WVS good/bad framing. |

### Special Variable (1 variable)

| Variable | LBS Waves | Notes |
|---|---|---|
| pol_say_what_think | w1, w4-w5 | Pre-registered. Binary: 1=say what think, 2=do not. |

---

## 2. No LBS Equivalent (WVS variables with no match)

These WVS variables have no comparable item in any LBS wave:

### Institutional Trust
- **trust_press** — LBS asks about "Media" generally (2015), "Newspapers" separately (2015), but not comparable confidence item
- **trust_television** — 2015 has TV as part of a different battery; 2023 has TV in a "quality of life" battery
- **trust_labor_unions** — 2015 P19ST.A asks about labor unions but in a separate battery; 2018+ uses a different "quality of life" framing
- **trust_civil_service** — Not asked in LBS
- **trust_universities** — Not asked in LBS
- **trust_major_companies** — 2018+ asks about "National Companies" in quality-of-life framing, not comparable
- **trust_banks** — 2015 P19ST.G and 2018+ P16NC.F ask about banks in quality-of-life framing, not standard confidence battery
- **trust_environmental_orgs** — Not asked in LBS
- **trust_womens_orgs** — Not asked in LBS
- **trust_charitable_orgs** — Not asked in LBS
- **trust_united_nations** — 2016/2018 ask trust in UN but in a separate international organizations battery, not the main confidence battery

### Social Trust
- **trust_family** — Not asked in LBS
- **trust_neighborhood** — Not asked in LBS
- **trust_people_personally** — Not asked in LBS
- **trust_first_time** — Not asked in LBS
- **trust_another_religion** — Not asked in LBS
- **trust_another_nationality** — Not asked in LBS

### Democratic Support
- **dem_experts_rule** — Not asked in LBS
- **dem_religious_law** — Not asked in LBS

---

## 3. Scale Mismatch (Same concept, different scale)

| LBS Variable | WVS Variable | LBS Scale | WVS Scale | Issue |
|---|---|---|---|---|
| dem_support_preferable | dem_importance_democracy | 1-3 nominal | 1-10 ordinal | Different construct: LBS asks preference among 3 options; WVS asks importance on continuous scale |
| dem_satisfaction | dem_satisfaction_political_system | 1-4 ordinal | 1-10 ordinal | Same concept, narrower scale. Can compare within-survey but not cross-survey without rescaling |
| dem_how_democratic_qual | dem_how_democratic | 1-4 qualitative | 1-10 ordinal | Different framing entirely. Only w1-w2 use comparable 1-10 scale |
| dem_military_support | dem_army_rule | 1-2 binary | 1-4 ordinal | Binary support vs 4pt good/bad evaluation |

---

## 4. Questionable Mappings (Concept similar, wording differs)

### dem_nondem_ok ↔ WVS dem_strong_leader
- **WVS**: "Having a strong leader who does not have to bother with parliament and elections" — how good/bad? (1-4)
- **LBS**: "I wouldn't mind a non-democratic government in power if it could solve problems" — agree/disagree (1-4)
- **Issue**: WVS asks about a specific scenario (strong leader); LBS asks about any non-democratic government conditional on problem-solving. Related but distinct constructs.

### dem_solves_problems ↔ WVS dem_democratic_system
- **WVS**: "Having a democratic political system" — how good/bad? (1-4)
- **LBS**: "Democracy allows us to solve the problems we have" — agree/disagree (1-4)
- **Issue**: WVS evaluates democracy as a system type; LBS evaluates democracy's instrumental effectiveness. Both measure pro-democracy sentiment but from different angles.

### dem_best_system — No direct WVS equivalent
- **LBS**: "Democracy may have problems but it is the best system of government" — agree/disagree (1-4)
- **Note**: The WVS dem_importance_democracy (1-10) is the closest conceptual match, but the framing and scale are entirely different. This is a standard Churchillian democracy item used widely in comparative politics.

---

## 5. Partial Coverage (Available in some waves only)

| Variable | Missing Waves | Reason |
|---|---|---|
| trust_president | w1, w2, w3 | Only added to LBS battery in 2020 |
| dem_how_democratic_10pt | w3, w4, w5 | 2015-2016 use 1-10 scale; later waves switched to qualitative |
| dem_how_democratic_qual | w1, w2, w5 | 2018-2020 only; 2023 doesn't ask this |
| dem_nondem_ok | w1, w3 | Not in 2015 or 2018 |
| dem_military_support | w1, w2, w3 | Only in 2020-2023 |
| dem_solves_problems | w1, w2, w3 | Only in 2020-2023 |
| pol_say_what_think | w2, w3 | 2016 asks different question (free speech frequency, 1-5); 2018 not asked at all |

---

## 6. Variables Available in LBS But Not Mapped

These LBS items could be useful but don't correspond to any WVS target variable:

- **P25ST (2016)**: "Can you speak out and criticize freely in country" (1-5 frequency) — free expression item, but different from binary "say what think"
- **P14ST / P12ST / P10ST**: "Country governed by powerful groups vs for the good of all" — available most waves
- **P19ST (2016)**: "Firm hand is not a bad thing" — authoritarian attitudes item
- **P18STM (2016)**: "Support a government that passes over laws" — rule of law item
- **Democracy solves problems (2016 P44STMC)**: Earlier version available in 2016 too, could extend coverage

---

## Notes

- LBS uses **IDENPA** as country identifier (ISO 3166-1 numeric codes). The pipeline maps these to ISO alpha-3 for consistency with WVS.
- LBS missing value codes are consistent across waves: -1=Don't know, -2=No answer, -3=Not applicable, -4=Not asked, -5=DK/NA combined.
- The 2015 wave uses some non-standard codes (e.g., P29ST code 4 = "Not asked") which are handled by QC range checks.
