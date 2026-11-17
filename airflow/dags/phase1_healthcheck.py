"""
Phase 1 check DAG: proves Airflow is running and can see files in airflow/dags.
It is replaced by the real pipeline DAG in Phase 6.
"""
from datetime import datetime

from airflow import DAG
from airflow.operators.bash import BashOperator

with DAG(
    dag_id="phase1_healthcheck",
    description="Confirms Airflow is set up correctly",
    start_date=datetime(2026, 1, 1),
    schedule=None,   # runs only when triggered by hand
    catchup=False,
    tags=["phase1"],
) as dag:

    say_hello = BashOperator(
        task_id="say_hello",
        bash_command='echo "Airflow is working. Hello from GiftHub!"',
    )

    check_data_folder = BashOperator(
        task_id="check_data_folder",
        bash_command="ls -la /opt/airflow/data/raw",
    )

    say_hello >> check_data_folder
