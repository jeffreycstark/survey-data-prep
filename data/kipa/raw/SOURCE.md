# Source & provenance — KIPA Social Cohesion Survey (KSIS)

**Survey**: 사회통합실태조사 / Korea Social Integration Survey
**Producer**: 한국행정연구원 (Korea Institute of Public Administration, KIPA)
**Distributor**: 한국사회과학자료원 / Korea Social Science Data Archive (**KOSSDA**)
**Archive portal**: https://kossda.snu.ac.kr — search `사회통합실태조사` for the full series
**DOI pattern**: `https://doi.org/10.22687/KOSSDA-A1-{year}-{id}-V{n}`
(series handle `A1`, same as the KIPA Corruption Survey — the numeric `{id}` disambiguates within a year)

Access requires a KOSSDA account and a data-use agreement; the DOI resolves to the
catalog landing page, not a direct file. The exact DOI + citation are printed in the
**인용 / Citation** box on each year's catalog page.

> This survey has **no per-dataset README** in the KOSSDA download (unlike the
> corruption survey), which is why provenance is recorded here instead.

## Per-file provenance

`{file}` → KOSSDA catalog page (handle) → DOI. Handle URLs below were confirmed to
exist via KOSSDA search. DOIs marked *(resolver-confirmed)* were verified through the
official `doi.org` resolver, which 302-redirects each DOI to the handle shown here.
Rows with a handle but `TODO` DOI need the DOI read off the catalog page's 인용/Citation
box (KOSSDA's TLS chain blocked a direct fetch from the prep environment). `TODO` handle
= catalog page not yet located.

| File | Year | KOSSDA catalog page | DOI |
|---|---|---|---|
| `kipa_2011.sav` | 2011 | TODO — see ⚠ below | TODO |
| `kipa_2012.sav` | 2012 | TODO — see ⚠ below | TODO |
| `kipa_2013.sav` | 2013 | TODO | TODO |
| `kipa_2014.sav` | 2014 | https://kossda.snu.ac.kr/handle/20.500.12236/23585 | `10.22687/KOSSDA-A1-2014-0217-V1.0` *(resolver-confirmed)* |
| `kipa_2015.sav` | 2015 | TODO | TODO |
| `kipa_2016.sav` | 2016 | https://kossda.snu.ac.kr/handle/20.500.12236/23583 | `10.22687/KOSSDA-A1-2016-0092-V1.0` *(resolver-confirmed)* |
| `kipa_2017.sav` | 2017 | https://kossda.snu.ac.kr/handle/20.500.12236/23582 | TODO — read off page |
| `kipa_2018.sav` | 2018 | TODO | TODO |
| `kipa_2019.sav` | 2019 | TODO | TODO |
| `kipa_2020.sav` | 2020 | https://kossda.snu.ac.kr/handle/20.500.12236/24721 | `10.22687/KOSSDA-A1-2020-0033-V1.0` *(resolver-confirmed)* |
| `kipa_2021.sav` | 2021 | https://kossda.snu.ac.kr/handle/20.500.12236/25722 | TODO — read off page |
| `kipa_2022.sav` | 2022 | TODO | TODO |
| `kipa_2023.sav` | 2023 | https://kossda.snu.ac.kr/handle/20.500.12236/28189 | TODO — read off page |
| `kipa_2024.sav` | 2024 | TODO — see ⚠ below | TODO |
| `kipa_2025.sav` | 2025 | TODO — see ⚠ below | TODO |

Questionnaires held locally: `kipa_2021_questionnaire.pdf`, `kipa_2022_questionnaire.pdf`,
`한국행정연구원_사회통합실태조사_설문지_2025.hwp`, `..._설문조사 개요서_2025.hwp`.

## ⚠ Provenance flags to resolve

- **2011–2012**: KIPA/KOSSDA document the 사회통합실태조사 as running **annually since
  2013**. `kipa_2011.sav` / `kipa_2012.sav` therefore may be a **pre-2013 pilot** or a
  **different KIPA survey** filed here. Confirm what these two files are before citing a
  2011/2012 DOI — a matching KOSSDA "사회통합실태조사" entry may not exist for them.
- **2024–2025**: newer than most catalog entries located so far. 2025 microdata may not
  be on KOSSDA yet — verify availability, and confirm whether `kipa_2025.sav` was sourced
  from KOSSDA or directly from KIPA.

## Related

- KIPA **Corruption** Survey (a *different* survey, `data/kipa_corruption/`) ships its own
  per-dataset READMEs with DOIs; see `data/kipa_corruption/raw/unzipped/<handle>/README.txt`.
- Year→handle map for the corruption survey:
  `src/r/data_prep_modules/kipa_corruption/0_load_waves.R`.
