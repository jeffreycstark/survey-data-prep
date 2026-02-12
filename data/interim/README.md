# Interim Data

This directory contains intermediate data files created during processing.

## Purpose

Interim data represents the state between raw and final processed data:
- Partially cleaned data
- Merged datasets before final transformations
- Data after major processing steps

## Guidelines

- Document transformations applied to create each interim file
- Include source file references
- Use clear naming: `step_description_yyyymmdd.ext`
- These files can be regenerated from raw data

## Example Files

- `01_cleaned_survey.csv` - Initial cleaning of raw survey data
- `02_merged_demographic.csv` - Survey merged with demographic data
- `03_recoded_variables.csv` - Variables recoded but not final
