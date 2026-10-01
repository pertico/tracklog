# Comparativa de la caja de herramientas en Python
#
# Criterio                  Pandas                          Polars                      GeoPandas (sjoin_nearest)
#
# Velocidad (1.5M filas)    Muy alta (~2s)                  Máxima (~0.5s)              Moderada (~10-15s)
# Consumo de Memoria        Alto                            Muy Bajo                    Alto
# Tipo de Cruce             Cuadrícula (Hash)               Cuadrícula (Hash)           Radio espacial exacto (R-Tree)
# Uso ideal                 Scripts rápidos / Prototipado   Pipelines de ETL modernos   Análisis espacial complejo

# Estrategia 1: Pandas puro (Aproximación Vectorizada con Hash Join)
# Esta es la implementación directa equivalente a la lógica que usamos en DuckDB. 
# Es extremadamente rápida (tarda un par de segundos para 1.5M de filas) 
# porque no realiza cálculos de distancia uno a uno, 
# sino un cruce de claves basado en un hash table vectorial.

import pandas as pd

# 1. Cargar datos
df = pd.read_parquet("data/tracklog.parquet")


# 2. Generar columnas temporales de cuadrícula (4 decimales ≈ 10-11 metros)
df["lat_grid"] = df["lat"].round(4)
df["lon_grid"] = df["lon"].round(4)

# 3. Crear la tabla de referencia (puntos con elevación)
ele_reference = (
    df[df["ele"].notna()]
    .groupby(["lat_grid", "lon_grid"])["ele"]
    .mean()
    .round(2)
    .reset_index()
    .rename(columns={"ele": "ele_imputed"})
)

# 4. Unir la referencia con el dataset original (Left Join)
df = df.merge(ele_reference, on=["lat_grid", "lon_grid"], how="left")

# 5. Imputar valores: si 'ele' es nulo, tomar 'ele_imputed'
df["ele"] = df["ele"].fillna(df["ele_imputed"])

# 6. Limpieza de columnas auxiliares
df.drop(columns=["lat_grid", "lon_grid", "ele_imputed"], inplace=True)

print(f"Porcentaje de nulos restante: {df['ele'].isna().mean() * 100:.2f}%")

# ----------------
# Estrategia 2: Polars (In-Memory Columnar de alto rendimiento)
# Polars está escrito en Rust y es hoy en día la alternativa moderna a Pandas. 
# Utiliza ejecución diferida (lazy evaluation) y optimización columnar multihilo, 
# siendo con frecuencia igual o más rápida que DuckDB en memoria RAM.

import polars as pl

# 1. Cargar Parquet usando el motor Lazy (no carga todo en RAM de golpe)
lazy_df = pl.scan_parquet("data/tracklog.parquet")

# 2. Definir la tabla de referencia (agrupación en cuadrícula)
reference = (
    lazy_df.filter(pl.col("ele").is_not_null())
    .with_columns([
        pl.col("lat").round(4).alias("lat_grid"),
        pl.col("lon").round(4).alias("lon_grid")
    ])
    .group_by(["lat_grid", "lon_grid"])
    .agg(pl.col("ele").mean().round(2).alias("ele_imputed"))
)

# 3. Construir la consulta completa y ejecutar en paralelo
df_final = (
    lazy_df.with_columns([
        pl.col("lat").round(4).alias("lat_grid"),
        pl.col("lon").round(4).alias("lon_grid")
    ])
    .join(reference, on=["lat_grid", "lon_grid"], how="left")
    .with_columns(
        pl.coalesce(["ele", "ele_imputed"]).alias("ele")
    )
    .drop(["lat_grid", "lon_grid", "ele_imputed"])
    .collect() # Aquí es donde se ejecuta físicamente en Rust
)

total_filas = len(df_final)
nulos_restantes = df_final["ele"].null_count()
pct_nulos = (nulos_restantes / total_filas) * 100

print("=" * 45)
print(" RESULTADOS ESTRATEGIA 2 (POLARS)")
print("=" * 45)
print(f"Total de registros:          {total_filas:,}")
print(f"Elevaciones nulas restantes: {nulos_restantes:,}")
print(f"Porcentaje de nulos:         {pct_nulos:.2f}%")
print("=" * 45)

# -----------------
# Estrategia 3: GeoPandas + Indexación Espacial (R-Tree / KD-Tree)
# Si en lugar de una cuadrícula fija quisieras medir un radio de distancia real 
# en metros (por ejemplo, buscar exactamente el punto más cercano dentro de 5 metros), 
# usar un JOIN tradicional en Python colapsaría la memoria.
#
# Para resolverlo sin bloquear el sistema, GeoPandas utiliza índices espaciales 
# tipo R-Tree (vía PyGEOS/GEOS) o algoritmos de árbol como KD-Tree (scipy.spatial):

import geopandas as gpd
import pandas as pd

# 1. Cargar como GeoDataFrame
df = pd.read_parquet("data/tracklog.parquet")
gdf = gpd.GeoDataFrame(
    df, 
    geometry=gpd.points_from_xy(df.lon, df.lat), 
    crs="EPSG:4326"
)

# 2. Separar puntos con y sin elevación
con_ele = gdf[gdf["ele"].notna()].copy()
sin_ele = gdf[gdf["ele"].isna()].copy()

# 3. Nearest Join con índice espacial (sbdjoin_nearest)
# 'max_distance' en grados decimales (0.00005° ≈ 5.5 metros)
imputed = gpd.sjoin_nearest(
    sin_ele[['geometry']], 
    con_ele[['geometry', 'ele']], 
    how="left", 
    max_distance=0.00005,
    distance_col="distancia"
)

# 4. Agrupar por el índice del punto original por si encuentra múltiples vecinos
ele_means = imputed.groupby(imputed.index)["ele"].mean().round(2)

# 5. Asignar las alturas imputadas al GeoDataFrame original
gdf.loc[sin_ele.index, "ele"] = ele_means

# --- PRINT DE VALIDACIÓN PARA GEOPANDAS ---
total_filas = len(gdf)
nulos_restantes = gdf["ele"].isna().sum()
pct_nulos = (gdf["ele"].isna().mean()) * 100

print("=" * 45)
print(" RESULTADOS ESTRATEGIA 3 (GEOPANDAS / R-TREE)")
print("=" * 45)
print(f"Total de registros:          {total_filas:,}")
print(f"Elevaciones nulas restantes: {nulos_restantes:,}")
print(f"Porcentaje de nulos:         {pct_nulos:.2f}%")
print("=" * 45)

# -----------
# Interpolación temporal de valores de elevación 
#
# 1. Implementación en Python (Pandas y Polars)
# En Pandas, el método .interpolate(method='time') requiere que el índice 
# sea de tipo datetime, mientras que .interpolate(method='linear') asume 
# intervalos constantes o posiciones ordenadas.

import numpy as np
import pandas as pd

# 1. Cargar datos y filtrar marcas de tiempo nulas
df = pd.read_parquet("data/tracklog.parquet")
df = df.dropna(subset=["time"]).copy()

# 2. Convertir a datetime, ordenar y eliminar timestamps duplicados
df["time"] = pd.to_datetime(df["time"])
df = df.sort_values("time").drop_duplicates(subset=["time"], keep="first")

# 3. Crear mascara de valores estrictamente negativos
mask_negativos = df["ele"] < 0

# 4. Crear una columna temporal con los negativos convertidos a NaN
#    para que el método interpolate pueda calcular su valor
df["ele_temp"] = np.where(mask_negativos, np.nan, df["ele"])

# 5. Calcular la interpolación basada en tiempo
df = df.set_index("time")
ele_interp = df["ele_temp"].interpolate(method="time").round(2)
df = df.reset_index()

# 6. Reemplazar ÚNICAMENTE donde la máscara original era True
df["ele"] = np.where(mask_negativos, ele_interp, df["ele"])

# 7. Eliminar columna auxiliar
df.drop(columns=["ele_temp"], inplace=True)

# --- Comprobación ---
print(f"Elevaciones negativas restantes: {(df['ele'] < 0).sum()}")
print(f"Elevaciones nulas preservadas:   {df['ele'].isna().sum()}")



# En Polars, la interpolación se realiza utilizando la función nativa interpolate() sobre la serie ordenada

import polars as pl

df = (
    pl.scan_parquet("data/tracklog.parquet")
    .filter(pl.col("time").is_not_null())
    .sort("time")
    .unique(subset=["time"], keep="first")
    .with_columns(
        # Mascara de apoyo: convertir < 0 a null para poder calcular su interpolación
        ele_tmp = pl.when(pl.col("ele") < 0).then(None).otherwise(pl.col("ele"))
    )
    .with_columns(
        ele_interp = pl.col("ele_tmp").interpolate().round(2)
    )
    .with_columns(
        # Reemplazar SOLO si el valor original era < 0
        ele = pl.when(pl.col("ele") < 0)
                .then(pl.col("ele_interp"))
                .otherwise(pl.col("ele"))
    )
    .drop(["ele_tmp", "ele_interp"])
    .collect()
)

print(f"Valores negativos restantes: {(df['ele'] < 0).sum()}")
print(f"Valores nulos de elevación restantes: {df['ele'].is_nan().sum()}")


'''
               ┌──────────────────────────────────────────┐
               │         ¿El punto es nulo?               │
               └────────────────────┬─────────────────────┘
                                    │
                                    ▼
       ┌──────────────────────────────────────────────────────────┐
       │ 1. INTERPOLACIÓN LINEAL                                  │
       │    (Aplica si tiene vecino anterior Y posterior)         │
       └────────────────────┬─────────────────────────────────────┘
                            │
                            │ Si no se puede (es un extremo)
                            ▼
       ┌──────────────────────────────────────────────────────────┐
       │ 2. EXTRAPOLACIÓN DE BORDE (Backfill / Forwardfill)       │
       │    - Inicio del track: Toma el primer valor >= 0         │
       │    - Final del track: Toma el último valor >= 0          │
       └────────────────────┬─────────────────────────────────────┘
                            │
                            │ Si todo el track fuera negativo
                            ▼
       ┌──────────────────────────────────────────────────────────┐
       │ 3. IMPUTACIÓN POR DEM / MDE                              │
       │    Consulta la altura geográfica real del punto (raster) │
       └──────────────────────────────────────────────────────────┘
'''

import polars as pl

def fix_track_elevations(df: pl.DataFrame) -> pl.DataFrame:
    return (
        df.with_columns(
            # 1. Convertir negativos a NULL temporalmente
            ele_clean = pl.when(pl.col("ele") >= 0).then(pl.col("ele")).otherwise(None)
        )
        .with_columns(
            # 2. Paso A: Interpolación lineal para puntos intermedios
            # 3. Paso B: Backward Fill (asigna el primer punto válido a los negativos del inicio)
            # 4. Paso C: Forward Fill (asigna el último punto válido a los negativos del final)
            ele_fixed = (
                pl.col("ele_clean")
                .interpolate()
                .bfill()
                .ffill()
                .round(2)
            )
        )
        .over(["track_fid", "track_seg_id"]) # ¡Crucial! Respetar los límites de cada ruta
        .with_columns(
            # Reemplazar solo en los registros donde 'ele' original era negativo
            ele = pl.when(pl.col("ele") < 0)
                    .then(pl.col("ele_fixed"))
                    .otherwise(pl.col("ele"))
        )
        .drop(["ele_clean", "ele_fixed"])
    )