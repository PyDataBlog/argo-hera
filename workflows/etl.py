from hera.workflows import (
    DAG,
    Artifact,
    Container,
    NoneArchiveStrategy,
    Workflow,
    WorkflowsService,
)


def get_minimal_etl_workflow() -> Workflow:
    with Workflow(
        generate_name="mini-etl-",
        entrypoint="etl-pipeline",
        namespace="argo",
        workflows_service=WorkflowsService(
            host="http://argo.10.145.85.4.nip.io",
            verify_ssl=False,
        ),
        service_account_name="wf-argo-workflows-server",
    ) as w:
        # Extract: Create a simple text file with data
        extract_container = Container(
            name="extract",
            image="alpine:3.18",
            command=["sh", "-c"],
            args=[
                "echo 'id,name,value\n1,alice,100\n2,bob,250\n3,charlie,300' > /tmp/data.csv"
            ],
            outputs=[
                Artifact(
                    name="raw-data",
                    path="/tmp/data.csv",
                    archive=NoneArchiveStrategy(),
                )
            ],
        )

        # Transform: Convert names to uppercase
        transform_container = Container(
            name="transform",
            image="alpine:3.18",
            command=["sh", "-c"],
            args=[
                'cat /tmp/input.csv | awk -F, \'NR==1 {print; next} {print $1 "," toupper($2) "," $3}\' > /tmp/transformed.csv'
            ],
            inputs=[Artifact(name="input-csv", path="/tmp/input.csv")],
            outputs=[
                Artifact(
                    name="transformed-data",
                    path="/tmp/transformed.csv",
                    archive=NoneArchiveStrategy(),
                )
            ],
        )

        # Load: Print the final data (simulating database load)
        load_container = Container(
            name="load",
            image="alpine:3.18",
            command=["sh", "-c"],
            args=[
                "echo 'Loading data to database...' && cat /tmp/final.csv && echo 'Load complete!'"
            ],
            inputs=[Artifact(name="final-csv", path="/tmp/final.csv")],
        )

        # Extract DAG
        with DAG(
            name="extract-dag",
            outputs=[
                Artifact(
                    name="extract-output",
                    from_="{{tasks.extract.outputs.artifacts.raw-data}}",
                )
            ],
        ) as extract_dag:
            extract_container()

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
            transform_container(
                arguments=transform_dag.get_artifact("input-data").with_name(
                    "input-csv"
                )
            )

        # Load DAG
        with DAG(
            name="load-dag",
            inputs=[Artifact(name="final-data")],
        ) as load_dag:
            load_container(
                arguments=load_dag.get_artifact("final-data").with_name("final-csv")
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

    return w


# Create and submit the workflow
get_minimal_etl_workflow().create()
