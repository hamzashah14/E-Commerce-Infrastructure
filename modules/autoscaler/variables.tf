variable "cluster_name" {
  description = "EKS cluster name, also used for node group auto-discovery"
  type        = string
}

variable "region" {
  description = "AWS region of the cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider"
  type        = string
}

variable "oidc_issuer" {
  description = "OIDC issuer URL of the cluster, without the https:// prefix"
  type        = string
}

variable "chart_version" {
  description = "cluster-autoscaler Helm chart version. 9.53.0 ships autoscaler 1.34.2, matching Kubernetes 1.34"
  type        = string
  default     = "9.53.0"
}
