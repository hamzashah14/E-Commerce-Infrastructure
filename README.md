# E-Commerce Infrastructure

Terraform for the AWS platform that runs the [E-Commerce-Microservices](https://github.com/hamzashah14/E-Commerce-Microservices) project: network, Kubernetes cluster, container registries and the in-cluster GitOps and monitoring tooling. This is a DevOps learning project, sized for a demo and cheap to tear down.

## What it creates

| Resource | Details |
|----------|---------|
| VPC `EKS-Demo-VPC` | `10.1.0.0/16`, DNS support and hostnames enabled, one internet gateway |
| Subnets | 3 public subnets (`10.1.1.0/24`, `10.1.2.0/24`, `10.1.3.0/24`) in `us-east-1a`, `us-east-1b`, `us-east-1c`, one shared public route table; tagged for EKS and load balancers |
| EKS cluster `eks-cluster` | Kubernetes `1.34`, public API endpoint, IAM role with `AmazonEKSClusterPolicy`, OIDC provider |
| Managed node group `eks-node-group` | `m7i-flex.large`, ON_DEMAND, 2 desired / 2 min / 6 max, 30 GiB disks, tagged for Cluster Autoscaler discovery; node role with `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` |
| EBS CSI driver | EKS add-on `aws-ebs-csi-driver` with an IAM role for service accounts (IRSA, `AmazonEBSCSIDriverPolicy`), so PersistentVolumeClaims can attach EBS volumes |
| ECR repositories | 7: `frontend`, `gateway`, `auth`, `order-service`, `orders`, `product-service`, `user-service`. Scan on push, mutable tags, `force_delete` enabled |
| metrics-server | EKS add-on `metrics-server`, so HorizontalPodAutoscalers can read CPU and memory metrics |
| Cluster Autoscaler | Helm chart `cluster-autoscaler` 9.53.0 (autoscaler 1.34.2) in `kube-system`, with an IRSA role limited to Auto Scaling groups tagged `k8s.io/cluster-autoscaler/eks-cluster = owned`; scales the node group between its min and max |
| Argo CD | Helm chart `argo-cd` 6.7.0 in namespace `argocd`; Service type `ClusterIP`, `server.insecure = true` (plain HTTP behind a port-forward) |
| Prometheus and Grafana | Helm chart `kube-prometheus-stack` 56.21.0 in namespace `monitoring`; Grafana, Prometheus and Alertmanager Services are `ClusterIP` |

The Argo CD and monitoring Helm releases are defined in `modules/argocd`, which owns both the `argocd` and `monitoring` namespaces. The Cluster Autoscaler release and its IAM role are in `modules/autoscaler`.

## Architecture

```
                       VPC  EKS-Demo-VPC  10.1.0.0/16
 ┌───────────────────────────────────────────────────────────────────┐
 │  10.1.1.0/24          10.1.2.0/24          10.1.3.0/24             │
 │  us-east-1a           us-east-1b           us-east-1c   (public)   │
 │      └─────────── EKS node group (m7i-flex.large, 1-2 nodes) ──┘   │
 │                                                                    │
 │  Internet gateway ◀── 0.0.0.0/0 ── public route table              │
 └───────────────────────────────────────────────────────────────────┘

 EKS control plane  eks-cluster (1.34)            ECR  7 repositories
 Helm in cluster    argocd  ·  monitoring (kube-prometheus-stack)
```

## Repository layout

```
.
├── main.tf               wires the modules and the Kubernetes / Helm providers
├── variables.tf          root input variables
├── terraform.tfvars      values used for this deployment
├── outputs.tf            cluster_name, cluster_endpoint, ecr_urls
├── provider.tf           Terraform and AWS provider requirements
├── .terraform.lock.hcl   pinned provider versions
├── modules/
│   ├── vpc/              VPC, subnets, internet gateway, route table
│   ├── eks/              cluster, node group, OIDC, EBS CSI and metrics-server add-ons, IRSA role
│   ├── autoscaler/       Cluster Autoscaler: IRSA role, policy and Helm release
│   ├── ecr/              one repository per name in var.repositories
│   └── argocd/           Argo CD and kube-prometheus-stack Helm releases
└── docs/ISSUES.md        problems met and how they were fixed
```

Pinned providers: `aws` 5.100.0, `kubernetes` 3.0.1, `helm` 3.1.1, `tls` 4.2.1.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) 1.5 or newer
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) with credentials that can create VPC, EKS, IAM and ECR resources
- kubectl, to use the cluster afterwards

```bash
aws configure                    # access key, secret, region us-east-1, output json
aws sts get-caller-identity      # must return your account
```

## Usage

```bash
git clone https://github.com/hamzashah14/E-Commerce-Infrastructure.git
cd E-Commerce-Infrastructure

terraform init
terraform plan          # review what will be created
terraform apply
```

Provisioning takes roughly 15 minutes; the EKS control plane and node group take the longest. The Kubernetes and Helm providers authenticate with a token from `aws_eks_cluster_auth`, so no local kubeconfig is needed during the apply.

Connect kubectl when it finishes:

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-cluster
kubectl get nodes
kubectl get pods -n argocd
kubectl get pods -n monitoring
```

## Configuration

Set in `terraform.tfvars`:

| Variable | Type | Value | Meaning |
|----------|------|-------|---------|
| `region` | string | `us-east-1` | AWS region |
| `vpc_name` | string | `EKS-Demo-VPC` | VPC name tag |
| `vpc_cidr` | string | `10.1.0.0/16` | VPC CIDR |
| `subnets` | list(object) | 3 entries | name, CIDR and availability zone of each public subnet |
| `cluster_name` | string | `eks-cluster` | EKS cluster name, also used in subnet tags and IAM role names |
| `node_group_name` | string | `eks-node-group` | managed node group name |
| `instance_types` | list(string) | `["m7i-flex.large"]` | worker instance types |
| `capacity_type` | string | `ON_DEMAND` | `ON_DEMAND` or `SPOT` |
| `desired_size`, `min_size`, `max_size` | number | 2, 2, 6 | node group scaling; `desired_size` is only the starting value, Cluster Autoscaler changes it afterwards and Terraform ignores that drift |
| `disk_size` | number | `30` | node disk size in GiB |
| `repositories` | list(string) | 7 names | ECR repositories to create |

## Outputs

| Output | Use |
|--------|-----|
| `cluster_name` | `aws eks update-kubeconfig --name` |
| `cluster_endpoint` | EKS API server endpoint |
| `ecr_urls` | repository URLs; the account ID in them is the `AWS_ACCOUNT_ID` GitHub secret |

## Hand-off to the application repository

1. `terraform output ecr_urls` shows the registry URLs (`<account-id>.dkr.ecr.us-east-1.amazonaws.com/<name>`).
2. Add the GitHub Actions secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` and `AWS_ACCOUNT_ID` to the application repository.
3. Follow the [deployment guide](https://github.com/hamzashah14/E-Commerce-Microservices/blob/main/docs/deployment-guide.md) to build the images, register the Argo CD application and load the database.

## Cost and cleanup

The EKS control plane, the EC2 nodes (two at minimum, up to six under load) and the EBS volumes are billed while they exist. Destroy the stack when you are done.

Delete the workloads first, so the EBS volume behind the database claim and any load balancers are released before Terraform removes the cluster:

```bash
kubectl delete namespace ecommerce
terraform destroy
```

ECR repositories are created with `force_delete = true`, so their images are deleted with them.

## Known limitations

- Public subnets only: nodes get public IPs, and there are no private subnets or NAT gateway.
- The EKS API endpoint is public; private access is disabled.
- State is local (no `backend` block). Add an S3 backend with locking before sharing this with others.
- No AWS Load Balancer Controller is installed; services are reached through `kubectl port-forward`.
- The node role has no CloudWatch Logs permission, so the optional Fluent Bit log forwarding needs one attached by hand.
- ECR tags are mutable.

## Documentation

- [docs/ISSUES.md](docs/ISSUES.md): known problems with causes and fixes
- [E-Commerce-Microservices](https://github.com/hamzashah14/E-Commerce-Microservices): the application, CI and GitOps manifests that run on this infrastructure
