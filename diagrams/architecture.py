"""Generate the two architecture diagrams referenced from README.md.

Output:
  ../docs/architecture-runtime.png
  ../docs/architecture-deploy.png

Regenerate:
  cd diagrams
  python -m venv .venv && .venv/bin/pip install -r requirements.txt
  .venv/bin/python architecture.py

Requires the system `graphviz` package (apt: graphviz, brew: graphviz).
"""
from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2ContainerRegistry, ElasticContainerService, Fargate
from diagrams.aws.devtools import Codebuild
from diagrams.aws.integration import SimpleNotificationServiceSnsTopic
from diagrams.aws.management import Cloudwatch, CloudwatchAlarm, CloudwatchLogs
from diagrams.aws.network import ALB, InternetGateway, NATGateway
from diagrams.aws.security import IAMRole, IdentityAndAccessManagementIam
from diagrams.onprem.client import Users
from diagrams.onprem.vcs import Github

GRAPH = {
    "fontname": "Helvetica",
    "fontsize": "14",
    "splines": "ortho",
    "nodesep": "0.6",
    "ranksep": "0.9",
    "pad": "0.4",
    "bgcolor": "white",
}
NODE = {"fontname": "Helvetica", "fontsize": "12"}
EDGE = {"fontname": "Helvetica", "fontsize": "10"}

# ---------------------------------------------------------------------------
# Diagram 1: runtime / request path
#
# Layout: LR top-to-bottom story.
#   1. User -> ALB (top public band)
#   2. ALB -> 2 Fargate tasks (private band)
#   3. Tasks -> NAT for egress, -> Logs for stdout
#   4. ALB metrics -> CloudWatch metric math -> 2 alarms -> single SNS topic
# IGW is omitted (implicit when the ALB is internet-facing) so the diagram
# does not carry an orphan node just to be technically complete.
# ---------------------------------------------------------------------------
with Diagram(
    "sre-reference-app - runtime",
    filename="../docs/architecture-runtime",
    show=False,
    direction="LR",
    graph_attr=GRAPH,
    node_attr=NODE,
    edge_attr=EDGE,
):
    user = Users("Internet")

    with Cluster("AWS account 569239324174 / us-west-2", graph_attr={"bgcolor": "#FAFAFC"}):
        with Cluster("VPC 10.0.0.0/16", graph_attr={"bgcolor": "#F0F4FA"}):
            with Cluster("Public subnets (2 AZ)", graph_attr={"bgcolor": "#E8F1FA"}):
                alb = ALB("ALB :80\nderegistration_delay = 30s")
                nat = NATGateway("NAT")

            with Cluster("Private subnets (2 AZ)", graph_attr={"bgcolor": "#FAF1E8"}):
                tasks = [
                    Fargate("ECS task 1\n256 CPU / 512 MB"),
                    Fargate("ECS task 2\n256 CPU / 512 MB"),
                ]

        with Cluster("Observability", graph_attr={"bgcolor": "#FAFAFC"}):
            logs = CloudwatchLogs("/ecs/sre-app\n7-day retention")
            dash = Cloudwatch("Dashboard\nsre-app-dashboard")
            with Cluster("Burn-rate alarms", graph_attr={"bgcolor": "#FFF4F4"}):
                fast = CloudwatchAlarm("fast-burn\n1h | 14.4%")
                slow = CloudwatchAlarm("slow-burn\n6h | 6%")
            sns = SimpleNotificationServiceSnsTopic("SNS\nslo-alerts")

    # request path (blue, solid)
    user >> Edge(label="HTTP :80", color="#1F6FEB", penwidth="2") >> alb
    alb >> Edge(label=":8080  /health 15s", color="#1F6FEB") >> tasks

    # task egress (gray, dashed)
    tasks[0] >> Edge(label="egress / image pull", style="dashed", color="#6E7B91") >> nat

    # logs (gray, dashed)
    tasks[1] >> Edge(label="stdout JSON", style="dashed", color="#6E7B91") >> logs

    # metrics + alarms (gray dashed for metrics, red for alarm fires)
    alb >> Edge(label="metrics", style="dashed", color="#6E7B91") >> dash
    alb >> Edge(label="RequestCount + 5xx", style="dashed", color="#6E7B91") >> fast
    alb >> Edge(style="dashed", color="#6E7B91") >> slow
    [fast, slow] >> Edge(label="page / ticket", color="#D63333", penwidth="2") >> sns


# ---------------------------------------------------------------------------
# Diagram 2: deploy pipeline
# ---------------------------------------------------------------------------
with Diagram(
    "sre-reference-app - deploy pipeline",
    filename="../docs/architecture-deploy",
    show=False,
    direction="LR",
    graph_attr=GRAPH,
    node_attr=NODE,
    edge_attr=EDGE,
):
    with Cluster("GitHub", graph_attr={"bgcolor": "#F6F8FA"}):
        repo = Github("JadenRazo/sre-reference-app\nmain branch")
        actions = Codebuild(".github/workflows/\ndeploy.yml")

    with Cluster("AWS account 569239324174 / us-west-2", graph_attr={"bgcolor": "#FAFAFC"}):
        with Cluster("IAM (federated)", graph_attr={"bgcolor": "#F0F4FA"}):
            oidc = IdentityAndAccessManagementIam(
                "OIDC provider\ntoken.actions.githubusercontent.com"
            )
            role = IAMRole(
                "sre-app-gh-deploy\ntrust: repo:JadenRazo/sre-reference-app:*\n"
                "PassRole scoped to ecs-tasks"
            )

        ecr = EC2ContainerRegistry("ECR\nsre-app:<commit-sha>")

        with Cluster("ECS", graph_attr={"bgcolor": "#FAF1E8"}):
            cluster = ElasticContainerService("sre-app-cluster")
            new_rev = Fargate("Task def rev N+1\nFIS-Target = true")

    repo >> Edge(label="push to main\n(paths: app/**, .github/workflows/deploy.yml)", color="#1F6FEB") >> actions
    actions >> Edge(label="OIDC token\n(no static keys)", color="#1F6FEB", penwidth="2") >> oidc
    oidc >> Edge(label="sts:AssumeRoleWithWebIdentity") >> role
    role >> Edge(label="docker build + push\n:commit-sha, :latest", color="#2EA043") >> ecr
    role >> Edge(label="register-task-definition\nupdate-service\nwait services-stable", color="#2EA043") >> cluster
    ecr >> Edge(style="dashed", label="image pull", color="#6E7B91") >> new_rev
    cluster >> Edge(label="rollout") >> new_rev
