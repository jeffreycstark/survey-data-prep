# Repository Structure

```
src/
├── r/
│   ├── codebook/               # Codebook YAML generation tools
│   │   ├── codebook_analysis.R
│   │   ├── codebook_workflow.R
│   │   ├── test_codebook.R
│   │   └── *.md                # Documentation
│   │
│   ├── harmonize/              # Harmonization engine (shared)
│   │   ├── harmonize.R
│   │   ├── validate_spec.R
│   │   └── report_harmonization.R
│   │
│   ├── survey/                 # Survey utilities
│   │   ├── codebook_tools.R
│   │   ├── harmonize_vars.R
│   │   └── load_data.R
│   │
│   ├── utils/                  # General utilities
│   │   ├── search.R            # extract_matches()
│   │   ├── recoding.R
│   │   └── validation.R
│   │
│   ├── data_prep_modules/      # Pipeline orchestration scripts
│   │   ├── 0_load_waves.R          # ABS wave loader
│   │   ├── 1_harmonize_funs.R      # Shared recoding helpers
│   │   ├── 2_harmonize_all.R       # ABS harmonization (shared functions)
│   │   ├── 99_create_final_dataset.R
│   │   └── {wvs,lbs,afro,arab-barometer,kamos,kgss,kipa-corruption,kinu,ipus,klosa,vdem}/
│   │       # Per-survey subdirs: 0_load_waves.R + 2_harmonize_all.R + 99_create_final_dataset.R
│   │
│   └── models/                 # Statistical models
│
├── config/
│   ├── abs/                    # Production ABS specs are in harmonize_validated/, not harmonize/
│   │   ├── harmonize/          # legacy / scratch
│   │   └── harmonize_validated/
│   └── {wvs,lbs,afro,arab-barometer,kamos,kgss,kipa,kipa-corruption,kinu,ipus,klosa}/harmonize/
│
├── python/                     # Python utilities
│   ├── ingest/
│   ├── export/
│   └── validation/
│
└── scripts/                    # Pipeline orchestration

data/
├── abs/                        # Asian Barometer Survey
│   └── raw/
│       ├── wave1/ ... wave6/   # ABS waves (SPSS .sav)
│       └── README.md
├── wvs/                        # World Values Survey
│   └── raw/
│       ├── wave1/ ... wave7/   # WVS waves (W1-W5: SPSS .sav, W6-W7: parquet)
├── lbs/                        # Latinobarómetro
│   └── raw/
│       ├── 1995/ ... 2024/     # LBS waves (SPSS .sav; 24 year-named dirs)
├── afro/                       # Afrobarometer
│   └── raw/
│       └── round1/ ... round8/, wave9/   # Afrobarometer R1-R9 (SPSS .sav)
├── kamos/                      # Korean Attitudes and Mobilization Opinion Survey
│   └── raw/
│       ├── wave1/              # KAMOS W1 2016 (SPSS .sav, n=2000)
│       └── wave4/              # KAMOS W4 2019 (SPSS .sav, n=1500)
├── kgss/                       # Korea General Social Survey
│   └── raw/
│       └── kor_data_CUM0074.sav  # Cumulative file (n=23,282, 3,491 cols, 2003-2025)
├── kinu/                       # KINU Unification Perception Survey (통일의식조사)
│   ├── raw/
│   │   ├── kinu_2014-2023_en.sav        # n=13,030, 956 cols, 13 fielding waves
│   │   └── kinu_2014-2024_codebook_en.xlsx  # cross-referenced codebook
├── ipus/                       # IPUS Unification Perception Survey (서울대 통일평화연구원)
│   └── raw/{2007..2024}/                # one .sav + codebook per year (18 years)
│       ├── ipus_{year}.sav              # primary SPSS, n≈1,200 each
│       └── ipus_{year}_codebook.{xls,xlsx,pdf}  # 2008/2009 are PDFs
├── klosa/                      # Korean Longitudinal Study of Aging (고령화연구패널조사)
│   └── raw/
│       └── w0{1..9}_e.sav               # English-labelled SPSS, one file per wave, W1-W9
├── v-dem/                      # Varieties of Democracy
│   └── raw/
│       └── v15/                # V-Dem v15 (RDS, 27,913 rows × 4,607 cols)
├── external/                   # External datasets (V-Dem, COVID, etc.)
├── interim/                    # Intermediate processing
└── processed/                  # Final harmonized datasets

outputs/
├── figures/
├── tables/
├── master_w*.rds               # ABS per-wave harmonized data
├── {wvs,lbs,afro,kamos,kgss,kipa-corruption,arab-barometer}/master_*.rds
└── harmonization_validation_*  # Validation reports

# Final combined per-survey datasets live in data/processed/{survey}_harmonized.rds
```
