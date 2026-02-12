# Election Data for Winner/Loser Analysis
## Matched to Asian Barometer Survey Fieldwork Dates

This document provides electoral context for refining your "winner/loser" coding by identifying:
1. The most recent election prior to each survey wave
2. Voter turnout rates (to contextualize non-voters)
3. Winner and main opposition (to identify "active losers")

---

## TAIWAN

| Wave | Fieldwork | Prior Election | Type | Turnout | Winner | Winner % | Main Opposition | Opp % |
|------|-----------|----------------|------|---------|--------|----------|-----------------|-------|
| W2 | Jan–Mar 2006 | Mar 2004 | Presidential | 80% | Chen Shui-bian (DPP) | 50.1% | Lien Chan (KMT) | 49.9% |
| W3 | Jan–Feb 2010 | Mar 2008 | Presidential | 76% | Ma Ying-jeou (KMT) | 58.4% | Frank Hsieh (DPP) | 41.6% |
| W4 | Jun–Oct 2014 | Jan 2012 | Presidential | 74% | Ma Ying-jeou (KMT) | 51.6% | Tsai Ing-wen (DPP) | 45.6% |
| W5 | Jul 2018–Jan 2019 | Jan 2016 | Presidential | 66% | Tsai Ing-wen (DPP) | 56.1% | Eric Chu (KMT) | 31.0% |
| W6 | Sep–Dec 2022 | Jan 2020 | Presidential | 75% | Tsai Ing-wen (DPP) | 57.1% | Han Kuo-yu (KMT) | 38.6% |

**Notes:**
- Taiwan holds presidential and legislative elections simultaneously (since 2012)
- Clear two-party system (DPP vs KMT) makes winner/loser coding straightforward
- Third parties (PFP, TPP) typically get <10%

---

## SOUTH KOREA

| Wave | Fieldwork | Prior Election | Type | Turnout | Winner | Winner % | Main Opposition | Opp % |
|------|-----------|----------------|------|---------|--------|----------|-----------------|-------|
| W2 | — | — | — | — | — | — | — | — |
| W3 | May 2011 | Dec 2007 | Presidential | 63% | Lee Myung-bak (GNP/Conservative) | 48.7% | Chung Dong-young (UNDP/Liberal) | 26.1% |
| W4 | Oct–Nov 2015 | Dec 2012 | Presidential | 76% | Park Geun-hye (Saenuri/Conservative) | 51.6% | Moon Jae-in (DUP/Liberal) | 48.0% |
| W5 | May–Jul 2019 | May 2017 | Presidential | 77% | Moon Jae-in (Democratic/Liberal) | 41.1% | Hong Jun-pyo (Liberty Korea/Conservative) | 24.0% |
| W6 | Jun–Jul 2022 | Mar 2022 | Presidential | 77% | Yoon Suk Yeol (PPP/Conservative) | 48.6% | Lee Jae-myung (Democratic/Liberal) | 47.8% |

**Notes:**
- W6 fieldwork (Jun-Jul 2022) was just 3-4 months after the March 2022 election
- 2017 was a snap election after Park's impeachment; Moon won plurality, not majority
- 2022 was the closest election in Korean history (0.73% margin)
- Single 5-year term limit means no incumbents running

---

## THAILAND

| Wave | Fieldwork | Prior Election | Type | Turnout | Winner | Winner % | Main Opposition | Opp % | Notes |
|------|-----------|----------------|------|---------|--------|----------|-----------------|-------|-------|
| W2 | — | — | — | — | — | — | — | — | — |
| W3 | Sep–Dec 2010 | Dec 2007 | Parliamentary | ~74% | PPP (pro-Thaksin) | 233/480 seats | Democrats | 165/480 seats | Post-2006 coup election |
| W4 | Aug–Oct 2014 | — | — | — | — | — | — | — | **NO VALID ELECTION** - Surveyed during/after May 2014 coup |
| W5 | Dec 2018–Feb 2019 | Jul 2011 | Parliamentary | 75% | Pheu Thai (pro-Thaksin) | 265/500 seats | Democrats | 159/500 seats | Last election before 2014 coup |
| W6 | Mar–Jul 2022 | Mar 2019 | Parliamentary | 75% | Pheu Thai | 136/500 seats | Palang Pracharat (military) | 116/500 seats | First election after 2014 coup |

**Notes:**
- Thailand is COMPLICATED for winner/loser analysis:
  - W4: No valid prior election (2014 election was annulled; coup occurred May 2014)
  - 2006 election boycotted by opposition, then annulled
  - Government formation often doesn't follow election results (judicial interventions, coups)
- Parliamentary system: "winner" = party that forms government, not necessarily vote plurality
- Consider excluding Thailand from winner/loser analysis due to institutional instability

---

## IMPLICATIONS FOR YOUR ANALYSIS

### Creating "Active Loser" vs "Abstainer" Categories

**Step 1: Identify ABS voting questions**
- Check for: "Did you vote in the last election?" (yes/no)
- Check for: "Which party did you vote for?" (party list)

**Step 2: Code respondents**
```
IF voted = NO → "Abstainer"
IF voted = YES AND party = winning_party → "Winner"
IF voted = YES AND party = main_opposition → "Active Loser"
IF voted = YES AND party = other → "Minor Party Voter" (optional)
```

**Step 3: Use turnout to contextualize**
- High turnout elections (>75%): Abstainers are unusual, possibly disengaged
- Low turnout elections (60-65%): Abstainers are a larger, more heterogeneous group

### Country-Specific Considerations

**Taiwan:** Clean two-party system; winner/loser straightforward
**South Korea:** Clean two-party system; winner/loser straightforward  
**Thailand:** 
- Consider excluding W4 entirely (no valid prior election)
- W5 respondents experienced 7 years of military rule since last election
- "Winner" may not reflect actual government (Pheu Thai won 2019 but didn't form government)

### Recommended Refinement

Your original binary (winner vs everyone else) could become:

| Category | Definition | Theoretical Expectation |
|----------|------------|------------------------|
| Winners | Voted for party that won/formed government | Highest satisfaction |
| Active Losers | Voted for main opposition party | Strongest "loser" effect |
| Minor Party Voters | Voted for party with <10% | Ambiguous |
| Abstainers | Did not vote | May be disengaged OR disgusted |

This lets you test whether the "loser" effect is really about *political exclusion* (strongest among active losers who participated and lost) versus *general alienation* (strongest among abstainers who've checked out).

---

## SOURCES

- Taiwan turnout: Election Study Center, National Chengchi University
- South Korea turnout: National Election Commission (NEC)
- Thailand turnout: Election Commission of Thailand
- Election results: Wikipedia country pages, IFES Election Guide
