import pandas as pd

def processing_pandas(df: pd.DataFrame) -> pd.DataFrame:

    # Anulamos valores de altura negativos y superiores a 4000
    # Si la condición se cumple, se reemplaza por NaN; si no, conserva su valor
    df['ele'] = df['ele'].mask((df['ele'] < 0) | (df['ele'] > 4000))

    # Actualizar valores e base a grid
    df['lat_round'] = df['lat'].round(4)
    df['lon_round'] = df['lon'].round(4)
    grid = (
        df.groupby(['lat_round', 'lon_round'], as_index=False)
        .agg(ele_mean=('ele', 'mean'))
    )

    # Usando merge (más lenta)
    df = df.merge(
        grid[['lat_round', 'lon_round', 'ele_mean']], 
        left_on=['lat_round', 'lon_round'], 
        right_on=['lat_round', 'lon_round'], 
        how='left',
        suffixes=('', '_grid')
    )
    df['ele'] = df['ele'].fillna(df['ele_mean'])
    df = df.drop(columns=['lat_round','lon_round','ele_mean'])

    '''
    # Alternativa usando map con MultiIndex (muy rápida e in-place)
    # En una primera aproximación no parece mucho más rápida.
    # 1. Crear un índice compuesto en grid
    grid_indexed = grid.set_index(['lat_round', 'lon_round'])['ele_mean']

    # 2. Generar la clave de búsqueda indexando df con las coordenadas redondeadas
    coordenadas_df = pd.Series(
        list(zip(df['lat'].round(4), df['lon'].round(4))), 
        index=df.index
    )

    # 3. Rellenar los valores nulos mediante el mapa
    df['ele'] = df['ele'].fillna(coordenadas_df.map(grid_indexed))
    '''


    '''
    Interpolación lineal de valores nulos por track

    TODO: Posibilidad de implementar interpolación basada en la distancia transcurrida o diferencia de tiempo
    
    Resumen de los parámetros clave:
        method='linear': Trasa una interpolación lineal proporcional al número de puntos faltantes 
            (por defecto asume espacio constante entre filas). Si tus intervalos de tiempo variaran 
            mucho entre filas, puedes usar method='time' usando la columna timestamp como índice temporal.

        transform(): Garantiza que los valores calculados se mantengan alineados 
            exactamente con el índice original del DataFrame.
    '''
    df = df.sort_values(by=['track_uid', 'time'])

    '''
    # limit_direction='both' o 'inside' según lo que prefieras para los extremos
    df['ele'] = df.groupby('track_uid')['ele'].transform(
    lambda group: group.interpolate(method='linear', limit_direction='inside')
    )

    '''
    # Interpolar los valores intermedios y luego propagar bordes dentro de cada track
    df['ele'] = df.groupby('track_uid')['ele'].transform(
        lambda group: group.interpolate(method='linear').ffill().bfill()
    )
    '''
    # Extrapolar linealmente las pendientes
    df['ele'] = df.groupby('track_uid')['ele'].transform(
        lambda group: group.interpolate(method='linear', fill_value='extrapolate')
    )
    '''
