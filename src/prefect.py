# Prefect o Dagster (Orquestadores Modernos de Workflows)
# Si buscas una solución de orquestación completa con interfaz web (UI), 
# programación de tareas (scheduling), retentativas y logs en tiempo real:

# Prefect: Es sumamente intuitivo y "Pythonico". 
# Solo necesitas añadir decoradores @task a tus funciones existentes 
# y @flow a la función principal que las ejecuta.
from prefect import flow, task

@task
def cargar_y_limpiar():
    ...

@flow(name="Tracklog Processing Pipeline")
def main_flow():
    df = cargar_y_limpiar()
    ...