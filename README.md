# GPX Tracklog 
## ydata-profiling
``` python
import pandas as pd
from data_profiling import ProfileReport

# Cargar los datos
df = pd.read_parquet("data/tracklog.parquet")

# Generar el reporte
profile = ProfileReport(df, title="Reporte de Perfilado", exploratory=True)

# Guardar en HTML
profile.to_file("data/tracklog-report.html")
```

## Run d-tale
``` python
import dtale
import pandas as pd

df = pd.DataFrame([dict(a=1,b=2,c=3)])

# Assigning a reference to a running D-Tale process.
d = dtale.show(df)
d
```
## R - Targets
```
tracklog/
├── R/
│   ├── 01_read_data.R       # Funciones de lectura
│   ├── 02_spatial_grid.R    # Imputación por cuadrícula
│   └── 03_time_interp.R     # Interpolación temporal
├── _targets.R               # Script principal del pipeline
└── run.R                    # Script para ejecutar todo`
```

## kedro
```
tracklog-kedro/
├── conf/
│   └── base/
│       └── catalog.yml             <-- Declaración de tracklog.parquet
├── data/
│   ├── 01_raw/                     <-- Ficheros .fit, .gpx, .zip
│   └── 02_intermediate/            <-- Aquí se generará tracklog.parquet
└── src/
    ├── raw2parquet/                <-- Tu código existente
    └── mi_proyecto/
        └── pipelines/
            └── data_ingestion/     <-- Primer paso del workflow
                ├── nodes.py
                └── pipeline.py
```