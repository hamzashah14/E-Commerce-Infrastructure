# Troubleshooting

Known problems with this infrastructure, with the cause and the fix. Application and GitOps issues are in the [E-Commerce-Microservices issues log](https://github.com/hamzashah14/E-Commerce-Microservices/blob/main/docs/ISSUES.md).

## Node group

### Pods fail to schedule: "too many pods"

- **Symptom:** after raising replica counts, new pods stay `Pending` and the scheduler reports it cannot fit them, with the error `too many pods`.
- **Cause:** with the VPC CNI, the number of pods a node can run is limited by the instance type's network interfaces and IP addresses per interface. A `t3.medium` (2 vCPU, 4 GiB) allows 17 pods. The application, Argo CD and the monitoring stack together exceeded that, even before replicas were raised.
- **Fix:** use a larger instance type; a `t3.large` (2 vCPU, 8 GiB) allows 35 pods. The current default is `m7i-flex.large`. Check what your node supports:

```bash
kubectl get nodes -o jsonpath='{.items[*].status.capacity.pods}'
```

If a node is still full, raise `max_size` and `desired_size` in `terraform.tfvars`.

### `disk_size` and `capacity_type` in `terraform.tfvars` had no effect

- **Symptom:** `terraform.tfvars` sets `disk_size = 30`, but the node group would be created with a 20 GiB disk.
- **Cause:** both variables were declared and set at the root, but `main.tf` did not pass them to `module "eks"`, so the module's defaults (20 GiB, `ON_DEMAND`) applied without any error.
- **Fix:** `capacity_type = var.capacity_type` and `disk_size = var.disk_size` are now passed in the `eks` module block. Lesson: when a root variable has no effect, check that it is wired into the module call.

## Storage

### PersistentVolumeClaim cannot attach an EBS volume

- **Symptom:** the PostgreSQL pod waits for its volume; events show a permission error from the EBS CSI driver.
- **Cause:** the EBS CSI driver needs its own IAM permissions. Policies on the node role are not enough on EKS, and the driver must receive them through an IAM role for its service account (IRSA).
- **Fix:** `modules/eks` creates the cluster's OIDC provider, an IAM role trusted by `system:serviceaccount:kube-system:ebs-csi-controller-sa` with `AmazonEBSCSIDriverPolicy`, and installs the `aws-ebs-csi-driver` add-on with that role.
