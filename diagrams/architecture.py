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
from diagrams.aws.network import ALB, NATGateway
from diagrams.aws.security import IAMRole, IdentityAndAccessManagementIam
from diagrams.onprem.client import Users
from diagrams.onprem.vcs import Github

# Layout philosophy
# -----------------
# 1. Direction LR (left-to-right). TB collapses to a narrow column on this
#    library; LR gives each cluster room.
# 2. One arrow per relationship. The runtime had separate ALB->dashboard,
#    ALB->fast, ALB->slow edges; this version collapses them to a single
#    "metrics" arrow into the Observability cluster, with alarms decorating
#    the cluster from inside.
# 3. splines="polyline" instead of "ortho". Ortho is cleaner when nodes
#    align on a grid; polyline gives Graphviz freedom to route around
#    clusters without 90-degree contortions.
# 4. Generous nodesep / ranksep. The script aims for legibility over
#    diagram density.

GRAPH = {
    "fontname": "Helvetica-Bold",
    "fontsize": "22",
    # spline = smooth Bezier curves. Routes edges AROUND obstacles instead
    # of through them, which kills the label-collision problem polyline had.
    # forcelabels=true keeps xlabels visible even when they would otherwise
    # be suppressed for overlap; concentrate=false avoids merging parallel
    # edges that share endpoints (we want each labeled edge distinct).
    "splines": "spline",
    "overlap": "false",
    "forcelabels": "true",
    "concentrate": "false",
    "nodesep": "1.2",
    "ranksep": "1.8",
    "pad": "1.4",
    "bgcolor": "white",
    "dpi": "200",
    "compound": "true",
    "labelloc": "b",
    "labeljust": "c",
    "rankdir": "LR",
}
NODE = {
    "fontname": "Helvetica-Bold",
    "fontsize": "18",
    "imagepos": "tc",
    "labelloc": "b",
    "margin": "0.25,0.20",
}
EDGE = {
    "fontname": "Helvetica-Bold",
    "fontsize": "15",
}

# ---------------------------------------------------------------------------
# Diagram 1: runtime
# ---------------------------------------------------------------------------
with Diagram(
    "sre-reference-app  -  runtime",
    filename="../docs/architecture-runtime",
    show=False,
    direction="LR",
    graph_attr=GRAPH,
    node_attr=NODE,
    edge_attr=EDGE,
):
    user = Users("Internet")

    with Cluster(
        "AWS account 569239324174 / us-west-2",
        graph_attr={"bgcolor": "#FAFAFC", "style": "rounded", "margin": "20"},
    ):
        with Cluster(
            "VPC 10.0.0.0/16",
            graph_attr={"bgcolor": "#F0F4FA", "style": "rounded", "margin": "16"},
        ):
            with Cluster(
                "Public subnets (2 AZ)",
                graph_attr={"bgcolor": "#E8F1FA", "style": "rounded"},
            ):
                alb = ALB("ALB :80\nderegistration_delay = 30s")
                nat = NATGateway("NAT")

            with Cluster(
                "Private subnets (2 AZ)",
                graph_attr={"bgcolor": "#FAF1E8", "style": "rounded"},
            ):
                tasks = [
                    Fargate("ECS task 1\n256 CPU / 512 MB"),
                    Fargate("ECS task 2\n256 CPU / 512 MB"),
                ]

        with Cluster(
            "Observability",
            graph_attr={"bgcolor": "#FAFAFC", "style": "rounded", "margin": "16"},
        ):
            logs = CloudwatchLogs("/ecs/sre-app\n7-day retention")
            dash = Cloudwatch("Dashboard\nsre-app-dashboard")
            with Cluster(
                "Burn-rate alarms",
                graph_attr={"bgcolor": "#FFF4F4", "style": "rounded"},
            ):
                fast = CloudwatchAlarm("fast-burn\n1h | 14.4%")
                slow = CloudwatchAlarm("slow-burn\n6h | 6%")
            sns = SimpleNotificationServiceSnsTopic("SNS\nslo-alerts -> email")

    # Request path (blue bold)
    user >> Edge(label="HTTP :80", color="#1F6FEB", penwidth="3", fontcolor="#1F6FEB") >> alb
    alb >> Edge(label=":8080  /health 15s", color="#1F6FEB", penwidth="2") >> tasks

    # Egress + logs (gray dashed) - only one task connects each to keep edges sparse
    tasks[0] >> Edge(label="egress", style="dashed", color="#6E7B91") >> nat
    tasks[1] >> Edge(label="JSON logs", style="dashed", color="#6E7B91") >> logs

    # Single metrics edge from ALB into the Observability cluster.
    # Alarms are decorations of the cluster, not separate inbound endpoints.
    alb >> Edge(label="metrics", style="dashed", color="#6E7B91") >> dash

    # Internal alarm chain
    dash >> Edge(style="invis") >> fast
    fast >> Edge(label="page", color="#D63333", penwidth="2", fontcolor="#D63333") >> sns
    slow >> Edge(label="ticket", color="#D63333", penwidth="2", fontcolor="#D63333") >> sns


# ---------------------------------------------------------------------------
# Diagram 2: deploy pipeline
# ---------------------------------------------------------------------------
with Diagram(
    "sre-reference-app  -  deploy pipeline",
    filename="../docs/architecture-deploy",
    show=False,
    direction="LR",
    graph_attr=GRAPH,
    node_attr=NODE,
    edge_attr=EDGE,
):
    with Cluster(
        "GitHub",
        graph_attr={"bgcolor": "#F6F8FA", "style": "rounded", "margin": "16"},
    ):
        repo = Github("JadenRazo /\nsre-reference-app")
        actions = Codebuild("Actions runner\ndeploy.yml")

    with Cluster(
        "AWS account 569239324174 / us-west-2",
        graph_attr={"bgcolor": "#FAFAFC", "style": "rounded", "margin": "20"},
    ):
        with Cluster(
            "IAM (federated)",
            graph_attr={"bgcolor": "#F0F4FA", "style": "rounded", "margin": "16"},
        ):
            oidc = IdentityAndAccessManagementIam("OIDC provider\nGitHub Actions")
            role = IAMRole(
                "sre-app-gh-deploy\ntrust scoped to repo\nPassRole locked to ECS"
            )

        ecr = EC2ContainerRegistry("ECR repo\nsre-app:<sha>")

        with Cluster(
            "ECS Fargate",
            graph_attr={"bgcolor": "#FAF1E8", "style": "rounded", "margin": "16"},
        ):
            cluster = ElasticContainerService("sre-app-cluster")
            new_rev = Fargate("Task def rev N+1\nFIS-Target = true")

    repo >> Edge(label="push to main", color="#1F6FEB", penwidth="2") >> actions
    actions >> Edge(label="OIDC token\nno static keys", color="#1F6FEB", penwidth="3", fontcolor="#1F6FEB") >> oidc
    oidc >> Edge(label="AssumeRoleWithWebIdentity") >> role
    role >> Edge(label="docker push\n:sha + :latest", color="#2EA043", penwidth="2") >> ecr
    role >> Edge(label="register task def\nupdate-service", color="#2EA043", penwidth="2") >> cluster
    ecr >> Edge(style="dashed", label="image pull", color="#6E7B91") >> new_rev
    cluster >> Edge(label="rollout") >> new_rev
