"""
Utility functions to be shared between scripts
"""

import os
import sys
import pandas as pd
import pyreadr



def read_rds(filepath):
    """Read an RDS-format matrix into a Pandas dataframe.
    Location can be data, scratch, or results.
    Index is populated from first column"""
    raw_df = pyreadr.read_r(filepath)[None]
    if raw_df.isnull().values.any():
        raise ValueError("NaN's were found in the data matrix.")
    return raw_df.set_index(raw_df.columns[0], drop=True)

def write_rds(df, filepath):
    """Write a pandas dataframe to RDS file in the dir specified.
    Valid locations are scratch or results.
    Index is stored as first column since pyreadr.write_rds drops it otherwise"""
    df.insert(0, df.index.name, df.index, allow_duplicates=True)
    pyreadr.write_rds(filepath, df)
    # Pyreadr.write_rds fails silently when permissions prevent file write,
    # so trigger an error if our file isn't actually there
    with open(filepath, "rb"):
        pass
