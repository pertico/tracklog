
import pandas as pd
import polars as pl


def pandas_processing():

    df = pd.read_parquet("data/tracklog.parquet")

    # Ordenar y eliminar timestamps duplicados
    df = df.sort_values("time").drop_duplicates(subset=["time"], keep="first")

def polars_processing():

    df = (
        pl.scan_parquet("data/tracklog.parquet")
        .sort("time")                               # Ordenar por timestamp
        .unique(subset=["time"], keep="first")      # Eliminar timestamp duplicados
    )

pandas_processing
polars_processing