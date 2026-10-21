# Voting App and DevOps Capstone

A containerized voting application with a local Docker Compose workflow, an
Amazon EKS deployment managed by Terraform and Helm, and GitHub Actions CI/CD.
The repository also includes Robot Shop and Kubernetes monitoring resources.

## Contents

- [Application and architecture](#application-and-architecture)
- [Run locally](#run-locally)
- [Deploy the voting app to EKS](#deploy-the-voting-app-to-eks)
- [CI/CD](#cicd)
- [Robot Shop](#robot-shop)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Cost and cleanup](#cost-and-cleanup)
- [Repository layout](#repository-layout)

## Application and architecture

Users submit votes through the Python **Vote** frontend. Votes are queued in
Redis; the .NET **Worker** consumes them and stores the results in PostgreSQL.
The Node.js **Result** frontend reads PostgreSQL and displays the totals.

```text
Browser -> Vote -> Redis -> Worker -> PostgreSQL -> Result -> Browser
```

The architecture image is [architecture.excalidraw.png](./architecture.excalidraw.png).

## Run locally

### Prerequisites

- Docker Desktop (or Docker Engine) with the Compose plugin
- Git

Clone the repository and start the stack:

```bash
git clone https://github.com/oluwahiyanu/example-voting-app.git
cd example-voting-app
docker compose up --build
```

Open:

- Voting page: <http://localhost:8080>
- Results page: <http://localhost:8081>

Cast a vote and refresh the results page to check the complete flow. To stop
the stack, press **Ctrl+C** and run:

```bash
docker compose down
```

Compose stores PostgreSQL data in the `db-data` named volume. To remove that
local data as well:

```bash
docker compose down --volumes
```

## Deploy the voting app to EKS

> **AWS costs:** EKS, EC2 worker nodes, storage, and Kubernetes
> `LoadBalancer` services can incur charges. Review the Terraform plan and
> your AWS costs before applying.

### Prerequisites

- An AWS account and AWS CLI credentials authorized to create EKS and EC2
  resources
- Terraform 1.5 or later
- `kubectl`, Helm, and Git

Terraform defaults to region `eu-north-1` and cluster name `capstone-cluster`.
From Git Bash:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Connect `kubectl` to the cluster:

```bash
aws eks update-kubeconfig --region eu-north-1 --name capstone-cluster
kubectl get nodes
```

The voting chart is in `helm/voting-app`. Its default app images are published
to GHCR under `ghcr.io/oluwahiyanu`. Install or update the release:

```bash
cd ..
helm upgrade --install voting ./helm/voting-app \
  --namespace default \
  --set apps.vote.tag=latest \
  --set apps.result.tag=latest \
  --set apps.worker.tag=latest

kubectl get pods -n default
kubectl get services -n default
```

The Vote and Result services use AWS LoadBalancers. Get their addresses with:

```bash
kubectl get services -n default
```

Open the external address for `vote` to cast votes and `result` to see the
totals. LoadBalancer provisioning can take several minutes and creates AWS
resources that may incur charges.

For a production deployment, use an immutable image tag (such as the Git
commit SHA) instead of `latest`.

## CI/CD

The workflow in [.github/workflows/ci.yml](./.github/workflows/ci.yml) runs on
pushes to `main`. It:

1. Checks Python and Node.js syntax and builds the .NET worker.
2. Builds Vote, Result, and Worker container images.
3. Scans the images with Trivy for fixable CRITICAL vulnerabilities.
4. Pushes the images to GHCR using the commit SHA as the tag.
5. Connects to EKS and upgrades the `voting` Helm release.

The single-replica Vote, Result, and Worker Deployments use a zero-surge
rolling strategy so updates do not require an extra pod slot on the cluster.
This can briefly interrupt an individual service while its replacement starts.
The `robot-shop` directory is tracked as a Git submodule; its source URL is
declared in `.gitmodules` so GitHub Actions checkout cleanup can resolve it.

Configure these repository secrets under **Settings → Secrets and variables →
Actions**:

| Secret | Purpose |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | AWS credentials for the deploy job |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials for the deploy job |

The workflow uses GitHub's `GITHUB_TOKEN` to publish packages. Make the GHCR
packages accessible to the cluster so Kubernetes can pull them.

## Robot Shop

The Robot Shop Helm chart and application sources are in the
[`robot-shop`](./robot-shop/) directory. Its chart is
[`robot-shop/K8s/helm`](./robot-shop/K8s/helm/).

Install or update it with:

```bash
kubectl create namespace robot-shop --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install robot-shop ./robot-shop/K8s/helm \
  --namespace robot-shop \
  --wait \
  --timeout 5m
kubectl get pods,services -n robot-shop
```

The chart's Redis claim uses the `gp2` StorageClass. Persistent EBS
provisioning requires a functioning EBS CSI driver and appropriate AWS
permissions in the cluster. Verify both before expecting Redis to become
Ready:

```bash
kubectl get storageclass
kubectl get csidrivers
kubectl get pvc -n robot-shop
```

The Robot Shop web frontend is exposed by a LoadBalancer service and may
create additional AWS load-balancer charges.

## Monitoring

Monitoring configuration and usage notes are in
[`monitoring/README.md`](./monitoring/README.md). The directory includes
Kustomize resources for Robot Shop monitoring, alert rules, Fluent Bit,
Jaeger, and OpenTelemetry Collector configuration.

If the kube-prometheus-stack release is already installed as `monitoring`,
apply the repository's monitoring resources with:

```bash
kubectl apply -k ./monitoring
```

Open Grafana locally:

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

Then visit <http://localhost:3000>. Keep the port-forward terminal open while
using Grafana; restart the command if its target pod is replaced.

Alertmanager's Slack configuration in `monitoring/values.yaml` reads the
webhook from the `slack-webhook` Kubernetes Secret. Do not put webhook URLs
or other credentials in Git or chat. The values file alone does not apply the
configuration to a Helm release; verify the release and its hooks before
upgrading.

## Troubleshooting

| Symptom | Checks |
| --- | --- |
| Pod is `ImagePullBackOff` | Check the image name, tag, and GHCR package access. |
| Pod is `CrashLoopBackOff` | Run `kubectl logs POD_NAME -n NAMESPACE --previous` and inspect events. |
| Pod remains `Pending` | Run `kubectl describe pod POD_NAME -n NAMESPACE`; check node pod capacity, PVCs, and StorageClasses. |
| `kubectl` cannot connect | Refresh kubeconfig with `aws eks update-kubeconfig --region eu-north-1 --name capstone-cluster`. |
| Grafana is unavailable on port 3000 | Check the Grafana pod and service, then restart the port-forward command above. |
| Helm upgrade fails | Review `helm status RELEASE -n NAMESPACE`, `helm history RELEASE -n NAMESPACE`, and Kubernetes hook pod events before retrying. |
| Redis has no endpoint in Robot Shop | Check its PVC, StorageClass, EBS CSI driver, and available node pod capacity. |

For the Robot Shop incident drill, see
[`docs/runbook.md`](./docs/runbook.md) and
[`docs/postmortem.md`](./docs/postmortem.md). The postmortem distinguishes
the drill's intended recovery scenario from the last recorded live-cluster
state.

## Cost and cleanup

When the workloads are no longer needed, uninstall their Helm releases before
destroying the cluster. This allows Kubernetes to remove LoadBalancer
resources first:

```bash
helm uninstall voting -n default
helm uninstall robot-shop -n robot-shop
helm uninstall monitoring -n monitoring
helm uninstall loki -n monitoring
helm uninstall otel -n monitoring
```

Only uninstall releases that you created and intend to remove. Then destroy
the Terraform-managed infrastructure:

```bash
cd terraform
terraform destroy
```

Review the Terraform plan before confirming destruction. This removes the
cluster infrastructure and affects every workload running in that cluster.

## Repository layout

```text
.
├── .github/workflows/ci.yml  # Build, scan, publish, and deploy pipeline
├── docs/                     # Incident runbook, SLO, and postmortem
├── helm/voting-app/          # Voting app Helm chart
├── k8s-specifications/       # Kubernetes manifests
├── monitoring/               # Monitoring configuration and dashboards
├── result/                   # Node.js results frontend
├── robot-shop/               # Robot Shop application and Helm chart
├── terraform/                # EKS infrastructure
├── vote/                     # Python voting frontend
├── worker/                   # .NET vote processor
├── docker-compose.yml        # Local development stack
└── architecture.excalidraw.png
```
