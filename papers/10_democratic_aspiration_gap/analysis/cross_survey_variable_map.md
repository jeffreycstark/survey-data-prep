# Cross-Survey Variable Map
# Paper 10: Democratic Aspiration Gap
# Generated: 2026-03-06
#
# All variables pulled from harmonized YAML specs in src/config/{survey}/harmonize/
# Direction verified against raw data coding and harmonization functions.

## Authoritarian Alternatives / Strongman Preferences

| Survey | Variable | Description | High = | Scale | Waves |
|--------|----------|-------------|--------|-------|-------|
| ABS | `strongman_rule` | "Get rid of parliament and elections, have a strong leader decide" | More authoritarian | 1–4 | W1–W6 (W3 gap) |
| ABS | `expert_rule` | "Get rid of elections, have experts make decisions" | More authoritarian | 1–4 | W1, W3–W6 (W2 gap) |
| ABS | `military_rule` | "The army should come in to govern the country" | More authoritarian | 1–4 | W1–W6 |
| ABS | `single_party_rule` | "Only one party should be allowed" | More authoritarian | 1–4 | W1–W6 |
| LBS | `strongman_mano_dura` | "A firm hand from the government is not a bad thing" | Pro-strongman | 0/1 binary | 1995, 2004, 2016 |
| LBS | `dem_nondem_ok` | "Wouldn't mind a non-democratic government if it solved problems" | More agreement | 1–4 | 2016, 2020, 2023 |
| LBS | `dem_military_support` | "Would support a military government" | Support | 0/1 binary | 2020, 2023 |
| Afro | `reject_one_party` | "Disapprove of one-party rule" | **More rejection (pro-dem)** | 1–5 | R2–R9 |
| Afro | `reject_military_rule` | "Disapprove of military rule" | **More rejection (pro-dem)** | 1–5 | R2–R9 |
| Afro | `reject_one_man_rule` | "Disapprove of one-man rule" | **More rejection (pro-dem)** | 1–5 | R2–R9 |
| WVS | `dem_strong_leader` | "Having a strong leader who doesn't bother with parliament" | More support for strongman | 1–4 | W6–W7 |
| WVS | `dem_experts_rule` | "Having experts, not government, make decisions" | More support for technocracy | 1–4 | W6–W7 |
| WVS | `dem_army_rule` | "Having the army rule" | More support for military | 1–4 | W6–W7 |
| WVS | `dem_democratic_system` | "Having a democratic political system" | More support for democracy | 1–4 | W6–W7 |
| WVS | `dem_religious_law` | "System governed by religious law" | More support for theocracy | 1–4 | W7 only |

**POLARITY WARNING**: Afro `reject_*` items are REVERSED relative to ABS/WVS/LBS. Afro high = pro-democracy; ABS/WVS/LBS high = more authoritarian. Flip one side before cross-survey comparison.


## Institutional Trust

| Survey | Variable | Description | High = | Scale | Waves |
|--------|----------|-------------|--------|-------|-------|
| **ABS** | `trust_president` | Trust in president/PM | More trust | 1–4 | W2–W6 |
| ABS | `trust_parliament` | Trust in parliament | More trust | 1–4 | W1–W6 |
| ABS | `trust_courts` | Trust in courts | More trust | 1–4 | W1–W6 |
| ABS | `trust_political_parties` | Trust in political parties | More trust | 1–4 | W1–W6 |
| ABS | `trust_national_government` | Trust in national government | More trust | 1–4 | W1–W6 |
| ABS | `trust_local_government` | Trust in local government | More trust | 1–4 | W1–W6 |
| ABS | `trust_military` | Trust in military | More trust | 1–4 | W1–W6 |
| ABS | `trust_police` | Trust in police | More trust | 1–4 | W1–W6 |
| ABS | `trust_civil_service` | Trust in civil service | More trust | 1–4 | W1–W6 |
| ABS | `trust_election_commission` | Trust in election commission | More trust | 1–4 | W1–W6 |
| ABS | `trust_ngos` | Trust in NGOs | More trust | 1–4 | W1–W6 |
| ABS | `trust_newspapers` | Trust in newspapers | More trust | 1–4 | W1–W6 |
| ABS | `trust_television` | Trust in television | More trust | 1–4 | W1–W6 |
| **Afro** | `trust_president` | Trust in president | More trust | 1–4 | R1–R9 |
| Afro | `trust_parliament` | Trust in parliament | More trust | 1–4 | R1–R9 |
| Afro | `trust_courts` | Trust in courts | More trust | 1–4 | R2–R9 |
| Afro | `trust_elections` | Trust in electoral commission | More trust | 1–4 | R2–R9 |
| Afro | `trust_police` | Trust in police | More trust | 1–4 | R1–R9 |
| Afro | `trust_armed_forces` | Trust in armed forces | More trust | 1–4 | R2–R9 |
| Afro | `trust_political_parties` | Trust in political parties | More trust | 1–4 | R2–R9 |
| Afro | `trust_churches` | Trust in religious leaders | More trust | 1–4 | R2–R9 |
| Afro | `trust_traditional_leaders` | Trust in traditional leaders | More trust | 1–4 | R2, R4, R6–R9 |
| **LBS** | `trust_president` | Trust in president | More trust | 1–4 | 13 of 24 waves |
| LBS | `trust_parliament` | Trust in congress/parliament | More trust | 1–4 | 20 of 24 waves |
| LBS | `trust_courts` | Trust in judiciary | More trust | 1–4 | 18 of 24 waves |
| LBS | `trust_political_parties` | Trust in political parties | More trust | 1–4 | 20 of 24 waves |
| LBS | `trust_government` | Trust in government | More trust | 1–4 | 15 of 24 waves |
| LBS | `trust_elections` | Trust in electoral tribunal | More trust | 1–4 | 14 of 24 waves |
| LBS | `trust_police` | Trust in police | More trust | 1–4 | 17 of 24 waves |
| LBS | `trust_armed_forces` | Trust in armed forces | More trust | 1–4 | 20 of 24 waves |
| LBS | `trust_churches` | Trust in church | More trust | 1–4 | 20 of 24 waves |
| LBS | `trust_newspapers` | Trust in newspapers | More trust | 1–4 | 14 waves (gap 2016–2020) |
| LBS | `trust_television` | Trust in television | More trust | 1–4 | 16 waves (gap 2016–2020) |
| LBS | `trust_radio` | Trust in radio | More trust | 1–4 | 13 waves (gap 2016–2020) |
| **WVS** | `trust_churches` | Trust in churches | More trust | 1–4 | W6–W7 |
| WVS | `trust_armed_forces` | Trust in armed forces | More trust | 1–4 | W6–W7 |
| WVS | `trust_press` | Trust in press | More trust | 1–4 | W6–W7 |
| WVS | `trust_television` | Trust in television | More trust | 1–4 | W6–W7 |
| WVS | `trust_police` | Trust in police | More trust | 1–4 | W6–W7 |
| WVS | `trust_courts` | Trust in courts | More trust | 1–4 | W6–W7 |
| WVS | `trust_government` | Trust in government | More trust | 1–4 | W6–W7 |
| WVS | `trust_political_parties` | Trust in political parties | More trust | 1–4 | W6–W7 |
| WVS | `trust_parliament` | Trust in parliament | More trust | 1–4 | W6–W7 |
| WVS | `trust_elections` | Trust in elections | More trust | 1–4 | W7 only |
| WVS | `trust_civil_service` | Trust in civil service | More trust | 1–4 | W6–W7 |
| WVS | `trust_universities` | Trust in universities | More trust | 1–4 | W6–W7 |
| WVS | `trust_major_companies` | Trust in major companies | More trust | 1–4 | W6–W7 |
| WVS | `trust_banks` | Trust in banks | More trust | 1–4 | W6–W7 |
| WVS | `trust_environmental_orgs` | Trust in environmental orgs | More trust | 1–4 | W6–W7 |
| WVS | `trust_womens_orgs` | Trust in women's orgs | More trust | 1–4 | W6–W7 |
| WVS | `trust_charitable_orgs` | Trust in charitable orgs | More trust | 1–4 | W6–W7 |
| WVS | `trust_united_nations` | Trust in UN | More trust | 1–4 | W6–W7 |
| WVS | `trust_labor_unions` | Trust in labor unions | More trust | 1–4 | W6–W7 |

**ALL trust variables across ALL surveys: 1–4 scale, higher = more trust. No polarity conflicts.**

### Suggested Concept Groups for Executive vs. Intermediary Analysis

| Group | ABS | Afro | LBS |
|-------|-----|------|-----|
| **Executive** | `trust_president`, `trust_police`, `trust_military` | `trust_president`, `trust_police`, `trust_armed_forces` | `trust_president`, `trust_police`, `trust_armed_forces` |
| **Intermediary** | `trust_parliament`, `trust_political_parties`, `trust_courts`, `trust_election_commission` | `trust_parliament`, `trust_political_parties`, `trust_courts`, `trust_elections` | `trust_parliament`, `trust_political_parties`, `trust_courts`, `trust_elections` |
| **Civil society** | `trust_ngos`, `trust_newspapers`, `trust_television` | `trust_churches`, `trust_traditional_leaders` | `trust_churches`, `trust_newspapers`, `trust_television`, `trust_radio` |

Note: ABS `trust_president` missing from W1. Afro `trust_traditional_leaders` sparse (R2, R4, R6–R9).


## Democratic Attitudes

| Survey | Variable | Description | High = | Scale | Waves |
|--------|----------|-------------|--------|-------|-------|
| ABS | `dem_always_preferable` | "Democracy always preferable" vs alternatives | — | 1–3 nominal | W1–W6 |
| ABS | `dem_best_form` | "Democracy is best form of government" | More pro-democracy | 1–4 | W3–W6 |
| ABS | `democracy_satisfaction` | "How satisfied with democracy?" | More satisfied | 1–4 | W1–W6 |
| ABS | `dem_extent_current` | "How much of a democracy is our country?" | More democratic | 1–10 | W1–W6 |
| ABS | `dem_country_present_govt` | "Place our country under present government" | More democratic | 1–10 | W1–W6 |
| ABS | `dem_country_past` | "Place our country 10 years ago" | More democratic | 1–10 | W3–W6 |
| ABS | `dem_country_future` | "Place our country 10 years from now" | More democratic | 1–10 | W1, W3–W6 |
| ABS | `democracy_suitability` | "Democracy is suitable for our country" | More suitable | 1–10 | W1–W6 |
| ABS | `democracy_efficacy` | "Democracy can solve society's problems" | Capable | 0/1 binary | W1–W6 |
| ABS | `dem_vs_econ` | "Democracy vs economic development" | More pro-democracy | 1–5 | W1–W6 |
| Afro | `dem_support_preferable` | "Democracy always preferable" vs alternatives | — | 1–3 nominal | R1–R9 |
| Afro | `dem_satisfaction` | "Satisfaction with democracy" | More satisfied | 1–4 | R2–R9 |
| Afro | `dem_how_democratic_qual` | "How democratic is the country?" | More democratic | 1–4 | R2–R9 |
| LBS | `dem_always_preferable` | "Democracy always preferable" vs alternatives | — | 1–3 nominal | All 24 waves |
| LBS | `dem_satisfaction` | "Satisfaction with democracy" | More satisfied | 1–4 | 21 of 24 waves |
| LBS | `dem_best_system` | "Democracy is best system of government" | More pro-democracy | 1–4 | 8 of 24 waves |
| LBS | `dem_how_democratic_10pt` | "How democratic is the country?" | More democratic | 1–10 | 16 of 24 waves |
| LBS | `dem_solves_problems` | "Democracy allows us to solve problems" | More agreement | 1–4 | 2020, 2023 |
| WVS | `dem_importance_democracy` | "How important to live in a democracy?" | More important | 1–10 | W6–W7 |
| WVS | `dem_how_democratic` | "How democratically governed today?" | More democratic | 1–10 | W6–W7 |
| WVS | `dem_satisfaction_political_system` | "Satisfaction with political system" | More satisfied | 1–10 | W7 only |

**SCALE WARNING**: ABS/Afro/LBS satisfaction = 1–4; WVS satisfaction = 1–10. ABS/LBS "how democratic" = 1–10; Afro = 1–4 qualitative. Rescale before comparing.

**NOMINAL ITEMS**: `dem_always_preferable` (ABS), `dem_support_preferable` (Afro), `dem_always_preferable` (LBS) are all 1–3 nominal with the same coding: 1=Democracy preferable, 2=Authoritarian sometimes preferable, 3=Doesn't matter. Directly comparable.


## Economic Evaluations

| Survey | Variable | Description | High = | Scale | Waves |
|--------|----------|-------------|--------|-------|-------|
| ABS | `econ_national_now` | "Overall national economic condition today" | Better | 1–5 | W1–W6 |
| ABS | `econ_family_now` | "Family economic situation today" | Better | 1–5 | W1–W6 |
| Afro | `econ_national_current` | "Country's present economic condition" | Better | 1–5 | R2–R9 |
| Afro | `econ_living_conditions` | "Your present living conditions" | Better | 1–5 | R2–R9 |
| LBS | `econ_national_current` | "Current economic situation of the country" | Better | 1–5 | 22 of 24 waves |
| LBS | `econ_personal_current` | "Current personal/family economic situation" | Better | 1–5 | 18 of 24 waves |

**ALL economic evaluations: 1–5 scale, higher = better. No polarity conflicts. Directly comparable.**

**Variable name mapping**: ABS uses `econ_national_now` / `econ_family_now`; Afro/LBS use `econ_national_current` / `econ_living_conditions` or `econ_personal_current`. Same construct, different names.


## Corruption

| Survey | Variable | Description | High = | Scale | Waves |
|--------|----------|-------------|--------|-------|-------|
| ABS | `corrupt_local_govt` | "How widespread is corruption in local government?" | More corruption perceived | 1–4 | W1–W6 |
| ABS | `corrupt_national_govt` | "How widespread is corruption in national government?" | More corruption perceived | 1–4 | W1–W6 |
| Afro | `bribe_document` | "Pay bribe for document or permit" | More bribery experience | 0–3 | R2–R9 |
| Afro | `bribe_police` | "Pay bribe to avoid problem with police" | More bribery experience | 0–3 | R2–R9 |
| Afro | `bribe_school` | "Pay bribe for school placement" | More bribery experience | 0–3 | R2–R9 |
| Afro | `bribe_medical` | "Pay bribe for medical care" | More bribery experience | 0–3 | R2–R9 |
| Afro | `corruption_level` | "How much corruption is there?" | More corruption perceived | 1–5 | R2–R9 |
| LBS | `corruption_experience` | "Have you or family member been victim of corruption?" | Yes=1 / No=0 | 0/1 binary | 14 waves |
| LBS | `corruption_progress` | "Progress reducing corruption in state institutions" | More progress | 1–5 | 15 waves |

**CAUTION**: ABS measures corruption *perception* (1–4), Afro measures bribery *experience* (0–3), LBS has both binary experience and ordinal progress. Same direction (higher = more), but different constructs and scales.


## Social Trust

| Survey | Variable | Description | High = | Scale | Waves |
|--------|----------|-------------|--------|-------|-------|
| LBS | `trust_generalized_binary` | "Most people can be trusted" | More trusting | 1–2 | 21 of 24 waves |
| WVS | `trust_generalized_binary` | "Most people can be trusted" | More trusting | 1–2 | W6–W7 |
| WVS | `trust_family` | Trust in family | More trust | 1–4 | W6–W7 |
| WVS | `trust_neighborhood` | Trust in neighborhood | More trust | 1–4 | W6–W7 |
| WVS | `trust_people_personally` | Trust people known personally | More trust | 1–4 | W6–W7 |
| WVS | `trust_first_time` | Trust people met first time | More trust | 1–4 | W6–W7 |
| WVS | `trust_another_religion` | Trust people of another religion | More trust | 1–4 | W6–W7 |
| WVS | `trust_another_nationality` | Trust people of another nationality | More trust | 1–4 | W6–W7 |

Note: ABS and Afro do not have generalized social trust in the harmonized dataset.


## Demographics (available across surveys)

| Survey | Variable | Description | Scale | Waves |
|--------|----------|-------------|-------|-------|
| ABS | `age`, `gender`, `urban_rural`, `education_level` | Standard demographics | varies | W1–W6 |
| Afro | `age`, `education_level`, `urban_rural` | Standard demographics | varies | R1–R9 |
| LBS | (not yet harmonized) | — | — | — |
| WVS | `sex`, `age`, `education_level`, `income_scale` | Standard demographics | varies | W6–W7 |

Note: Afro `education_level` is 0–3 (R1 native, R2–R4 collapsed from 0–9, R5–R9 pre-condensed). ABS `education_level` scale varies by wave.


## Weights

| Survey | Variable | Raw source | Waves |
|--------|----------|-----------|-------|
| ABS | `weight` | varies by wave | W3–W6 |
| Afro | `weight` | withinwt_hh | R9 |
| LBS | `weight` | WT | all waves |
| WVS | `weight` | V258 (W6), W_WEIGHT (W7) | W6–W7 |
