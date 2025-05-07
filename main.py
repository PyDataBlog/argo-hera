import os

from hera.workflows import DAG, Workflow, WorkflowsService, script

os.environ["ARGO_SERVER"] = "http://argo.10.145.85.4.nip.io"
os.environ["ARGO_HTTP1"] = "true"
os.environ["ARGO_SECURE"] = "false"
os.environ["ARGO_BASE_HREF"] = ""
os.environ["ARGO_TOKEN"] = ""
os.environ["ARGO_NAMESPACE"] = "argo"


# Turn a function into a reusable "Script template"
# using the script decorator
@script(image="python:3.13")
def echo(message: str):
    print(message)


# Orchestration logic lives *outside* of business logic
with Workflow(
    generate_name="dag-diamond-",
    entrypoint="diamond",
    namespace=os.environ["ARGO_NAMESPACE"],
    workflows_service=WorkflowsService(
        host=os.environ["ARGO_SERVER"],
        verify_ssl=False,
    ),
    service_account_name="wf-argo-workflows-server",
) as w:
    with DAG(name="diamond"):
        A = echo(name="A", arguments={"message": "A"})
        B = echo(name="B", arguments={"message": "B"})
        C = echo(name="C", arguments={"message": "C"})
        D = echo(name="D", arguments={"message": "D"})
        A >> [B, C] >> D  # Define execution order

# Create the workflow directly on your Argo Workflows cluster!
w.create()
