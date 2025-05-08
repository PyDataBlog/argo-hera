from hera.workflows import (
    DAG,
    Artifact,
    Container,
    NoneArchiveStrategy,
    Workflow,
    WorkflowsService,
)


def get_workflow() -> Workflow:
    # Initialize workflow
    with Workflow(
        generate_name="dag-artifact-passing-",
        entrypoint="runner-dag",
        namespace="argo",
        workflows_service=WorkflowsService(
            host="http://argo.10.145.85.4.nip.io",
            verify_ssl=False,
        ),
        service_account_name="wf-argo-workflows-server",
    ) as w:
        # Task: generate artifact
        hello_world_to_file = Container(
            name="hello-world-to-file",
            image="busybox",
            command=["sh", "-c"],
            args=["sleep 1; echo hello world | tee /tmp/hello_world.txt"],
            outputs=[
                Artifact(
                    name="hello-art",
                    path="/tmp/hello_world.txt",
                    archive=NoneArchiveStrategy(),
                )
            ],
        )

        # Task: consume artifact
        print_message_from_file = Container(
            name="print-message-from-file",
            image="alpine:latest",
            command=["sh", "-c"],
            args=["cat /tmp/message"],
            inputs=[Artifact(name="message", path="/tmp/message")],
        )

        # DAG 1: generate the artifact
        with DAG(
            name="generate-artifact-dag",
            outputs=[
                Artifact(
                    name="hello-file",
                    from_="{{tasks.hello-world-to-file.outputs.artifacts.hello-art}}",
                )
            ],
        ) as generator_dag:
            hello_world_to_file()

        # DAG 2: consume the artifact
        with DAG(
            name="consume-artifact-dag",
            inputs=[Artifact(name="hello-file-input")],
        ) as consumer_dag:
            print_message_from_file(
                arguments=consumer_dag.get_artifact("hello-file-input").with_name(
                    "message"
                )
            )

        # Root DAG: link producer to consumer
        with DAG(name="runner-dag"):
            g = generator_dag()
            c = consumer_dag(
                arguments=g.get_artifact("hello-file").with_name("hello-file-input")
            )
            g >> c

    return w


# Create and submit the workflow
get_workflow().create()
