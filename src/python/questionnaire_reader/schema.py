"""Codebook-v1 record type, normalizer, and parquet writers.

Contract: data/_codebook_schema/codebook_v1.md — one row per
(survey, wave, raw_var, response_code); 11 columns, 7 required.
`response_code` is written as string; `missing_code_flag` as bool.

The `_raw` sidecar adds parse provenance per (wave, raw_var):
parse_confidence, parse_method, and scale_json (code -> label dict).
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

from .paths import parsed_dir

COLUMNS: list[str] = [
    "survey",
    "wave",
    "raw_var",
    "question_text",
    "response_code",
    "response_label",
    "missing_code_flag",
    "source_doc",
    "source_page",
    "language",
    "notes",
]


@dataclass
class CodebookRow:
    survey: str
    wave: str
    raw_var: str
    question_text: str
    response_code: str
    response_label: str
    missing_code_flag: bool
    source_doc: str | None = None
    source_page: str | None = None
    language: str | None = None
    notes: str | None = None
    # Sidecar provenance (not part of the 11-column contract).
    parse_confidence: float = 1.0
    parse_method: str = ""


def rows_to_frame(rows: list[CodebookRow]) -> pd.DataFrame:
    """Normalize parsed rows into the 11-column contract frame."""
    recs = []
    for r in rows:
        recs.append(
            {
                "survey": r.survey,
                "wave": str(r.wave),
                "raw_var": r.raw_var,
                "question_text": " ".join(str(r.question_text).split()),
                "response_code": str(r.response_code),
                "response_label": " ".join(str(r.response_label).split()),
                "missing_code_flag": bool(r.missing_code_flag),
                "source_doc": r.source_doc,
                "source_page": None if r.source_page is None else str(r.source_page),
                "language": r.language,
                "notes": r.notes,
            }
        )
    df = pd.DataFrame.from_records(recs, columns=COLUMNS)
    df = df.drop_duplicates(subset=["survey", "wave", "raw_var", "response_code"])
    return df


def sidecar_frame(rows: list[CodebookRow]) -> pd.DataFrame:
    """One row per (survey, wave, raw_var) with provenance + scale_json."""
    by_var: dict[tuple[str, str, str], list[CodebookRow]] = {}
    for r in rows:
        by_var.setdefault((r.survey, str(r.wave), r.raw_var), []).append(r)
    recs = []
    for (survey, wave, raw_var), grp in by_var.items():
        scale = {str(g.response_code): str(g.response_label) for g in grp}
        recs.append(
            {
                "survey": survey,
                "wave": wave,
                "raw_var": raw_var,
                "question_text": " ".join(str(grp[0].question_text).split()),
                "n_codes": len(scale),
                "parse_confidence": min(g.parse_confidence for g in grp),
                "parse_method": grp[0].parse_method,
                "scale_json": json.dumps(scale, ensure_ascii=False),
                "source_doc": grp[0].source_doc,
            }
        )
    return pd.DataFrame.from_records(recs)


def write_outputs(survey: str, rows: list[CodebookRow]) -> tuple[Path, Path]:
    """Write the contract parquet + _raw sidecar; returns both paths."""
    out = parsed_dir(survey)
    core = rows_to_frame(rows)
    side = sidecar_frame(rows)
    core_path = out / f"{survey.replace('-', '_')}_questionnaire_items.parquet"
    side_path = out / f"{survey.replace('-', '_')}_questionnaire_items_raw.parquet"
    core.to_parquet(core_path, index=False)
    side.to_parquet(side_path, index=False)
    return core_path, side_path
