# Kedro (Recomendado para proyectos de Ciencia/Ingeniería de Datos)
#
# Kedro es un framework de código abierto mantenido por la 
# LF AI & Data Foundation (Linux Foundation) diseñado específicamente 
# para crear pipelines de datos modulares, reproducibles y mantenibles en Python.

from kedro.pipeline import node, pipeline

def imputar_elevaciones_grid(df):
    # Tu código de DuckDB / Polars / Pandas
    return df_imputado

def interpolar_negativos(df):
    # Tu código con np.where e interpolación temporal
    return df_limpio

def create_pipeline(**kwargs):
    return pipeline([
        node(func=imputar_elevaciones_grid, inputs="tracklog_raw", outputs="tracklog_grid"),
        node(func=interpolar_negativos, inputs="tracklog_grid", outputs="tracklog_clean"),
    ])