# Raw Data

This directory contains the original, immutable raw data files.

## Guidelines

- **Never modify raw data files** - they should remain exactly as received
- Document the source, date, and any relevant metadata
- Use descriptive filenames: `source_yyyymmdd_description.ext`
- Add a data dictionary for each dataset

## Data Dictionary Template

For each dataset, document:

| Variable | Description | Type | Values/Range | Missing Code |
|----------|-------------|------|--------------|--------------|
| id | Respondent ID | Numeric | 1-N | - |
| age | Age in years | Numeric | 18-99 | -99 |
| gender | Gender | Categorical | 1=Male, 2=Female, 3=Other | -99 |

## Current Datasets

### Dataset 1: Survey Data
- **File:** `survey_2024_wave1.csv`
- **Source:** [Organization/Platform]
- **Date collected:** YYYY-MM-DD
- **Sample size:** N respondents
- **Description:** Brief description
- **Codebook:** `survey_2024_codebook.pdf`

## Data Privacy

- Ensure all data files containing PII are properly protected
- Do not commit sensitive data to version control
- Follow institutional IRB and data protection guidelines
