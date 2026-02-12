#!/usr/bin/env python3
"""
Build script for processing data pipeline
Runs all data processing steps in sequence
"""

import sys
from pathlib import Path
import subprocess

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent / "src" / "python"))

def run_step(script_path: Path, description: str) -> None:
    """Run a processing step and handle errors"""
    print(f"\n{'='*60}")
    print(f"Running: {description}")
    print(f"Script: {script_path}")
    print(f"{'='*60}\n")
    
    try:
        result = subprocess.run(
            [sys.executable, str(script_path)],
            check=True,
            capture_output=True,
            text=True
        )
        print(result.stdout)
        if result.stderr:
            print(f"Warnings: {result.stderr}")
        print(f"✓ {description} completed successfully")
    except subprocess.CalledProcessError as e:
        print(f"✗ Error in {description}")
        print(f"Error output: {e.stderr}")
        sys.exit(1)

def main():
    """Main build pipeline"""
    base_path = Path(__file__).parent.parent
    src_python = base_path / "src" / "python"
    
    print(f"Starting data processing pipeline")
    print(f"Base directory: {base_path}")
    
    # Define processing steps
    steps = [
        # (src_python / "ingest" / "load_raw_data.py", "Data ingestion"),
        # (src_python / "validation" / "validate_data.py", "Data validation"),
        # (src_python / "export" / "export_processed.py", "Export processed data"),
    ]
    
    # Run each step
    for script, description in steps:
        if script.exists():
            run_step(script, description)
        else:
            print(f"⚠ Skipping {description} - script not found: {script}")
    
    print(f"\n{'='*60}")
    print("Build pipeline completed successfully!")
    print(f"{'='*60}\n")

if __name__ == "__main__":
    main()
