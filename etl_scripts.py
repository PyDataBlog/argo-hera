from hera.workflows import (
    DAG,
    Artifact,
    NoneArchiveStrategy,
    Workflow,
    WorkflowsService,
    script,
)

ARGO_SERVER = "http://argo.10.145.85.4.nip.io"
ARGO_SECURE = "false"
ARGO_NAMESPACE = "argo"


# Extract step with explicit output artifact
@script(
    image="python:3.13-alpine",
    outputs=[
        Artifact(name="data", path="/tmp/data.csv", archive=NoneArchiveStrategy())
    ],
)
def extract():
    import csv

    print("Extracting data...")
    data = [
        ["id", "name", "value"],
        [1, "alice", 100],
        [2, "bob", 250],
        [3, "charlie", 300],
    ]

    with open("/tmp/data.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerows(data)

    print("Extraction complete!")


# Transform step with input and output artifacts
@script(
    image="python:3.13-alpine",
    inputs=[Artifact(name="raw-data", path="/tmp/input.csv")],
    outputs=[
        Artifact(
            name="transformed-data",
            path="/tmp/transformed.csv",
            archive=NoneArchiveStrategy(),
        )
    ],
)
def transform():
    import csv

    print("Transforming data...")
    transformed_rows = []

    with open("/tmp/input.csv", "r") as f:
        reader = csv.reader(f)
        headers = next(reader)
        transformed_rows.append(headers)

        for row in reader:
            # Convert name to uppercase
            row[1] = row[1].upper()
            transformed_rows.append(row)

    with open("/tmp/transformed.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerows(transformed_rows)

    print("Transformation complete!")


# Load step with input artifact
@script(
    image="python:3.13-alpine",
    inputs=[Artifact(name="final-data", path="/tmp/final.csv")],
)
def load():
    import csv

    print("Loading data to database...")

    with open("/tmp/final.csv", "r") as f:
        reader = csv.reader(f)
        print("Headers:", next(reader))
        for row in reader:
            print(f"Loading record: {row}")

    print("Load complete!")


# Create the ETL workflow
with Workflow(
    generate_name="mini-etl-",
    entrypoint="etl-pipeline",
    namespace=ARGO_NAMESPACE,
    workflows_service=WorkflowsService(
        host=ARGO_SERVER,
        verify_ssl=False,
    ),
    service_account_name="wf-argo-workflows-server",
) as w:
    # Extract DAG
    with DAG(
        name="extract-dag",
        outputs=[
            Artifact(
                name="extract-output",
                from_="{{tasks.extract.outputs.artifacts.data}}",
            )
        ],
    ) as extract_dag:
        extract(name="extract")

    # Transform DAG
    with DAG(
        name="transform-dag",
        inputs=[Artifact(name="input-data")],
        outputs=[
            Artifact(
                name="transform-output",
                from_="{{tasks.transform.outputs.artifacts.transformed-data}}",
            )
        ],
    ) as transform_dag:
        transform(
            name="transform",
            arguments={
                "artifacts": {"raw-data": transform_dag.get_artifact("input-data")}
            },
        )

    # Load DAG
    with DAG(
        name="load-dag",
        inputs=[Artifact(name="final-data")],
    ) as load_dag:
        load(
            name="load",
            arguments={
                "artifacts": {"final-data": load_dag.get_artifact("final-data")}
            },
        )

    # Main ETL pipeline DAG
    with DAG(name="etl-pipeline"):
        e = extract_dag()
        t = transform_dag(
            arguments=e.get_artifact("extract-output").with_name("input-data")
        )
        l = load_dag(
            arguments=t.get_artifact("transform-output").with_name("final-data")
        )

        # Define execution order
        e >> t >> l

# Submit the workflow
w.create()
