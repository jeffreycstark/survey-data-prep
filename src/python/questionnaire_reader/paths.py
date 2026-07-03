"""Repo-root and per-survey path resolution."""

from __future__ import annotations

from pathlib import Path


def repo_root(start: Path | None = None) -> Path:
    """Walk up from `start` (default: this file) to the pyproject.toml root."""
    p = (start or Path(__file__)).resolve()
    for candidate in [p, *p.parents]:
        if (candidate / "pyproject.toml").is_file():
            return candidate
    raise FileNotFoundError("pyproject.toml not found walking up from " + str(p))


def parsed_dir(survey: str) -> Path:
    """Output directory for Source-C artifacts (created on demand)."""
    d = repo_root() / "data" / survey / "questionnaire_parsed"
    d.mkdir(parents=True, exist_ok=True)
    return d


def codebook_parquets(survey: str) -> list[Path]:
    """Source-A parquets written by the R extractors."""
    d = repo_root() / "data" / survey / "codebook"
    return sorted(d.glob("*.parquet")) if d.is_dir() else []


def verbatim_csv(survey: str) -> Path | None:
    """Source-B verbatim dictionary CSV, or None if the survey has none."""
    stem = survey.replace("-", "_")
    p = (
        repo_root()
        / "data"
        / survey
        / "questionnaire_text"
        / f"{stem}_verbatim_items.csv"
    )
    return p if p.is_file() else None


def polarity_lexicon_path() -> Path:
    return repo_root() / "src" / "config" / "_audit" / "polarity_lexicon.yml"
