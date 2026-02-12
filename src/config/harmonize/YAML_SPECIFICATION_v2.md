# Harmonization YAML Specification v2

## Overview

This document describes the elegant, non-redundant YAML format (v2) for defining survey variable harmonization specifications.

**Key Principles:**
- DRY (Don't Repeat Yourself) - no repeated identical blocks
- Default + Exceptions pattern - specify once, override selectively
- Clear semantics - structure reflects intent
- Processable - easy to parse and apply rules

---

## Complete Model Example

```yaml
# Harmonization Specification - Model YAML (v2)
# A clean, non-redundant format for survey variable harmonization

missing_conventions:
  treat_as_na:
    codes: [-1, -2, 97, 98, 99]
    description: "Standard missing codes across all waves"

variables:
  - id: econ_national_now
    concept: economy
    description: "Overall national economic condition today"
    type: ordinal
    
    # Source mapping: wave -> question_code
    source:
      w1: q001
      w2: q1
      w3: q1
      w4: q1
      w5: q1
      w6: q1
    
    # Target scale definition
    scale:
      min: 1
      max: 5
      labels:
        1: "Very bad"
        2: "Bad"
        3: "So so"
        4: "Good"
        5: "Very good"
    
    # Harmonization rules
    harmonize:
      default:
        method: identity
      # Only specify waves that differ from default
      exceptions:
        w3:
          method: r_function
          fn: safe_reverse_5pt
        w4:
          method: r_function
          fn: safe_reverse_5pt
        w5:
          method: r_function
          fn: safe_reverse_5pt
        w6:
          method: r_function
          fn: safe_reverse_5pt
    
    # Quality control
    qc:
      valid_range: [1, 5]  # Applies to all waves unless overridden
      validate:
        - waves: [w1, w2, w3]
          phrase: "econom"
        - waves: [w4, w5, w6]
          phrase: "economy"
    
    # Metadata
    tags: [core, "candidate_index:economy"]
```

---

## Section Reference

### missing_conventions (Top-level, required)

Defines missing value handling conventions used across variables.

```yaml
missing_conventions:
  treat_as_na:
    codes: [-1, -2, 97, 98, 99]
    description: "Standard missing codes across all waves"
```

**Fields:**
- `treat_as_na.codes` - Array of numeric codes to treat as missing
- `treat_as_na.description` - Human-readable explanation

---

### variables (Top-level, required)

Array of variable specifications.

#### id
Unique identifier for the variable (used in output dataset names)

```yaml
id: econ_national_now
```

#### concept
The conceptual domain/category this variable belongs to

```yaml
concept: economy
```

#### description
Human-readable description of what the variable measures

```yaml
description: "Overall national economic condition today"
```

#### type
Data type: `ordinal`, `nominal`, `continuous`, etc.

```yaml
type: ordinal
```

---

### source (Required)

Maps each wave to its corresponding question code in the raw data.

```yaml
source:
  w1: q001
  w2: q1
  w3: q1
  w4: q1
  w5: q1
  w6: q1
```

**Keys:** Wave names (w1-w6)  
**Values:** Question codes from raw survey data

---

### scale (Optional)

Defines the measurement scale for this variable.

```yaml
scale:
  min: 1
  max: 5
  labels:
    1: "Very bad"
    2: "Bad"
    3: "So so"
    4: "Good"
    5: "Very good"
```

**Fields:**
- `min` - Minimum value
- `max` - Maximum value
- `labels` - Optional mapping of values to text labels

---

### harmonize (Required)

Specifies how to transform raw values into harmonized form.

#### default (Required)

The base transformation method applied to all waves:

```yaml
harmonize:
  default:
    method: identity
```

**Common methods:**
- `identity` - Use raw values as-is
- `r_function` - Apply an R function
- `recode` - Explicit value recoding

#### exceptions (Optional)

Waves that deviate from the default method:

```yaml
harmonize:
  default:
    method: identity
  exceptions:
    w3:
      method: r_function
      fn: safe_reverse_5pt
    w4:
      method: r_function
      fn: safe_reverse_5pt
    w5:
      method: r_function
      fn: safe_reverse_5pt
    w6:
      method: r_function
      fn: safe_reverse_5pt
```

**Only specify waves that differ from default** - this minimizes redundancy.

---

### qc (Quality Control, Optional)

Defines validation rules for data quality checks.

#### valid_range (Optional)

The acceptable range of values. Applies to all waves unless overridden.

```yaml
qc:
  valid_range: [1, 5]
```

#### validate (Optional)

Grouped wave validation with different phrases for different wave sets.

```yaml
qc:
  valid_range: [1, 5]
  validate:
    - waves: [w1, w2, w3]
      phrase: "econom"
    - waves: [w4, w5, w6]
      phrase: "economy"
```

**Structure:**
- `waves` - Array of wave codes to apply this phrase to
- `phrase` - Keyword to search for in question text (for validation/matching)

**Why grouped waves?**
- Shows intent clearly - groups of similar waves
- Scales elegantly for multiple phrase sets
- Easy to maintain - updates to one group don't affect others

---

### tags (Optional)

Array of metadata tags for organization and filtering.

```yaml
tags: [core, "candidate_index:economy"]
```

---

## v1 vs v2 Comparison

| Aspect | v1 | v2 |
|--------|----|----|
| **Harmonize by_wave** | Repeats all 6 waves | Only specifies exceptions |
| **QC valid_range_by_wave** | Repeats [1,5] for all 6 waves | Single `valid_range` |
| **QC validate_all** | Array format `["econom"]` | Grouped `validate` structure |
| **Lines of code** | 45 lines | 32 lines |
| **Redundancy** | High | Minimal |
| **Clarity** | Good | Better - clear defaults and overrides |
| **Maintainability** | Moderate | High - easier to update |

---

## Processing Logic

### Extracting source mappings:

```r
for (wave in names(variable$source)) {
  question_code <- variable$source[[wave]]
  # Use question_code to extract column from wave dataset
}
```

### Applying harmonization:

```r
# Get harmonization method
method <- variable$harmonize$default$method

# Check for wave-specific exception
if (!is.null(variable$harmonize$exceptions[[wave]])) {
  method <- variable$harmonize$exceptions[[wave]]$method
}

# Apply method to this wave's data
```

### Validating with QC phrases:

```r
for (group in variable$qc$validate) {
  phrase <- group$phrase
  for (wave in group$waves) {
    # Use phrase to validate question text in wave dataset
    # e.g., grep(phrase, question_text, ignore.case=TRUE)
  }
}
```

---

## Best Practices

1. **Use defaults generously** - If most waves use the same method, make it the default
2. **Group similar waves** - In QC validate, group waves that share the same phrase
3. **Keep source mapping simple** - Just wave → question_code mapping
4. **Document labels** - Include human-readable scale labels for interpretation
5. **Tag variables** - Use consistent tags for filtering and organization

---

## Example: Multi-Phrase Variable

```yaml
- id: trust_civil_service
  concept: institutional_trust
  description: "Trust in civil service"
  type: ordinal
  
  source:
    w1: q011
    w2: q12
    w3: q12
    w4: q12
    w5: q12
    w6: q12
  
  scale:
    min: 1
    max: 4
    labels:
      1: "No trust"
      2: "Low trust"
      3: "High trust"
      4: "Complete trust"
  
  harmonize:
    default:
      method: identity
  
  qc:
    valid_range: [1, 4]
    validate:
      - waves: [w1]
        phrase: "CIVIL"
      - waves: [w2, w3, w4, w5, w6]
        phrase: "CIVIL"
```

---

## File Naming

Save variable specifications with the concept name:

```
src/config/harmonize/
├── democracy_satisfaction.yml
├── economy.yml
├── institutional_trust.yml
├── local_government_corruption.yml
└── ...
```

Each file should contain `missing_conventions` at the top level and `variables` as an array of variable specifications.

