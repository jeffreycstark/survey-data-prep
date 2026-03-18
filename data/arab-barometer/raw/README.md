# Arab Barometer Raw Data

Download from: https://www.arabbarometer.org/survey-data/data-downloads/
(Free registration required)

Place each wave's .sav file in the corresponding directory:

```
wave2/  ← W2 (2010-2011): Algeria, Egypt, Iraq, Jordan, Lebanon, Palestine,
                           Saudi Arabia, Sudan, Tunisia, Yemen
wave3/  ← W3 (2012-2014): +Kuwait, Libya, Morocco
wave4/  ← W4 (2016-2017): Algeria, Egypt, Jordan, Lebanon, Morocco, Palestine, Tunisia
wave5/  ← W5 (2018-2019): Algeria, Egypt, Iraq, Jordan, Kuwait, Lebanon, Libya,
                           Morocco, Palestine, Sudan, Tunisia, Yemen
wave6/  ← W6 (2020-2021): Algeria, Egypt, Iraq, Jordan, Kuwait, Lebanon, Libya,
                           Mauritania, Morocco, Palestine, Sudan, Tunisia
wave7/  ← W7 (2021-2022): Algeria, Egypt, Iraq, Jordan, Kuwait, Lebanon, Libya,
                           Mauritania, Morocco, Palestine, Sudan, Tunisia
wave8/  ← W8 (2023-2024): Iraq, Jordan, Kuwait, Lebanon, Mauritania, Morocco,
                           Palestine, Tunisia
```

The loader (`0_load_waves.R`) auto-detects the .sav filename in each directory.
