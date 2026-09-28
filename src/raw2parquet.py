
import os
import sys
import logging
import datetime
import pandas as pd
import geopandas as gpd
import gpxpy
from fitparse import FitFile
from datetime import datetime

# Configuración inicial
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    stream=sys.stdout  # <--- Esto asegura la salida estándar
)

def procesar_gpx(ruta):
    puntos = []
    track_fid = 0
    track_seg_id = 0
    track_seg_point_id = 0
    with open(ruta, 'r') as f:
        try:
            gpx = gpxpy.parse(f)
            for track in gpx.tracks:
                track_name = track.name
                track_type = track.type
                for segment in track.segments:
                    for p in segment.points:
                        puntos.append({'source': 'GPX', 'track_name': track_name, 'track_type':track_type, 'track_fid': track_fid, 'track_seg_id': track_seg_id, 'track_seg_point_id': track_seg_point_id,'time': p.time, 'lat': p.latitude, 'lon': p.longitude, 'ele': p.elevation, 'source_file': os.path.basename(ruta)})
                        track_seg_point_id += 1
                    track_seg_point_id = 0
                    track_seg_id += 1
                track_seg_id=0
                track_fid += 1
        except:
            raise Exception("Failed to parsar GPX file: ", f) 
    return puntos

def procesar_fit(ruta):
    puntos = []
    fitfile = FitFile(ruta)
    for record in fitfile.get_messages('record'):
        d = record.get_values()
        if 'position_lat' in d and 'position_long' in d:
            # FIT guarda lat/lon en semicírculos, hay que convertir a grados
            lat = d['position_lat'] * (180.0 / 2**31)
            lon = d['position_long'] * (180.0 / 2**31)
            puntos.append({
                'source': 'FIT',
                'time': d.get('timestamp'),
                'lat': lat,
                'lon': lon,
                'ele': d.get('enhanced_altitude', d.get('altitude')),
                'source_file': os.path.basename(ruta)
            })
    return puntos

# Función para aplicar la lógica
#def limpiar_tz(dt):
#    # Verificamos si tiene tzinfo y si el nombre de su clase contiene 'SimpleTZ'
#    if dt and hasattr(dt, 'tzinfo') and 'SimpleTZ' in str(type(dt.tzinfo)):
#        return dt.replace(tzinfo=datetime.astimezone.utc)
#    return dt


# --- MAIN ---
data_dir = os.environ['ONEDRIVE'] + '/Documentos/GPS'
raw_data_dir = data_dir + '/GPX/Download'  # Cambia esto por tu ruta

todos_los_puntos = []

logging.info('Start processing files...')
#for archivo in os.listdir(directorio):
for root, subfolders, files in os.walk(raw_data_dir):
    # No iteramos por subfolders, os.walk ya entrará en ellas en la siguiente vuelta    
    for file in files:
        logging.info(f'Procecessing {file.lower()}')
        full_path = os.path.join(root, file)
        if file.lower().endswith('.gpx'):
            todos_los_puntos.extend(procesar_gpx(full_path))
        elif file.lower().endswith(('.fit')):
            todos_los_puntos.extend(procesar_fit(full_path))

# Convertir a DataFrame
df = pd.DataFrame(todos_los_puntos)
# Change "Zulu time" por UTC
df['time'] = pd.to_datetime(df['time'], utc=True)
# Aplicamos a la columna
# df['time'] = df['time'].apply(limpiar_tz)


# Convertir a GeoDataFrame para que sea un GeoParquet real
gdf = gpd.GeoDataFrame(df, geometry=gpd.points_from_xy(df.lon, df.lat), crs="EPSG:4326")

# Guardar como Parquet (formato estándar de alto rendimiento)
gdf.to_parquet(data_dir + '/tracklog.parquet')

logging.info(f"Done!: {len(df)} points processed.")