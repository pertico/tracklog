import polars as pl



def polars_processing():

    df = (
        pl.scan_parquet("data/tracklog.parquet")
        .sort("time")                               # Ordenar por timestamp
        .unique(subset=["time"], keep="first")      # Eliminar timestamp duplicados
    )
