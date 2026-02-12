"""
Utility functions for data processing and analysis
"""

from pathlib import Path
from typing import Union
import pandas as pd


def get_project_root() -> Path:
    """Get the project root directory."""
    return Path(__file__).parent.parent.parent


def load_data(filename: str, data_type: str = "processed") -> pd.DataFrame:
    """
    Load a data file from the project data directory.
    
    Parameters
    ----------
    filename : str
        Name of the file to load
    data_type : str
        Type of data: "raw", "interim", or "processed"
        
    Returns
    -------
    pd.DataFrame
        Loaded dataframe
        
    Examples
    --------
    >>> df = load_data("survey_data.csv", "processed")
    """
    root = get_project_root()
    data_path = root / "data" / data_type / filename
    
    if not data_path.exists():
        raise FileNotFoundError(f"Data file not found: {data_path}")
    
    # Detect file type and load accordingly
    suffix = data_path.suffix.lower()
    
    if suffix == ".csv":
        return pd.read_csv(data_path)
    elif suffix == ".parquet":
        return pd.read_parquet(data_path)
    elif suffix == ".feather":
        return pd.read_feather(data_path)
    elif suffix in [".xlsx", ".xls"]:
        return pd.read_excel(data_path)
    elif suffix == ".dta":
        return pd.read_stata(data_path)
    elif suffix == ".sav":
        return pd.read_spss(data_path)
    else:
        raise ValueError(f"Unsupported file type: {suffix}")


def save_data(
    df: pd.DataFrame,
    filename: str,
    data_type: str = "processed",
    **kwargs
) -> None:
    """
    Save a dataframe to the project data directory.
    
    Parameters
    ----------
    df : pd.DataFrame
        Dataframe to save
    filename : str
        Name of the file to save
    data_type : str
        Type of data: "interim" or "processed"
    **kwargs
        Additional arguments to pass to the save function
    """
    root = get_project_root()
    data_path = root / "data" / data_type / filename
    
    # Create directory if it doesn't exist
    data_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Detect file type and save accordingly
    suffix = data_path.suffix.lower()
    
    if suffix == ".csv":
        df.to_csv(data_path, index=False, **kwargs)
    elif suffix == ".parquet":
        df.to_parquet(data_path, index=False, **kwargs)
    elif suffix == ".feather":
        df.to_feather(data_path, **kwargs)
    elif suffix in [".xlsx", ".xls"]:
        df.to_excel(data_path, index=False, **kwargs)
    else:
        raise ValueError(f"Unsupported file type: {suffix}")
    
    print(f"Data saved to: {data_path}")


def describe_data(df: pd.DataFrame) -> pd.DataFrame:
    """
    Generate comprehensive descriptive statistics.
    
    Parameters
    ----------
    df : pd.DataFrame
        Dataframe to describe
        
    Returns
    -------
    pd.DataFrame
        Descriptive statistics
    """
    desc = df.describe(include="all").T
    desc["missing"] = df.isnull().sum()
    desc["missing_pct"] = (df.isnull().sum() / len(df)) * 100
    desc["unique"] = df.nunique()
    
    return desc
