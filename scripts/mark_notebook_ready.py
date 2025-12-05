#!/usr/bin/env python3
"""
Utility to mark a Jupyter notebook as "ready" for Airflow execution.
It injects a `papermill_job` metadata block that the notebook_registry DAG reads.
"""
import argparse
import json
import os
from pathlib import Path

import nbformat

try:
    import boto3
    from botocore.config import Config as BotoConfig
except ImportError:  # pragma: no cover
    boto3 = None


def parse_kv_pair(pair: str):
    if "=" not in pair:
        raise argparse.ArgumentTypeError(f"Invalid param '{pair}'. Use key=value.")
    key, value = pair.split("=", 1)
    return key, value


def maybe_upload_to_minio(nb_path: Path, dag_id: str, schedule: str, enabled: bool, parameters: dict, output_template: str):
    endpoint = os.environ.get("OPENLAKES_MINIO_ENDPOINT")
    access_key = os.environ.get("OPENLAKES_MINIO_ACCESS_KEY")
    secret_key = os.environ.get("OPENLAKES_MINIO_SECRET_KEY")
    bucket = os.environ.get("OPENLAKES_NOTEBOOK_BUCKET")
    published_prefix = os.environ.get("OPENLAKES_NOTEBOOK_PUBLISHED_PREFIX", "published")
    workspace_prefix = os.environ.get("OPENLAKES_NOTEBOOK_WORKSPACE_PREFIX", "workspace")
    username = os.environ.get("JUPYTERHUB_USER", "unknown")

    if not all([endpoint, access_key, secret_key, bucket]) or boto3 is None:
        return

    session = boto3.session.Session()
    s3 = session.resource(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=BotoConfig(signature_version="s3v4"),
    )

    metadata = {
        "dag-id": dag_id,
        "schedule": schedule,
        "enabled": str(enabled).lower(),
        "output-notebook": output_template,
        "owner": username,
        "parameters": json.dumps(parameters),
    }

    target_key = f"{published_prefix.rstrip('/')}/{dag_id}/{nb_path.name}"
    workspace_key = f"{workspace_prefix.rstrip('/')}/{username}/{nb_path.name}"

    def _upload(key: str):
        with nb_path.open("rb") as handle:
            s3.Object(bucket, key).put(Body=handle, Metadata=metadata)

    _upload(target_key)
    _upload(workspace_key)


def main():
    parser = argparse.ArgumentParser(description="Mark notebook as Airflow-ready via Papermill metadata.")
    parser.add_argument("--notebook", required=True, help="Path to the .ipynb file")
    parser.add_argument("--dag-id", required=True, help="Airflow DAG ID / task identifier")
    parser.add_argument("--schedule", default="@daily", help="Airflow cron schedule")
    parser.add_argument("--output-notebook", required=True, help="Path template for Papermill output notebook")
    parser.add_argument(
        "--param",
        action="append",
        default=[],
        help="Papermill parameter in key=value form (repeatable)",
    )
    parser.add_argument(
        "--disable",
        action="store_true",
        help="Disable the job instead of enabling it",
    )
    args = parser.parse_args()

    nb_path = Path(args.notebook)
    if not nb_path.exists():
        raise SystemExit(f"Notebook not found: {nb_path}")

    nb = nbformat.read(nb_path.open(), as_version=4)
    job_meta = nb.metadata.get("papermill_job", {})

    params = dict(job_meta.get("parameters", {}))
    for pair in args.param:
        key, value = parse_kv_pair(pair)
        params[key] = value

    job_meta.update(
        {
            "dag_id": args.dag_id,
            "schedule": args.schedule,
            "output_notebook": args.output_notebook,
            "enabled": not args.disable,
            "parameters": params,
        }
    )

    nb.metadata["papermill_job"] = job_meta
    nbformat.write(nb, nb_path.open("w"))

    maybe_upload_to_minio(
        nb_path=nb_path,
        dag_id=args.dag_id,
        schedule=args.schedule,
        enabled=not args.disable,
        parameters=params,
        output_template=args.output_notebook,
    )

    status = "disabled" if args.disable else "enabled"
    print(
        json.dumps(
            {
                "notebook": str(nb_path),
                "dag_id": args.dag_id,
                "schedule": args.schedule,
                "status": status,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
