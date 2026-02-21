# Cambodia Prospecting Memo
## ABS Waves 2, 3, 4, 6 (2008, 2012, 2015, 2021)
## N: ~1,000–1,242 respondents per wave

---

## Context

Cambodia is a dominant-party authoritarian state (CPP under Hun Sen, now Hun Manet).
The four waves span a remarkable political arc:
- **W2 (2008)**: Consolidating CPP dominance post-reconstruction
- **W3 (2012)**: Pre-2013 election — opposition CNRP's strongest period; urban youth mobilization
- **W4 (2015)**: Post-2013 election disputes settled; CNRP officially recognized but under pressure
- **W6 (2021)**: Post-CNRP dissolution (2017); COVID-19 period; one-party legislature; deep CPP control

---

## Core Finding: Demobilization + Regime Normalization

The dominant story is **not** growing authoritarian enthusiasm — it's a population that has
withdrawn from politics, stopped contacting leaders, and increasingly accepts the existing
order as normal. At the same time, formal electoral participation has *risen*.

---

## The Five Major Threads

### 1. Political Action: Collapse (W3→W6)

All contentious political action measures fall sharply after W3:

| Variable | W2 | W3 | W4 | W6 |
|---|---|---|---|---|
| action_demonstration | — | 4.48 | 3.07 | **1.29** |
| action_petition | — | 4.34 | 3.23 | **2.14** |
| action_contact_elected | 3.44 | 4.31 | 3.08 | **1.74** |
| action_contact_civil_servant | 3.43 | 4.33 | 3.19 | **2.47** |
| community_leader_contact | 1.53 | 1.90 | 2.00 | **1.39** |

Scale: 1=never, 5=often. W3 peak coincides with CNRP's rise and 2013 pre-election mobilization.
W6 collapse follows CNRP dissolution (2017). This is among the steepest participation declines
in the ABS dataset.

**But voted_last_election rises: W3=0.787 → W4=0.832 → W6=0.881.**
Elections without opposition → turnout paradoxically rises. Classic demobilization signature.

---

### 2. Authoritarian Support: Rising, Especially W4→W6

| Variable | W2 | W3 | W4 | W6 |
|---|---|---|---|---|
| expert_rule | — | 1.58 | 1.66 | **2.11** |
| single_party_rule | 1.79 | 1.97 | 1.78 | **2.21** |
| strongman_rule | 1.60 | 1.73 | 1.76 | **2.17** |
| military_rule | 2.19 | 2.19 | 1.98 | **2.21** |

Scale: 1=very bad, 4=very good. All four rise sharply in W6 (2021).
The jump is concentrated between W4 (2015) and W6 (2021) — after the CNRP dissolution
removed any credible democratic alternative. This reads as normalization, not enthusiasm.

Group coherence: DIVERGENT overall (military_rule diverges slightly) but the W4→W6
jump is consistent across all four variables.

---

### 3. Democratic Future: Crashing Optimism

| Variable | W3 | W4 | W6 |
|---|---|---|---|
| dem_country_future (10pt) | **9.58** | 7.72 | 6.67 |
| dem_country_past (10pt) | 3.97 | 3.87 | **4.78** |
| dem_country_present_govt (10pt) | 5.85 | 5.06 | **5.77** |

W3 (2012): Cambodians rated the democratic future at 9.6/10 — extraordinarily optimistic,
possibly reflecting pre-election hope. By W6 it has fallen to 6.7.
Meanwhile, ratings of the democratic *past* have actually risen — perhaps Cambodians
remember the Sihanouk or early post-UNTAC period more fondly as the present disappoints.

**This is the classic output legitimacy puzzle inverted**: future optimism collapses
as authoritarian acceptance rises. Under democracy theory this is a crisis; under
output legitimacy theory it may reflect learning that democracy was not coming.

---

### 4. Corruption: Sharp W3→W4 Rise, Then W6 Drop

| Variable | W2 | W3 | W4 | W6 |
|---|---|---|---|---|
| corrupt_witnessed (binary) | 0.277 | 0.494 | **0.628** | 0.149 |
| corrupt_national_govt (1-4, higher=more) | 2.86 | 2.67 | 2.90 | **2.33** |
| corrupt_local_govt | 2.56 | 2.47 | 2.56 | **2.36** |

Witnessed corruption peaked at W4 (2015) — 63% had personally witnessed corruption.
By W6 it crashed to 15%. Perception of government corruption at national level also fell.

Possible explanations:
- Hun Sen's anti-corruption campaigns (selective)
- Survey response conformity effect after CNRP dissolution — less safe to criticize
- Actual reduced exposure as consolidation reduced elite competition

---

### 5. Media & Political Interest: Sustained Decline

| Variable | W3 | W4 | W6 |
|---|---|---|---|
| pol_news_follow | 3.07 | 2.86 | **2.04** |
| news_internet | 5.78 | 2.17 | 2.17 |
| political_interest | 2.57 | 2.29 | **2.06** |
| pol_discuss | 1.45 | 1.47 | **1.26** |

Internet news following collapsed W3→W4 (possibly measurement change between waves)
then held flat. Political interest and news following decline monotonically.

**news_internet W3 (5.78) vs W4 (2.17)**: Check YAML source mapping — this 
may reflect scale change or question wording shift, not a real-world change.

---

## Acceleration Reversals of Note

The 39 direction-reversals are analytically rich — many reflect the W3 peak:

| Variable | Early slope | Late slope | Story |
|---|---|---|---|
| trad_obey_parents | +0.98 | -0.28 | Peaked W3, fell back |
| trad_teacher_authority | +1.00 | -0.26 | Same pattern |
| gov_elections_real_choice | +1.00 | -0.20 | Peaked W3 pre-election |
| econ_family_now | +0.56 | -0.50 | Economic optimism reversed |
| dem_vs_econ | -1.00 | +0.12 | W3 strongly pro-democracy; swung back |
| govt_withholds_info | -0.53 | +0.47 | Less perceived secrecy W3→W4, more W6 |
| corrupt_witnessed | +0.45 | -0.50 | Corruption peak W4, collapse W6 |

The W3 (2012) wave looks like a high-watermark of civic engagement and democratic
aspiration across many dimensions simultaneously — consistent with the CNRP mobilization.

---

## China: Slowly Going Good

| Variable | W4 | W6 |
|---|---|---|
| intl_china_asia_goodharm (1=much harm, 4=much good) | 2.69 | 2.88 |
| intl_future_influence_asia (W3–W6, rising) | 2.41 → 2.74 → **3.30** | |

Cambodians are more positive about Chinese influence than most ABS countries and growing
more so. Cambodia is China's closest ASEAN partner; the Belt and Road investment is visible
in infrastructure. The rising `intl_future_influence_asia` is striking — Cambodians
increasingly see Asian (implicitly Chinese) influence as the regional future.

---

## Potential Paper Angles

### A. "The Demobilization Sequence"
Theory: Opposition elimination → participation collapse → authoritarian normalization.
Cambodia as the sharpest case in the ABS dataset. Testable: does the W3 peak in
civic action predict the W6 acceptance trough? What mediates (fear? learning? preference)?

### B. "Crashing Democratic Futures"
dem_country_future is the steepest-falling variable. In W3 Cambodians were MORE optimistic
about their democratic future than virtually any other country in ABS. By W6 that optimism
had nearly halved. This is a story about how hope dies — and what replaces it.

### C. "Corruption Witnessed vs. Corruption Believed"
Corruption *witnessed* collapses W4→W6 even as government corruption *perceptions* remain
moderate. Does reduced exposure (demobilization reduces the need to bribe?) or fear of
self-incrimination in reporting explain the gap? CPP anti-corruption campaigns?

### D. "China Going Good"
Cambodia as an outlier in Southeast Asia on Chinese influence perceptions. The trend 
is positive and accelerating. A paired comparison with Vietnam or Philippines (where
China perceptions are deteriorating) could make this vivid.

### E. "Traditional Values and the W3 Anomaly"
trad_obey_parents and trad_teacher_authority peak in W3 and fall back — unusual,
since most countries show either monotonic trends or no pattern. Was W3 a moment of
conservative backlash mixed with the democratic surge? Or survey artifact?

---

## Data Caveats

- Only 4 waves, skipping W1 and W5 — gaps limit structural break detection power
- W6 (2021) was conducted during COVID-19 — mobility restrictions, surveyor access, and
  social desirability pressures all elevated
- W3 (2012) coincided with the CNRP's strongest moment; its results may be unusually
  high on civic engagement relative to the structural baseline
- news_internet W3→W4 drop looks like a scale/question change, needs verification
  against the original questionnaires

