from hera.workflows import Steps, Workflow, WorkflowsService, script

ARGO_SERVER = "http://argo.10.145.85.4.nip.io"
ARGO_HTTP1 = "true"
ARGO_SECURE = "false"
ARGO_BASE_HREF = ""
ARGO_TOKEN = ""
ARGO_NAMESPACE = "argo"


@script()
def echo(message: str):
    print(message)


with Workflow(
    generate_name="hello-world-",
    entrypoint="steps",
    namespace=ARGO_NAMESPACE,
    workflows_service=WorkflowsService(host=ARGO_SERVER),
) as w:
    with Steps(name="steps"):
        echo(arguments={"message": "Hello world!"})

w.create()
