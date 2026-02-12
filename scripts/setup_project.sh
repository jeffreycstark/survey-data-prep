#!/bin/bash
#
# Project setup script for survey-data-prep
#

set -e  # Exit on error

echo "=========================================="
echo "Setting up survey-data-prep"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if we're in the project root
if [ ! -f "pyproject.toml" ]; then
    echo "Error: Please run this script from the project root directory"
    exit 1
fi

# Python setup with uv
echo -e "${BLUE}Setting up Python environment with uv...${NC}"
if command -v uv &> /dev/null; then
    uv python install 3.12.12
    uv sync
    echo -e "${GREEN}✓ Python environment created${NC}"
else
    echo "Warning: uv not found. Install from: https://astral.sh/uv"
    echo "Skipping Python setup..."
fi

# Git setup
echo -e "\n${BLUE}Initializing Git repository...${NC}"
if [ ! -d ".git" ]; then
    git init
    git add .
    git commit -m "Initial commit: survey-data-prep pipeline"
    echo -e "${GREEN}✓ Git repository initialized${NC}"
else
    echo "Git repository already exists"
fi

# Pre-commit hooks
echo -e "\n${BLUE}Setting up pre-commit hooks...${NC}"
if command -v pre-commit &> /dev/null || [ -f ".venv/bin/pre-commit" ]; then
    if [ -f ".venv/bin/activate" ]; then
        source .venv/bin/activate
    fi
    pre-commit install
    echo -e "${GREEN}✓ Pre-commit hooks installed${NC}"
else
    echo "Warning: pre-commit not found. Install with: uv tool install pre-commit"
    echo "Skipping pre-commit setup..."
fi

# R environment (renv)
echo -e "\n${BLUE}Setting up R environment...${NC}"
if command -v R &> /dev/null; then
    echo "R detected. You can initialize renv by:"
    echo "  R -e 'renv::init()'"
    echo "  R -e 'renv::restore()'"
else
    echo "R not found. Skipping R setup..."
fi

# Create initial directories
echo -e "\n${BLUE}Verifying directory structure...${NC}"
mkdir -p data/{raw,interim,processed}
mkdir -p outputs/{figures,tables}
echo -e "${GREEN}✓ Directory structure verified${NC}"

# Summary
echo ""
echo "=========================================="
echo "Setup complete! Next steps:"
echo "=========================================="
echo ""
echo "1. Activate Python environment:"
echo "   source .venv/bin/activate"
echo ""
echo "2. (Optional) Set up R environment:"
echo "   R -e 'renv::init()'"
echo ""
echo "3. Run the harmonization pipeline:"
echo "   Rscript src/r/data_prep_modules/0_load_waves.R"
echo "   Rscript src/r/data_prep_modules/2_harmonize_all.R"
echo "   Rscript src/r/data_prep_modules/99_create_final_dataset.R"
echo ""
echo "4. Set up GitHub repository:"
echo "   gh repo create survey-data-prep --public --source=. --remote=origin"
echo "   git push -u origin main"
echo ""
