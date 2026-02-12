# Codebook Module - Quick Reference

**TL;DR**: Search → Generate YAML → Edit → Harmonize

---

## One-Liner Examples

### Generate YAML from search results

```r
source("src/r/codebook/codebook_workflow.R")
generate_codebook_yaml(
  extract_matches("economic condition", w1, w2, w3, w4, w5, w6),
  concept = "economy",
  save_to = "src/config/harmonize/economy.yml"
)
```

### Generate multiple YAML files at once

```r
batch_generate_yaml(
  list(
    economy = results_econ,
    politics = results_politics,
    governance = results_gov
  ),
  output_dir = "src/config/harmonize/"
)
```

### Get detailed analysis report

```r
cat(analyze_search_results(results, concept = "economy"))
```

---

## Common Tasks

### Task: Auto-generate YAML for one concept

```r
# 1. Load module
source("src/r/codebook/codebook_workflow.R")

# 2. Get search results
results <- extract_matches("your search term", w1, w2, w3, w4, w5, w6)

# 3. Generate YAML
yaml_str <- generate_codebook_yaml(results, concept = "concept_name")

# 4. Review
cat(yaml_str)

# 5. Save
writeLines(yaml_str, "src/config/harmonize/concept_name.yml")
```

### Task: Review what was detected

```r
# Scale types for each wave
for (wave in names(grouped$q1)) {
  info <- detect_scale_type(1:10, grouped$q1[[wave]]$value_labels)
  cat(sprintf("%s: %s (%s)\n", wave, info$type, info$direction))
}

# Reversals between waves
detect_reversals(lapply(grouped$q1, function(x) x$value_labels))
```

### Task: Batch process all search results

```r
# Define all your searches
search_list <- list(
  economy = extract_matches("economic condition", waves),
  politics = extract_matches("trust government", waves),
  democracy = extract_matches("democratic system", waves),
  rights = extract_matches("civil rights", waves)
)

# Generate all YAML files at once
batch_generate_yaml(search_list, "src/config/harmonize/")

# Check results
# → economy.yml, politics.yml, democracy.yml, rights.yml created
```

### Task: Edit generated YAML

Generated YAML has this structure (fill in blanks):

```yaml
q1:
  id: "FILL_IN_HERE"  # e.g., econ_national, econ_family
  concept: "economy"
  description: "..."
  source:
    w1: "..."
    ...
  # ⚠️ REVERSAL comments show what was detected
  harmonize:
    default:
      method: "identity"  # or "r_function"
    by_wave:
      # Add entries here for waves that need special handling
      w3:
        method: "r_function"
        fn: "safe_reverse_5pt"
        validate_all: ["econom"]
  qc:
    valid_range_by_wave: {}
```

---

## Function Cheat Sheet

| Function | Purpose | Input | Output |
|----------|---------|-------|--------|
| `generate_codebook_yaml()` | Main entry: search → YAML | search_df | yaml_string or file |
| `analyze_search_results()` | Review report | search_df | markdown_report |
| `detect_scale_type()` | Identify scale | values, labels | list(type, range, direction, conf) |
| `detect_reversals()` | Find flipped scales | wave_labels | list(reversed_pairs, conf, notes) |
| `group_by_question()` | Organize by question | search_df | grouped_list |
| `batch_generate_yaml()` | Multi-concept YAML | results_list | saved_files |
| `parse_search_results()` | Normalize format | raw_results | standard_df |

---

## Debug Checklist

**Problem**: YAML not generated
- [ ] `results` data frame has correct columns? (wave, variable_name, variable_label)
- [ ] `concept` parameter is set?
- [ ] No rows in search results?

**Problem**: Reversals not detected
- [ ] Value labels present in search results?
- [ ] Labels use standard English keywords (bad/good, yes/no, agree/disagree)?
- [ ] Check confidence score - may be below auto-detection threshold

**Problem**: Questions not grouped correctly
- [ ] Variable names follow qN pattern (q1, q001, q01)?
- [ ] Extract question number working? Test: `extract_question_number("q001")` → 1

**Problem**: Scale types wrong
- [ ] Values actually in 1-5 range or 1-4 range?
- [ ] Check confidence score for clues

---

## Output Locations

| File | Purpose | Location |
|------|---------|----------|
| Generated YAML | Harmonization specs | `src/config/harmonize/[concept].yml` |
| Search results | Input data frame | From `extract_matches()` |
| Analysis report | Human review | Console output (use `cat()`) |

---

## Performance Notes

- **Scale detection**: O(n) per variable, <1ms per variable
- **Reversal detection**: O(w²) for w waves, ~5ms for 6 waves
- **YAML generation**: O(w) for w waves, ~10ms per question
- **Batch processing**: Linear in number of concepts

Example: 24 matches, 6 waves, 4 questions → ~50ms total

---

## Common Patterns

### Pattern 1: One search, one YAML

```r
# Minimize complexity
results <- extract_matches("pattern", w1, w2, w3, w4, w5, w6)
generate_codebook_yaml(results, "concept", "output.yml")
```

### Pattern 2: Multiple searches, multiple YAML

```r
# Organize by domain
searches <- list(
  econ = "economic condition",
  politics = "trust government",
  rights = "civil rights"
)

results_list <- sapply(searches, function(term) {
  extract_matches(term, w1, w2, w3, w4, w5, w6)
})

batch_generate_yaml(results_list)
```

### Pattern 3: Review first, save later

```r
# Don't save automatically - review first
yaml_str <- generate_codebook_yaml(results, "concept")
cat(yaml_str)  # Review

# Then save manually
writeLines(yaml_str, "file.yml")
```

---

## Tips & Tricks

**Tip 1**: Use `analyze_search_results()` before `generate_codebook_yaml()` to check what's being detected

```r
cat(analyze_search_results(results, "concept"))
# Review output...
generate_codebook_yaml(results, "concept", save_to = "...")
```

**Tip 2**: Filter results before processing if searching for broad term

```r
# If searching for "condition" matches 100+ variables:
results <- extract_matches("condition", waves)
results_econ <- subset(results, grepl("economic|economy", label, ignore.case = TRUE))
generate_codebook_yaml(results_econ, "economy")
```

**Tip 3**: Check reversal confidence if unsure

```r
revs <- detect_reversals(lapply(grouped$q1, function(x) x$value_labels))
revs$confidence  # 0-1 score, >0.8 = high confidence
```

**Tip 4**: Manual overrides for stubborn cases

If auto-detection is wrong, edit the YAML directly:

```yaml
# If system detected reversal but you know it's not:
harmonize:
  default:
    method: "identity"  # Force identity, skip reversal

# If system missed reversal:
by_wave:
  w3:
    method: "r_function"
    fn: "safe_reverse_5pt"
```

---

## Workflow Decision Tree

```
Have search results?
├─ No → Run extract_matches()
└─ Yes
   ├─ Just one concept? → generate_codebook_yaml()
   ├─ Multiple concepts? → batch_generate_yaml()
   └─ Want to review first? → analyze_search_results()

Generated YAML looks good?
├─ No → Edit by hand or adjust in generate call
└─ Yes → Save to src/config/harmonize/[concept].yml

Ready to harmonize?
└─ Load YAML in harmonize_all() and run
```

---

## Files to Know

```
src/r/codebook/
├── codebook_analysis.R      ← Core detection logic
├── codebook_workflow.R      ← Integration (search → YAML)
├── test_codebook.R          ← Tests
├── README.md                ← Full documentation
├── SKILL_SEARCH_AND_ANALYZE.md ← Skill details
└── QUICK_REFERENCE.md       ← You are here
```

---

## Next Steps

1. ✅ Search for variables: `extract_matches()`
2. ✅ Generate YAML: `generate_codebook_yaml()`
3. ✅ Edit YAML: Open in text editor, fill blanks
4. ➜ Validate YAML: `validate_harmonize_spec()`
5. ➜ Harmonize: `harmonize_all()`
6. ➜ Check QC: `report_harmonization()`
