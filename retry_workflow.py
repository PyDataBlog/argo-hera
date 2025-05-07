from hera.workflows import DAG, RetryStrategy, Workflow, WorkflowsService, script

ARGO_SERVER = "http://argo.10.145.85.4.nip.io"
ARGO_HTTP1 = "true"
ARGO_SECURE = "false"
ARGO_BASE_HREF = ""
ARGO_TOKEN = ""
ARGO_NAMESPACE = "argo"


# Apply retry strategy directly in the script decorator
@script(image="python:3.13", retry_strategy=RetryStrategy(limit="3"))
def task_that_might_fail(task_name: str):
    import random
    import sys

    # 50% chance of failure
    exit_code = random.choice([0, 1, 1])
    if exit_code != 0:
        print(f"Task {task_name} failed, will be retried")
        sys.exit(exit_code)

    print(f"Task {task_name} completed successfully!")


# Create a workflow using our retryable task
with Workflow(
    generate_name="retry-diamond-",
    entrypoint="diamond",
    namespace=ARGO_NAMESPACE,
    workflows_service=WorkflowsService(
        host=ARGO_SERVER,
        verify_ssl=ARGO_SECURE,
    ),
    service_account_name="wf-argo-workflows-server",
) as w:
    with DAG(name="diamond"):
        A = task_that_might_fail(name="A", arguments={"task_name": "A"})
        B = task_that_might_fail(name="B", arguments={"task_name": "B"})
        C = task_that_might_fail(name="C", arguments={"task_name": "C"})
        D = task_that_might_fail(name="D", arguments={"task_name": "D"})

        # Define execution order (diamond pattern)
        A >> [B, C] >> D

# Submit the workflow
w.create()
