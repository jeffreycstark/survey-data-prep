# IPUS Unification Perception Survey (서울대 통일평화연구원 통일의식조사)

**Status**: Initial (11 vars, 18 annual waves 2007–2024, 21,617 respondents, South Korea only).

Run by SNU Institute for Peace and Unification Studies (서울대 통일평화연구원); n≈1,200 each year. **Longest Korean unification opinion series in our pipeline** (vs KGSS's 17 calendar-year waves and KINU's 13 fielding waves). Annual fielding has no gaps 2007–2024.

## Pipeline

```bash
Rscript src/r/data_prep_modules/ipus/0_load_waves.R
Rscript src/r/data_prep_modules/ipus/2_harmonize_all.R
Rscript src/r/data_prep_modules/ipus/99_create_final_dataset.R
```

Source: `data/ipus/raw/{2007..2024}/` — one `.sav` + codebook per year (18 years). Codebooks for 2008/2009 are PDFs (not parsed).

## Loading

```r
d <- readRDS("data/processed/ipus_harmonized.rds")
# Or: arrow::read_parquet("data/processed/ipus_harmonized.parquet")
```

## ⚠️ Critical caveats

- **Variable-name rotation across waves** is heavy: same construct appears under different raw names across the 18 waves (e.g., `uni_necessity` is `a12` in 2007/2009/2010, `b06` in 2008, `uni01` in 2011-2020, `uni01_a` in 2021-2024). The harmonization layer hides this; raw-data users should consult `data/ipus/questionnaire_text/raw_to_harmonized.csv`.
- **Encoding mojibake** in the raw `.sav` files for years 2008, 2009, 2013–2016 — the loader passes `encoding="CP949"` for those years to recover Korean labels. Other years use UTF-8 default.
- **2012 SAV has stripped variable labels** (NULL); inferred mapping is reliable from variable-name continuity (uni01-style is consistent with 2011/2013).
- **No weight column** in any IPUS year; treat as unweighted.

## Variable categories

| Category | Variables | Scale |
|----------|-----------|-------|
| Unification (3) | uni_necessity (1–5 reversed, higher=more pro-unification, 18 waves), uni_view (categorical 1–4: aid recipient → opposed; 18 waves), uni_timing (categorical 1–5: <5yr → impossible; 18 waves) | varies |
| Demographics (4) | sex (binary; 17 waves, missing 2012 due to 0/1 coding mismatch), age (continuous; 16 waves, missing 2008/2009 which used 4-bucket only), urban_rural (1–3 reversed, higher=more urban; 18 waves), religion (categorical 1–98; 18 waves) | varies |
| North Korea (4) | nk_nuke_threat (1–4 reversed, higher=more threatened; 18 waves), nk_sk_relations (categorical 1=aid → 5=enemy; 18 waves), nk_recent_change (1–4 reversed, higher=more change perceived; 18 waves), nk_regime_wants_unif (1–4 reversed, higher=more wants to unify; 15 waves, missing 2007/2008/2010) | varies |
| Identifiers (3) | wave (integer year), year (integer), country = "KOR" | nominal |

## Verbatim dictionary

`data/ipus/questionnaire_text/ipus_verbatim_items.csv` — Initial (192 rows, 11 harmonized vars × 18 waves; built from SAV embedded labels via `src/scripts/build_ipus_verbatim.R` + alias map). 2012 SAV has stripped labels — those 10 rows flagged for manual codebook extraction. 2008/2009 codebooks are PDFs (not parsed).

## Triangulation: KINU / KGSS / IPUS

All three Korean unification series are now harmonized. **Direction conventions**:
- IPUS `uni_necessity`: higher=more pro-unification ✓ (project rule)
- KINU `uni_necessity`: higher=more pro-unification ✓
- KGSS `pol_unification`: higher=LESS pro-unification (OPPOSITE direction; reverse before comparing)

All three peak in 2018 (Pyongyang summit) and decline post-2020. IPUS's 2007 baseline (which both KGSS and KINU lack) shows that 2007 had the highest pro-unification of the entire 18-year period — useful contextual baseline.
