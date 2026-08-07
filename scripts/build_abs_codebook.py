#!/usr/bin/env python3
"""
build_abs_codebook.py

Parses all ABS harmonization YAML configs and wave label files to produce
a master variable codebook CSV.

Output: data/processed/abs_variable_codebook.csv

Each row = one harmonized variable, with columns for:
  - harmonized_name, concept, description
  - scale (min, max, labels)
  - source question number per wave (w1_source ... w6_source)
  - exact question wording per wave (w1_wording ... w6_wording)
  - w1_verbatim ... w6_verbatim flags indicating wording source
  - harmonization method and notes

Usage:
  cd /Users/jeffreystark/Development/Research/survey-data-prep
  python scripts/build_abs_codebook.py
"""

import csv
import re
from pathlib import Path

import yaml


# ── Paths ────────────────────────────────────────────────────────────────────

PROJECT_ROOT = Path(__file__).resolve().parent.parent
YAML_DIR = PROJECT_ROOT / "src" / "config" / "abs" / "harmonize"
LABELS_DIR = PROJECT_ROOT / "data" / "abs" / "labels"
VERBATIM_PATH = PROJECT_ROOT / "data" / "abs" / "questionnaire_text" / "abs_verbatim_items.csv"
OUTPUT_PATH = PROJECT_ROOT / "data" / "processed" / "abs_variable_codebook.csv"

WAVES = ["w1", "w2", "w3", "w4", "w5", "w6"]

LABEL_FILES = {
    "w1": "W1_labels.txt",
    "w2": "W2_labels.txt",
    "w3": "W3_labels.txt",
    "w4": "W4_labels.txt",
    "w5": "W5_labels.txt",
    "w6": None,
}


# ── Load verbatim questionnaire text ────────────────────────────────────────

def load_verbatim() -> dict[tuple[str, str], dict]:
    """Load verbatim questionnaire text CSV as a lookup.

    Returns dict keyed on (wave, question_id) -> {section, stem_text, item_text, response_scale, notes}
    """
    if not VERBATIM_PATH.exists():
        print(f"  Verbatim file not found: {VERBATIM_PATH}")
        print("  Run: python scripts/build_abs_verbatim.py")
        return {}

    lookup = {}
    with open(VERBATIM_PATH, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            wave = row["wave"]
            qid = row["question_id"]
            if qid:
                lookup[(wave, qid)] = {
                    "item_text": row.get("item_text", ""),
                    "stem_text": row.get("stem_text", ""),
                    "section": row.get("section", ""),
                }
    return lookup


# ── Parse label files ────────────────────────────────────────────────────────

def parse_label_file(filepath: Path) -> dict[str, str]:
    """Parse a W*_labels.txt file into a dict mapping question ID -> question text."""
    if not filepath.exists():
        return {}

    text = filepath.read_text(encoding="utf-8", errors="replace")
    result = {}

    pattern = re.compile(
        r"Variable:\s+(\S+)\s*\n\s*Question:\s*(.+?)(?:\n|$)",
        re.MULTILINE
    )

    for match in pattern.finditer(text):
        var_id = match.group(1).strip().lower()
        question = match.group(2).strip()
        result[var_id] = question

    return result


def load_all_labels() -> dict[str, dict[str, str]]:
    """Load label dicts for all waves. Returns {wave: {qid: wording}}."""
    labels = {}
    for wave, filename in LABEL_FILES.items():
        if filename is None:
            labels[wave] = {}
            continue
        filepath = LABELS_DIR / filename
        labels[wave] = parse_label_file(filepath)
    return labels


# ── Parse YAML configs ───────────────────────────────────────────────────────

def parse_yaml_files() -> list[dict]:
    """Parse all YAML harmonization configs into a flat list of variable dicts."""
    variables = []

    for yml_path in sorted(YAML_DIR.glob("*.yml")):
        with open(yml_path, encoding="utf-8") as f:
            config = yaml.safe_load(f)

        if config is None or "variables" not in config:
            continue

        yaml_filename = yml_path.stem

        for var in config["variables"]:
            row = {
                "harmonized_name": var.get("id", ""),
                "concept": var.get("concept", ""),
                "yaml_file": yaml_filename,
                "description": var.get("description", ""),
                "type": var.get("type", ""),
                "scale_min": var.get("scale", {}).get("min", ""),
                "scale_max": var.get("scale", {}).get("max", ""),
                "scale_labels": "; ".join(
                    f"{k}={v}" for k, v in var.get("scale", {}).get("labels", {}).items()
                ),
                "notes": var.get("note", ""),
            }

            # Source question per wave
            source = var.get("source", {})
            for wave in WAVES:
                raw_q = source.get(wave)
                row[f"{wave}_source"] = str(raw_q) if raw_q is not None else ""

            # Harmonization method
            harm = var.get("harmonize", {})
            default_method = harm.get("default", {}).get("method", "")
            default_fn = harm.get("default", {}).get("fn", "")
            exceptions = harm.get("exceptions", {})

            if default_fn:
                row["harmonize_default"] = f"{default_method}:{default_fn}"
            else:
                row["harmonize_default"] = default_method

            exception_strs = []
            for wave, exc in exceptions.items():
                method = exc.get("method", "")
                fn = exc.get("fn", "")
                exception_strs.append(f"{wave}={method}:{fn}" if fn else f"{wave}={method}")
            row["harmonize_exceptions"] = "; ".join(exception_strs)

            variables.append(row)

    return variables


# ── Attach question wording ──────────────────────────────────────────────────

def attach_wordings(
    variables: list[dict],
    labels: dict[str, dict[str, str]],
    verbatim: dict[tuple[str, str], dict],
) -> None:
    """Add w*_wording and w*_verbatim columns.

    Uses verbatim questionnaire text as primary source.
    Falls back to SPSS label text when verbatim is not available.
    w*_verbatim = "verbatim" | "spss_label" | "" to indicate source.
    """
    for var in variables:
        for wave in WAVES:
            source_q = var.get(f"{wave}_source", "").strip()
            if not source_q:
                var[f"{wave}_wording"] = ""
                var[f"{wave}_verbatim"] = ""
                continue

            # Try verbatim first
            verbatim_entry = verbatim.get((wave, source_q))
            if verbatim_entry and verbatim_entry.get("item_text"):
                # Build wording from stem + item
                stem = verbatim_entry.get("stem_text", "")
                item = verbatim_entry["item_text"]
                if stem:
                    var[f"{wave}_wording"] = f"[{stem}] {item}"
                else:
                    var[f"{wave}_wording"] = item
                var[f"{wave}_verbatim"] = "verbatim"
                continue

            # Fall back to SPSS labels
            wave_labels = labels.get(wave, {})
            wording = wave_labels.get(source_q, "")

            # Try zero-padded variant if not found
            if not wording and re.match(r"q\d+$", source_q):
                num = re.search(r"\d+", source_q).group()
                padded = f"q{num.zfill(3)}"
                wording = wave_labels.get(padded, "")
                if not wording:
                    unpadded = f"q{int(num)}"
                    wording = wave_labels.get(unpadded, "")

            var[f"{wave}_wording"] = wording
            var[f"{wave}_verbatim"] = "spss_label" if wording else ""


# ── Write CSV ────────────────────────────────────────────────────────────────

def write_csv(variables: list[dict], output_path: Path) -> None:
    """Write the codebook to CSV."""
    if not variables:
        print("WARNING: No variables found. Check YAML directory.")
        return

    columns = [
        "harmonized_name", "concept", "yaml_file", "description", "type",
        "scale_min", "scale_max", "scale_labels",
    ]
    for wave in WAVES:
        columns.append(f"{wave}_source")
    for wave in WAVES:
        columns.append(f"{wave}_wording")
    for wave in WAVES:
        columns.append(f"{wave}_verbatim")
    columns.extend([
        "harmonize_default", "harmonize_exceptions", "notes"
    ])

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(variables)

    print(f"Wrote {len(variables)} variables to {output_path}")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    print(f"YAML directory: {YAML_DIR}")
    print(f"Labels directory: {LABELS_DIR}")
    print(f"Verbatim file: {VERBATIM_PATH}")
    print(f"Output: {OUTPUT_PATH}")
    print()

    # Parse YAMLs
    variables = parse_yaml_files()
    print(f"Parsed {len(variables)} variables from {len(list(YAML_DIR.glob('*.yml')))} YAML files")

    # Load verbatim questionnaire text
    verbatim = load_verbatim()
    print(f"Loaded {len(verbatim)} verbatim entries")

    # Load label files
    labels = load_all_labels()
    for wave, lbl in labels.items():
        print(f"  {wave}: {len(lbl)} SPSS labels loaded")

    # Attach wordings (verbatim primary, SPSS labels fallback)
    attach_wordings(variables, labels, verbatim)

    # Count wording sources
    from collections import Counter
    sources = Counter()
    for var in variables:
        for wave in WAVES:
            src = var.get(f"{wave}_source", "")
            vflag = var.get(f"{wave}_verbatim", "")
            if src:
                sources[vflag if vflag else "none"] += 1
    print(f"\nWording sources: {dict(sources)}")

    # Write
    write_csv(variables, OUTPUT_PATH)
    print("Done.")


if __name__ == "__main__":
    main()
