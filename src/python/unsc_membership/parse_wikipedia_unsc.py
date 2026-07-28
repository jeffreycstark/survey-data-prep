"""Parse UNSC non-permanent membership from the archived Wikipedia wikitext.

Deliverable 2.3 (source 1 of 2) for paper-bank 24, papers/24-unsc/DATA-REQUEST.md.

This parser takes Wikipedia as source 1; source 2 and the 15 hand-checked
country-terms are handled separately.

CORRECTION: an earlier version of this docstring claimed the UN's own list at
un.org/securitycouncil was unusable because it returned a CloudFront 403. That
was wrong — the 403 was caused by the default curl User-Agent alone. With
ordinary browser headers the page returns 200 and serves the authoritative
roster as "Country  1970-1971, 2004-2005, ...". Reconciling against it is
therefore possible and still outstanding, not blocked.

Table structure
---------------
Each row is keyed by the year a term BEGINS and lists the five seats elected
that year. Terms run two calendar years from 1 January, so the members serving
in year Y are those elected in Y and in Y-1 -> 10 seats, which is the
invariant we validate against.

Seat allocation alternates by parity of the term-start year:
    odd  start: African 1, Asia-Pacific 1, GRULAC 1, WEOG 2
    even start: African 2, Asia-Pacific 1, Eastern European 1, GRULAC 1

CAUTION
-------
The asterisk in the source marks the seat held by the representative of Arab
nations, which alternates between the African and Asia-Pacific groups. It does
NOT mark a split or shared term. Do not map it to `split_term`.
"""

import json
import re
import csv
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
SRC = ROOT / "data" / "unsc" / "raw" / "wikipedia_unsc_members.wikitext"
OUT = ROOT / "data" / "unsc" / "interim" / "unsc_terms_wikipedia.csv"

# Column -> regional group by parity of the term-start year (see docstring).
GROUPS_ODD = ["African", "Asia-Pacific", "GRULAC", "WEOG", "WEOG"]
GROUPS_EVEN = ["African", "African", "Asia-Pacific", "Eastern European", "GRULAC"]

ROW_RE = re.compile(
    r"^!\s*\[\[(\d{4}) United Nations Security Council election\|(\d{4})\]\]\s*$"
)


def clean_country(cell: str):
    """Pull a country name out of one table cell.

    Returns (name, arab_seat_flag, n_years). Cells look like:
        rowspan="2" | {{flagwrap|Zambia|1964}}
        rowspan="1" | {{flagwrap|Italy}}
        {{flagwrap|Syria|1963}}*

    `rowspan` IS THE TERM LENGTH IN YEARS. Terms are normally two calendar
    years (rowspan=2); a rowspan of 1 marks a seat SPLIT by agreement between
    two states, each serving one year. Italy (2017) and the Netherlands (2018)
    are the case in the paper's window. Assuming every term is two years
    double-counts those seats and breaks the 10-per-year invariant.
    """
    arab = "*" in cell
    rs = re.search(r'rowspan\s*=\s*"?(\d+)"?', cell, re.I)
    n_years = int(rs.group(1)) if rs else 2
    m = re.search(r"\{\{\s*(?:flagwrap|Flag country|flag|flagcountry)\s*\|([^|}]+)", cell, re.I)
    if not m:
        m = re.search(r"\[\[([^\]|]+)", cell)
        if not m:
            return None, arab, n_years
    name = m.group(1).strip()
    name = re.sub(r"\s*\(.*?\)\s*$", "", name).strip()
    return (name or None), arab, n_years


def parse():
    text = SRC.read_text()
    lines = text.split("\n")
    rows = []
    i = 0
    while i < len(lines):
        m = ROW_RE.match(lines[i].strip())
        if not m:
            i += 1
            continue
        year = int(m.group(2))
        # Cells follow on the next non-empty content lines until the next row marker.
        j = i + 1
        buf = []
        while j < len(lines) and not lines[j].strip().startswith("!"):
            s = lines[j].strip()
            if s.startswith("|") and s != "|-":
                buf.append(s.lstrip("|"))
            j += 1
        cells = []
        for chunk in buf:
            cells.extend(chunk.split("||"))
        cells = [c.strip() for c in cells if c.strip()]
        parsed = []
        for c in cells:
            nm, arab, n_years = clean_country(c)
            if nm:
                parsed.append((nm, arab, n_years))
        if parsed:
            rows.append((year, parsed))
        i = j
    return rows


def main():
    rows = parse()
    out = []
    for year, members in rows:
        groups = GROUPS_ODD if year % 2 == 1 else GROUPS_EVEN
        for idx, (name, arab, n_years) in enumerate(members):
            out.append(
                {
                    "country_name_raw": name,
                    "term_start_year": year,
                    "term_end_year": year + n_years - 1,
                    "n_years": n_years,
                    "split_term": int(n_years != 2),
                    "regional_group": groups[idx] if idx < len(groups) else "",
                    "arab_seat": int(arab),
                    "col_index": idx,
                }
            )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)

    # ── Validation: exactly 10 non-permanent seats in every year from 1966 ──
    serving = {}
    for r in out:
        for y in range(r["term_start_year"], r["term_end_year"] + 1):
            serving.setdefault(y, []).append(r["country_name_raw"])

    print(f"parsed {len(rows)} election-year rows -> {len(out)} country-terms")
    print(f"term-start years: {min(r[0] for r in rows)}-{max(r[0] for r in rows)}")
    bad = {y: v for y, v in serving.items() if 1970 <= y <= 2025 and len(v) != 10}
    print(f"\nSEAT-COUNT CHECK (must be 10/year, 1970-2025):")
    if not bad:
        print("  ✅ all years 1970-2025 have exactly 10 non-permanent members")
    else:
        print(f"  ⚠️ {len(bad)} years off:")
        for y in sorted(bad):
            print(f"     {y}: {len(bad[y])}  {sorted(bad[y])}")
    print(f"\n-> {OUT}")


if __name__ == "__main__":
    main()
