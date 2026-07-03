"""Questionnaire-document reader (Phase 6 of the harmonization auditor).

Parses official questionnaire/codebook documents (DOCX, XLSX, PDF) into the
codebook-v1 11-column contract (data/_codebook_schema/codebook_v1.md) and
cross-validates three independent sources of response-scale truth:

  A — .sav codebook parquets extracted by the R extractors
      (data/<survey>/codebook/*.parquet)
  B — the hand-curated verbatim dictionaries
      (data/<survey>/questionnaire_text/<survey>_verbatim_items.csv)
  C — questionnaire originals parsed by this package
      (data/<survey>/questionnaire_parsed/<survey>_questionnaire_items.parquet)

CLI:
  uv run python -m questionnaire_reader parse --survey gcb
  uv run python -m questionnaire_reader crossvalidate --survey gcb
"""

__version__ = "0.1.0"
