terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

locals {
  namespace       = "kube-system"
  service_account = "cluster-autoscaler"
}

# IAM role for the autoscaler's service account (IRSA)

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${local.namespace}:${local.service_account}"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${var.cluster_name}-cluster-autoscaler-irsa"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Read access is unscoped (Describe calls do not support resource-level permissions).
# Scaling actions are limited to ASGs tagged as owned by this cluster.
data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name   = "cluster-autoscaler"
  role   = aws_iam_role.cluster_autoscaler.id
  policy = data.aws_iam_policy_document.cluster_autoscaler.json
}

# Cluster Autoscaler

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  namespace  = local.namespace
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.chart_version

  values = [
    yamlencode({
      cloudProvider = "aws"
      awsRegion     = var.region

      # Finds node groups tagged k8s.io/cluster-autoscaler/enabled and
      # k8s.io/cluster-autoscaler/<cluster_name> (set in modules/eks).
      autoDiscovery = {
        clusterName = var.cluster_name
      }

      rbac = {
        serviceAccount = {
          name = local.service_account
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
          }
        }
      }
    })
  ]

  depends_on = [
    aws_iam_role_policy.cluster_autoscaler
  ]
}
