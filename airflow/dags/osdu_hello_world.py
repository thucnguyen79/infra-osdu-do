from datetime import datetime
from airflow import DAG
from airflow.operators.python import PythonOperator

def hello():
    print("Hello from OSDU Airflow!")
    return "success"

with DAG(
    dag_id="osdu_hello_world",
    start_date=datetime(2026, 1, 1),
    schedule_interval=None,
    catchup=False,
    tags=["osdu", "test"],
) as dag:
    task = PythonOperator(
        task_id="say_hello",
        python_callable=hello,
    )
