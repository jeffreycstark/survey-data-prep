# Party Identification Variable Cross-Wave Summary

**Question**: "Among the political parties listed here, which party if any do you feel closest to?"

---

## Variable Names by Wave

| Wave | Variable | Question Number |
|------|----------|-----------------|
| W2   | `q54`    | Q54             |
| W3   | `q47`    | Q47             |
| W4   | `q53`    | Q53             |
| W5   | `q56`    | Q56             |
| W6   | `q54` (`Q54` for Taiwan) | Q54 |

---

## Taiwan Party Codes and Names

| Code | W2 | W3 | W4 | W5 | W6 |
|------|----|----|----|----|----|
| 701 | KMT | KMT | KMT | Kuomintang (KMT) | Kuomintang (KMT) |
| 702 | DPP | DPP | DPP | Democratic Progressive Party (DPP) | Democratic Progressive Party (DPP) |
| 703 | New Party | New Party | New Party | New Party | New Party |
| 704 | PFP | People First Party | People First Party | People First Party | People First Party |
| 705 | TSU | Taiwan Solidarity Union | Taiwan Solidarity Union | Taiwan Solidarity Union | Taiwan Solidarity Union |
| 706 | Other | Other | Green Party | New Power Party | New Power Party |
| 707 | - | - | Civic Party | - | Taiwan People's Party (TPP) |
| 708 | - | - | - | - | Taiwan Radical Wings |
| 709 | - | - | - | - | Others |
| 799 | - | - | - | Others | - |

### Taiwan Party Coalitions
- **Pan-Blue (conservative)**: KMT (701), New Party (703), PFP (704)
- **Pan-Green (progressive)**: DPP (702), TSU (705), New Power Party (706 in W5-W6)
- **Neutral/Third Force**: Taiwan People's Party/TPP (707 in W6)

### Taiwan Harmonization Notes
- Codes 701-705 are **stable** across all waves
- Code 706 changes meaning: Other (W2-W3) → Green Party (W4) → New Power Party (W5-W6)
- Code 707 changes meaning: Civic Party (W4) → TPP (W6)
- **Recommended**: Create separate harmonized variable that tracks coalition membership

---

## South Korea Party Codes and Names

| Code | W2 | W3 | W4 | W5 | W6 |
|------|----|----|----|----|----|
| 301 | Uri Party (governing) | Uri Party (governing) | Saenuri Party | Democratic Party of Korea | Democratic Party |
| 302 | Grand National Party | Grand National Party | New Politics Alliance | Liberty Korea Party | People Power Party |
| 303 | Democratic Party | Democratic Party | Justice Party | BAREUNMARAE Party | Justice Party |
| 304 | Democratic Labor Party | Democratic Labor Party | - | Party for Democracy & Peace | - |
| 305 | People First Party | People First Party | - | Justice Party | - |
| 306 | Other Parties | Other Parties | - | ETC | - |
| 307 | - | Liberty Forward Party | - | - | - |
| 308 | - | Future hope solidarity | - | - | - |
| 309 | - | Creative Korea Party | - | - | - |
| 310 | - | New Progressive Party | - | - | - |
| 311 | - | People's Participation Party | - | - | - |

### South Korea Party Coalitions
**⚠️ CRITICAL: Codes are NOT stable - same codes refer to different parties**

- **Progressive lineage (code 301 changes)**:
  - W2-W3: Uri Party (progressive, governing)
  - W4: Saenuri Party (conservative!)
  - W5-W6: Democratic Party (progressive)

- **Conservative lineage (code 302 changes)**:
  - W2-W3: Grand National Party (conservative)
  - W4: New Politics Alliance for Democracy (progressive!)
  - W5: Liberty Korea Party (conservative)
  - W6: People Power Party (conservative)

- **Minor progressive**: Justice Party (303 in W4, W6; 305 in W5)

### South Korea Harmonization Notes
- **Codes 301-302 flip meaning between waves** - cannot use raw codes
- Must create ideology-based harmonized variable:
  - `party_ideology`: 1=Progressive, 2=Conservative, 3=Minor/Other
- Or party-lineage based variable tracking actual succession

---

## Thailand Party Codes and Names

| Code | W2 | W3 | W4 | W5 | W6 |
|------|----|----|----|----|----|
| 801 | Prajadhipat (Democrat) | Prajadhipat (Democrat) | Democrat Party | Democrat Party | Democrat Party |
| 802 | Thai Rak Thai | Thai Rak Thai | Pheu Thai Party | Pheu Thai Party | Pheu Thai Party |
| 803 | Chart Thai | Chart Thai | Phumjai Thai Party | Pracharat Party | Palang Pracharath Party |
| 804 | Mahachon | Mahachon | Chart Thai Pattana | Future Forward Party | Move Forward Party |
| 805 | Other Party | Other Party | Pheu Pandin Party | Bhumjaithai Party | Chartthaipattana Party |
| 806 | - | Pheu Thai | - | Puea Pandin Party | Thai Liberal Party |
| 807 | - | Bhumjai Thai | - | - | - |
| 808 | - | Chart Thai Pattana | - | - | - |
| 809 | - | Pua Paendin | - | - | - |
| 899 | - | - | - | Others | - |

### Thailand Party Coalitions
**⚠️ CRITICAL: Major party changes due to military coups and dissolutions**

- **Pro-Thaksin lineage (code 802 relatively stable)**:
  - Thai Rak Thai (W2-W3, dissolved 2007)
  - → People's Power Party (dissolved 2008, not in W3 codes)
  - → Pheu Thai Party (W4-W6)

- **Anti-Thaksin/Pro-Military**:
  - Democrat Party (801, stable name across waves)
  - Palang Pracharath/PPRP (803 in W5-W6, pro-military)

- **Progressive opposition (code 804 changes)**:
  - Mahachon (W2-W3)
  - Chart Thai Pattana (W4)
  - Future Forward Party (W5, dissolved 2020)
  - → Move Forward Party (W6)

### Thailand Harmonization Notes
- Code 801 (Democrat Party) is **stable**
- Code 802 (Pro-Thaksin) is **conceptually stable** despite name changes
- Code 803 changes meaning completely
- Code 804 changes meaning completely
- Must create coalition-based harmonized variable

---

## Key Harmonization Challenges

### 1. Party Code Instability
Same codes refer to **completely different parties** across waves:
- **Korea 301**: Uri Party (progressive) in W2-W3 → Saenuri (conservative) in W4 → Democratic Party (progressive) in W5-W6
- **Thailand 803**: Chart Thai (W2-W3) → Phumjai Thai (W4) → Pracharat/PPRP (W5-W6)

### 2. Party Succession/Dissolution
Parties dissolve (often by court order) and reform under new names:
- Thai Rak Thai → People's Power → Pheu Thai (all pro-Thaksin)
- Future Forward → Move Forward (progressive opposition in Thailand)
- Uri Party → various mergers → Democratic Party of Korea

### 3. Variable Name Changes
The question number shifts across waves, requiring different variable names:
- q54 → q47 → q53 → q56 → q54

### 4. Coalition Membership Determination
Need to match party ID to election results to determine:
- Ruling party vs opposition at time of survey
- Winner/loser status based on most recent election
- Coalition membership for multiparty systems

---

## Recommended Harmonization Approach

### Step 1: Extract raw party codes
Create unified variable `party_id_raw` with country-specific prefix preserved

### Step 2: Create party lineage mapping
Map each party code to its ideological/political lineage:

```yaml
taiwan_parties:
  pan_blue: [701, 703, 704]  # KMT, New Party, PFP
  pan_green: [702, 705, 706]  # DPP, TSU, New Power Party (W5-W6)
  neutral: [707]  # TPP (W6 only)

korea_parties:
  progressive:
    w2_w3: [301, 303, 304]  # Uri, Democratic, Democratic Labor
    w4: [302]  # New Politics Alliance
    w5: [301, 304, 305]  # Democratic Party, Party for Dem & Peace, Justice
    w6: [301, 303]  # Democratic Party, Justice Party
  conservative:
    w2_w3: [302]  # Grand National Party
    w4: [301]  # Saenuri
    w5: [302]  # Liberty Korea
    w6: [302]  # People Power Party

thailand_parties:
  pro_thaksin: [802]  # Pheu Thai lineage (stable code)
  anti_thaksin_establishment: [801]  # Democrat Party (stable code)
  pro_military:
    w5: [803]  # Pracharat
    w6: [803]  # Palang Pracharath
  progressive_opposition:
    w5: [804]  # Future Forward
    w6: [804]  # Move Forward
```

### Step 3: Create harmonized coalition variable
`party_coalition`: 1=Progressive/Pan-Green/Pro-Thaksin, 2=Conservative/Pan-Blue/Anti-Thaksin, 3=Neutral/Minor

### Step 4: Match to election results
Use `election_results_abs_waves.rds` to determine:
- `party_won_election`: Did respondent's party win most recent election?
- `party_in_government`: Is respondent's party currently in ruling coalition?

---

## Files Created

- `party_id_crosswalk.md` - This documentation file
- `election_results_abs_waves.rds` - Election results for matching (created earlier)
- `election_results_abs_waves.R` - Script to generate election data
