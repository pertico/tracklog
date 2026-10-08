import sys
import logging
import uuid
import hashlib
import numpy as np
import pandas as pd

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    stream=sys.stdout  # <--- Esto asegura la salida estándar
)

def calc_track_points_md5(timestamps):
    # Unir todos los timestamps ordenados/secuenciales en una sola cadena
    joined = ','.join(timestamps.astype(str))
    return hashlib.md5(joined.encode('utf-8')).hexdigest()

def track_summary(df:pd.DataFrame) -> pd.DataFrame:
    summary = (
        df.groupby('track_uid', as_index=False)
        .agg(
            start_time=('time', 'min'),
            end_time=('time', 'max'),
            distance_m=('distance_meters', 'sum'),
            points=('time', 'count')  # o cualquier columna no nula
        )
    )

    # Calcular la duración total en minutos a partir de la diferencia entre start_time y end_time
    summary['duration_m'] = (summary['end_time'] - summary['start_time']).dt.total_seconds() / 60.0

    # Calculamos velocidad media del track
    summary['speed_kmh'] = summary['distance_m']/(summary['duration_m']*60) * 3.6

    # Reordenar las columnas en el orden exacto deseado
    summary = summary[['track_uid', 'points', 'start_time', 'end_time', 'duration_m', 'distance_m', 'speed_kmh']]

    #1. Asegurar la representación exacta en formato string de las columnas
    summary_strings = (
        summary['start_time'].astype(str) + "::" +
        summary['end_time'].astype(str) + "::" +
        summary['points'].astype(str)
    )

    # 2. Generar el hash MD5 usando list comprehension (muy rápido)
    summary['summary_digest'] = [
        hashlib.md5(val.encode('utf-8')).hexdigest() 
        for val in summary_strings
    ]

    # Calcular la Serie con los digests por track_uid
    points_md5_series = df.groupby('track_uid')['time'].agg(calc_track_points_md5)

    # Asignar a summary
    summary['content_digest'] = summary['track_uid'].map(points_md5_series)

    return summary

def haversine(lat1, lon1, lat2, lon2):
    """
    Calcula la distancia Haversine en metros entre dos conjuntos de coordenadas.
    """
    R = 6371000.0  # Radio medio de la Tierra en metros

    lat1_rad, lon1_rad = np.radians(lat1), np.radians(lon1)
    lat2_rad, lon2_rad = np.radians(lat2), np.radians(lon2)

    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad

    a = np.sin(dlat / 2.0)**2 + np.cos(lat1_rad) * np.cos(lat2_rad) * np.sin(dlon / 2.0)**2
    c = 2 * np.arctan2(np.sqrt(a), np.sqrt(1 - a))

    return R * c

def cleaning_pandas(tracklog: pd.DataFrame) -> pd.DataFrame:

    # Eliminamos registros con timestamp nulo
    logging.info('Remove null timestamps...')
    tracklog['time'] = pd.to_datetime(tracklog['time'], errors='coerce')
    # tracklog = tracklog.dropna(subset=['timestamp'])
    # tracklog = tracklog[tracklog['timestamp'].notna()]
    tracklog.dropna(subset=['time'], inplace=True)

    # Ordenar y eliminar timestamps duplicados
    # logging.info('Sort and remove duplicated timestamps...')
    # tracklog = tracklog.sort_values("time").drop_duplicates(subset=["time"], keep="first")

    # Generamos un uuid para cada track y ordenamos
    logging.info(f"Generate track UUID and sort...")
    NAMESPACE_BASE = uuid.uuid5(uuid.NAMESPACE_DNS, 'tracklog')
    '''
    # Esta opción con apply (fila por fila) es más lenta.
    tracklog['track_uid'] = tracklog.apply(
        lambda row: str(uuid.uuid5(
            NAMESPACE_BASE, 
            f"{row['source']}::{row['source_file']}::{row['track_fid']}"
        )), 
        axis=1
    )    
    '''
    tracklog['track_uid'] = [str(uuid.uuid5(NAMESPACE_BASE, val)) for val in tracklog['source'].astype(str) + "::" + tracklog['source_file'].astype(str) + "::" + tracklog['track_fid'].astype(str)]
    tracklog.sort_values(by=['track_uid', 'time'], inplace=True)

    # Calculamos deltas
    logging.info(f"Calculate deltas...")
    tracklog['time_delta'] = tracklog.groupby('track_uid')['time'].diff()

    # 1. Obtener la latitud y longitud del punto anterior por cada track_uid
    tracklog['prev_lat'] = tracklog.groupby('track_uid')['lat'].shift(1)
    tracklog['prev_lon'] = tracklog.groupby('track_uid')['lon'].shift(1)

    # 2. Calcular la distancia respecto al punto anterior
    tracklog['distance_meters'] = haversine(
        tracklog['prev_lat'], tracklog['prev_lon'], 
        tracklog['lat'], tracklog['lon']
    )

    # 3. Limpiar las columnas auxiliares
    tracklog = tracklog.drop(columns=['prev_lat', 'prev_lon'])

    # Crear track summary
    logging.info(f"Create track summary...")
    summary = track_summary(tracklog)

    logging.info(f"Remove duplicates...")
    # 1. Obtener la lista/máscara de 'track_uid' que queremos CONSERVAR
    # Identificamos las filas no duplicadas en 'summary' según 'content_digest'
    # (keep='first' conserva el primer track_uid encontrado para cada digest)
    summary_sin_duplicados = summary.drop_duplicates(subset=['content_digest'], keep='first')

    # 2. Filtrar 'tracklog' manteniendo solo los track_uid válidos
    tracklog = tracklog[tracklog['track_uid'].isin(summary_sin_duplicados['track_uid'])]

    # 3. Limpiar también 'summary' para que quede alineado con 'tracklog'
    summary = summary_sin_duplicados.reset_index(drop=True)


    logging.info("Remove subtracks...")
    # 1. Realizar un merge cruzado (o cartesiano) de summary consigo mismo
    # En Pandas 2.x se utiliza how='cross'
    cross_summary = summary.merge(
        summary, 
        how='cross', 
        suffixes=('_child', '_parent')
    )

    # 2. Excluir la autocomparación (un track no es subtrack de sí mismo)
    cross_summary = cross_summary[
        cross_summary['track_uid_child'] != cross_summary['track_uid_parent']
    ]

    # 3. Aplicar las condiciones temporales para identificar subtracks
    # (Empieza igual o después Y termina igual o antes que el parent)
    is_subtrack_condition = (
        (cross_summary['start_time_child'] >= cross_summary['start_time_parent']) &
        (cross_summary['end_time_child'] <= cross_summary['end_time_parent'])
    )

    subtracks_detected = cross_summary[is_subtrack_condition]

    # 4. Obtener la lista única de 'track_uid' que son subtracks de algún otro track
    subtrack_uids = subtracks_detected['track_uid_child'].unique()

    # A. Marcar en summary qué tracks son subtracks y de qué track dependen
    # summary['is_subtrack'] = summary['track_uid'].isin(subtrack_uids)

    # B. Si prefieres eliminar los subtracks de ambos DataFrames:
    summary = summary[~summary['track_uid'].isin(subtrack_uids)].reset_index(drop=True)
    tracklog = tracklog[tracklog['track_uid'].isin(summary['track_uid'])].reset_index(drop=True)

    logging.info(f"{len(subtrack_uids)} subtracks removed.")

    # Calculo de distintas estadíticas de los tracks
    logging.info(f"Calculate track statistics")
    # 1. Asegurar que las métricas por punto están calculadas
    # (Ignoramos los valores NaN/0 de los primeros puntos de cada track para no sesgar el cálculo)
    points_clean = tracklog[tracklog['time_delta'].dt.total_seconds() > 0].copy()

    # 2. Construir la tabla de estadísticas avanzadas por track
    track_stats = (
        points_clean.groupby('track_uid', as_index=False)
        .agg(
            # Métricas de Puntos y Tiempo
            total_points=('time', 'count'),
            time_mean_sec=('time_delta', 'mean'),
            time_median_sec=('time_delta', 'median'),
            time_max_sec=('time_delta', 'max'),
            time_std_sec=('time_delta', 'std'),
            time_p95_sec=('time_delta', lambda x: x.quantile(0.95)),
            
            # Métricas de Distancia
            dist_mean_m=('distance_meters', 'mean'),
            dist_median_m=('distance_meters', 'median'),
            dist_max_m=('distance_meters', 'max'),
            dist_p95_m=('distance_meters', lambda x: x.quantile(0.95)),
            
            # Métricas de Velocidad (para detectar saltos anómalos/imposibles)
            # speed_max_kmh=('speed_kmh', 'max'),
            # speed_p95_kmh=('speed_kmh', lambda x: x.quantile(0.95))
        )
    )

    # 3. Formatear y rellenar nulos en tracks con un solo punto
    track_stats = track_stats.fillna(0.0)

    # Unir summary con track_stats a través de track_uid
    summary = summary.merge(
        track_stats, 
        on='track_uid', 
        how='left'
    )

    # Calulo de puntos de split
    logging.info(f"Calculate break points (phase 1)...")
    tracklog['is_break'] = False
    tracklog['is_break'] = (tracklog['time_delta'].dt.total_seconds() > 3600) | tracklog['is_break']
    logging.info(f"{len(tracklog[tracklog['is_break']])} break points.")

    logging.info(f"Calculate break points (phase 2)...")
    split_candidates = summary[summary['time_max_sec'].dt.total_seconds() > (summary['time_median_sec'].dt.total_seconds() * 1000)]

    # 1. Filtrar tracklog dejando solo los candidatos
    tracklog_to_split = tracklog[tracklog['track_uid'].isin(split_candidates['track_uid'])]

    # 2. Obtener los índices exactos del punto con time_delta máximo en cada track
    idx_breakpoints = tracklog_to_split.groupby('track_uid')['time_delta'].idxmax()

    tracklog.loc[idx_breakpoints, 'is_break'] = True
    logging.info(f"{len(tracklog[tracklog['is_break']])} break points.")
    
    
    # Calular segment_id, nuevo track_uid e actulizar deltas
    logging.info("Calculate segment_id, track_uid and update deltas...")
    # 2. Agrupar la serie booleana por track_uid y hacer cumsum()
    tracklog['segment_id'] = tracklog.groupby('track_uid')['is_break'].cumsum()

    # 4. Reconstruir un nuevo 'track_uid' combinando el original y el segmento
    tracklog['track_uid'] = (
        tracklog['track_uid'].astype(str) + "_seg" + tracklog['segment_id'].astype(str)
    )

    # 3. Resetear las métricas del primer punto de cada nuevo subtrack
    es_inicio_segmento = tracklog.groupby('track_uid').cumcount() == 0

    tracklog.loc[es_inicio_segmento, 'time_delta'] = pd.NaT
    tracklog.loc[es_inicio_segmento, 'distance_meters'] = 0.0
   
    return tracklog

logging.info(f"Start cleaning...")
cleaning_pandas(pd.read_parquet("./data/tracklog.parquet"))
logging.info(f"Finished cleaning...")
