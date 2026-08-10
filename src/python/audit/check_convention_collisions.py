#!/usr/bin/env python3
"""
Layer 1 / data-free: catch missing-code conventions that eat valid responses.

The failure mode this exists for: a variable's `missing.use_convention` points
at a convention whose codes fall INSIDE the variable's own valid range, so the
engine nulls real answers before anything downstream can notice. Nothing in the
existing audit sees it — the out-of-range log can't fire (the code is in range),
and coverage checks read the loss as genuine item non-response.

Two checks, both source-tree only (no survey data, so this runs in CI):

  A. LABEL_COLLISION  — a code the variable's own `scale.labels` describes as a
     substantive category is listed in its missing convention. Near-zero false
     positive rate: the spec is contradicting itself.

  B. RANGE_COLLISION  — a missing code sits inside `qc.valid_range`. Noisier;
     legitimate for wide nominal code lists, so it is reported as a warning and
     suppressible via src/config/_audit/collision_exemptions.yml.

Both checks only consider waves whose resolved rule is `method: identity`.
Missing codes are applied to the RAW vector while valid_range/labels describe
the HARMONIZED one, so for recode/r_function/derive the two live on different
scales and comparing them would be meaningless.

  python3 src/python/audit/check_convention_collisions.py [--strict]

Exit: 0 clean, 1 label collisions found (or any collision under --strict).
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import sys

import yaml

SPEC_GLOB = "src/config/*/harmonize*/*.yml"
EXEMPTIONS = "src/config/_audit/collision_exemptions.yml"

# Labels that describe non-response. A code carrying one of these is *supposed*
# to be in the missing convention.
MISSING_LABEL = re.compile(
    r"don'?t know|do not know|\bdk\b|no answer|refus|declin|not applicable"
    r"|\bn/?a\b|missing|can'?t choose|cannot choose|understand|no response"
    r"|inapplicable|not asked|skip|모름|무응답|비해당|해당\s*없|없음",
    re.I,
)


def as_float(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def codes_of(conv):
    """Mirror harmonize.R: bare scalar, bare list, or {codes: ...}."""
    if conv is None:
        return []
    if isinstance(conv, dict):
        conv = conv.get("codes")
    if conv is None:
        return []
    if not isinstance(conv, list):
        conv = [conv]
    return [c for c in (as_float(v) for v in conv) if c is not None]


def resolve_rule(harmonize, wave):
    """Mirror resolve_wave_rule() precedence: by_wave, exceptions, direct, default."""
    for holder in (harmonize.get("by_wave") or {}, harmonize.get("exceptions") or {}):
        if wave in holder:
            return holder[wave] or {}
    if wave in harmonize and wave not in ("default", "by_wave", "exceptions"):
        return harmonize[wave] or {}
    return harmonize.get("default") or {"method": "identity"}


def load_exemptions(root):
    path = os.path.join(root, EXEMPTIONS)
    if not os.path.exists(path):
        return set()
    doc = yaml.safe_load(open(path)) or {}
    out = set()
    for entry in doc.get("exemptions") or []:
        out.add((entry.get("spec"), entry.get("variable")))
    return out


def scan(root):
    exempt = load_exemptions(root)
    label_hits, range_hits = [], []

    for path in sorted(glob.glob(os.path.join(root, SPEC_GLOB))):
        if "MODEL_VARIABLE" in path:
            continue
        rel = os.path.relpath(path, root)
        try:
            spec = yaml.safe_load(open(path))
        except yaml.YAMLError as exc:
            print(f"YAML PARSE FAIL: {rel}: {exc}")
            continue
        if not isinstance(spec, dict):
            continue
        convs = spec.get("missing_conventions") or {}

        for var in spec.get("variables") or []:
            if not isinstance(var, dict):
                continue
            vid = var.get("id")
            if (rel, vid) in exempt or (None, vid) in exempt:
                continue

            conv_key = (var.get("missing") or {}).get("use_convention")
            codes = set(codes_of(convs.get(conv_key)))
            codes |= set(codes_of((var.get("missing") or {}).get("codes")))
            codes |= set(codes_of((var.get("qc") or {}).get("treat_as_na")))
            if not codes:
                continue

            source = var.get("source") or {}
            harmonize = var.get("harmonize") or {}
            identity_waves = sorted(
                w for w, s in source.items()
                if s and (resolve_rule(harmonize, w) or {}).get("method") == "identity"
            )
            if not identity_waves:
                continue

            # A. self-contradicting labels
            labels = (var.get("scale") or {}).get("labels") or {}
            bad = {
                as_float(k): str(t) for k, t in labels.items()
                if as_float(k) in codes and not MISSING_LABEL.search(str(t))
            }
            if bad:
                label_hits.append((rel, vid, conv_key, bad, identity_waves))

            # B. missing code inside the declared valid range
            qc = var.get("qc") or {}
            ranges = {}
            if isinstance(qc.get("valid_range"), list) and len(qc["valid_range"]) == 2:
                ranges["*"] = qc["valid_range"]
            for w, r in (qc.get("valid_range_by_wave") or {}).items():
                if w in identity_waves:
                    ranges[w] = r
            for w, r in ranges.items():
                lo, hi = as_float(r[0]), as_float(r[1])
                if lo is None or hi is None:
                    continue
                inside = sorted(c for c in codes if lo <= c <= hi)
                if inside:
                    range_hits.append((rel, vid, conv_key, inside, [lo, hi], w))
                    break

    return label_hits, range_hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--strict", action="store_true",
                    help="also fail on RANGE_COLLISION warnings")
    args = ap.parse_args()

    label_hits, range_hits = scan(args.root)

    if label_hits:
        print(f"\nLABEL_COLLISION — {len(label_hits)} variable(s): the spec's own "
              f"scale.labels call a code substantive, the missing convention deletes it\n")
        for rel, vid, conv, bad, waves in label_hits:
            print(f"  {rel}")
            print(f"    {vid}  [use_convention: {conv}]  identity waves: {len(waves)}")
            for code, text in sorted(bad.items()):
                print(f"        {code:g} = {text}")

    if range_hits:
        print(f"\nRANGE_COLLISION — {len(range_hits)} variable(s): missing code inside "
              f"qc.valid_range (review; exempt in {EXEMPTIONS} if intended)\n")
        for rel, vid, conv, inside, rng, wave in range_hits:
            codes = ", ".join(f"{c:g}" for c in inside)
            print(f"  {rel}: {vid} [{conv}] codes {codes} inside {rng} ({wave})")

    if not label_hits and not range_hits:
        print("no convention collisions found")

    failed = bool(label_hits) or (args.strict and bool(range_hits))
    print(f"\n{len(label_hits)} label collision(s), {len(range_hits)} range warning(s)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
