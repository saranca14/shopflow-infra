# ShopFlow Infrastructure

Terraform infrastructure for the ShopFlow multi-cluster platform.

## Architecture

**Single VPC** with 3 EKS clusters sharing the same network — all cross-cluster communication is private within the VPC.

| Cluster | Subnets | Nodes | Instance | Purpose |
|---------|---------|-------|----------|---------|
| **shopflow-workload** | 10.0.10.0/24, 10.0.11.0/24 | 2-4 | t3.medium | E-commerce app |
| **shopflow-platform** | 10.0.12.0/24, 10.0.13.0/24 | 1-2 | t3.medium | Tekton CI + ArgoCD |
| **shopflow-observability** | 10.0.14.0/24, 10.0.15.0/24 | 2-3 | t3.large | OTel, Jaeger, Prometheus, Grafana |

## Deployment Order

```bash
# 1. Shared infrastructure first (VPC + ECR)
cd environments/shared
terraform init && terraform apply

# 2. Then each cluster (can be parallelized)
cd ../workload
terraform init && terraform apply

cd ../platform
terraform init && terraform apply

cd ../observability
terraform init && terraform apply
```

## Configure kubectl

```bash
# Switch between clusters
aws eks update-kubeconfig --region eu-west-1 --name shopflow-workload
aws eks update-kubeconfig --region eu-west-1 --name shopflow-platform
aws eks update-kubeconfig --region eu-west-1 --name shopflow-observability
```

## Tear Down

```bash
# Reverse order: clusters first, shared last
cd environments/workload && terraform destroy
cd ../platform && terraform destroy
cd ../observability && terraform destroy
cd ../shared && terraform destroy
```
