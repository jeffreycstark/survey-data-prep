# ABS draft specs — NOT loaded by the pipeline

These were parked in `src/config/abs/harmonize/` while that directory was inert
(ABS production specs lived in `harmonize_validated/`). When the two were merged
on 2026-08-07 so ABS matches every other survey, keeping them in place would have
silently added 27 variables to the harmonized output.

They are drafts, never validated, and none of their variables appears in
`data/processed/abs_harmonized.rds`:

- `regime_nostalgia.yml` — 6 vars (`democracy_scale_past/now/future`, `econ_country_past`, …).
  `src/config/_anchors/economic_evaluations.yml` refers to it as a non-production file.
- `wvs_turkey_gradient.yml` — 21 `wvs_*` vars. WVS variables under `config/abs/`;
  misfiled rather than merely unused.

To promote one: validate it, then move it up into `../harmonize/`.
