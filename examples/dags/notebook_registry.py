"""
Auto-discovers notebooks that have a `papermill_job` metadata block and creates
Papermill-powered Airflow DAGs for each. This lets JupyterHub users publish notebooks
and have them executed/scheduled automatically once they mark them as ready.
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict

from airflow import DAG
from airflow.providers.papermill.operators.papermill import PapermillOperator

NOTEBOOK_ROOT = Path(os.environ.get("OPENLAKES_NOTEBOOK_ROOT", "/opt/airflow/dags/examples"))
ARTIFACT_ROOT = os.environ.get("OPENLAKES_NOTEBOOK_ARTIFACTS", "/opt/airflow/artifacts")
DEFAULT_ARGS = {
    "owner": "openlakes",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}


def load_notebook_metadata(nb_path: Path) -> Dict:
    try:
        with nb_path.open() as fp:
            nb = json.load(fp)
    except Exception:
        return {}
    metadata = nb.get("metadata", {})
    return metadata.get("papermill_job", {})


def create_dag_from_metadata(nb_path: Path, meta: Dict) -> DAG:
    dag_id = meta["dag_id"]
    schedule = meta.get("schedule", None)
    output_nb = meta.get(
        "output_notebook",
        os.path.join(ARTIFACT_ROOT, f"{dag_id}-{{{{ ds }}}}.ipynb"),
    )
    parameters = meta.get("parameters", {})

    dag = DAG(
        dag_id=dag_id,
        schedule=schedule,
        start_date=datetime(2025, 1, 1),
        catchup=False,
        default_args=DEFAULT_ARGS,
        description=f"Papermill job generated from notebook {nb_path}",
    )

    with dag:
        PapermillOperator(
            task_id=f"run_{dag_id}",
            input_nb=str(nb_path),
            output_nb=output_nb,
            parameters=parameters,
        )

    return dag


def discover_notebook_dags():
    for nb_path in NOTEBOOK_ROOT.rglob("*.ipynb"):
        meta = load_notebook_metadata(nb_path)
        if not meta.get("enabled"):
            continue
        if "dag_id" not in meta:
            continue
        dag = create_dag_from_metadata(nb_path, meta)
        globals()[dag.dag_id] = dag


if NOTEBOOK_ROOT.exists():
    discover_notebook_dags()
else:
    print(
        json.dumps(
            {
                "message": "Notebook root does not exist; skipping DAG generation",
                "notebook_root": str(NOTEBOOK_ROOT),
            }
        )
    )
