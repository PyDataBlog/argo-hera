import os

from hera.workflows import Steps, Workflow, WorkflowsService, script

os.environ["ARGO_SERVER"] = "http://argo.10.145.85.4.nip.io"
os.environ["ARGO_HTTP1"] = "true"
os.environ["ARGO_SECURE"] = "false"
os.environ["ARGO_BASE_HREF"] = ""
os.environ["ARGO_TOKEN"] = ""
os.environ["ARGO_NAMESPACE"] = "argo"


@script()
def echo(message: str):
    print(message)


with Workflow(
    generate_name="hello-world-",
    entrypoint="steps",
    namespace=os.environ["ARGO_NAMESPACE"],
    workflows_service=WorkflowsService(host=os.environ["ARGO_SERVER"]),
) as w:
    with Steps(name="steps"):
        echo(arguments={"message": "Hello world!"})

w.create()
