
import numpy as np
import pandas as pd


def clean_tracklog(df: pd.DataFrame) -> pd.DataFrame:
    df.loc[df['ele' < 0]] = np.nan
    df.dropna(subset=[time], inplace=True)

    return df


def pandas_processing():

    df = pd.read_parquet("data/tracklog.parquet")

    df = clean_tracklog(df)

    print("=" * 45)
    print(" RESULTADOS ESTRATEGIA 3 (GEOPANDAS / R-TREE)")
    print("=" * 45)
    print(f"Total de registros:          {total_filas:,}")
    print(f"Elevaciones nulas restantes: {nulos_restantes:,}")
    print(f"Porcentaje de nulos:         {pct_nulos:.2f}%")
    print("=" * 45)


    # Ordenar y eliminar timestamps duplicados
    df = df.sort_values("time").drop_duplicates(subset=["time"], keep="first")


pandas_processing