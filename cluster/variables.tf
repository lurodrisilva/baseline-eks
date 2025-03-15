# variable "environment" {
#   description = "Environment for deployment"
#   type        = string
#   default     = "prod"
# }

variable "tag" {
  description = "Tag for resources"
  type        = string
  default     = "eks-cluster-baseline"
}

variable "nodegroup_name" {
  description = "Nodegroup name for control plane"
  type        = string
  default     = "eks-cluster-baseline-ng"
}

variable "cluster_name" {
  description = "Custom Cluster Name"
  type        = string
  default     = "eks-cluster-baseline"
}

variable "vpc_name" {
  description = "Custom VPC Name"
  type        = string
  default     = "eks-cluster-baseline-vpc"
}

variable "private_subnets_cidr" {
    description = "Custom VPC Private subnet CIDR Blocks"
    type = list
    default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "vpc_cidr_block" {
    description = "Custom VPC Public subnet CIDR Blocks"
    type = string
    default = "10.1.0.0/16"
}

# variable "public_subnets" {
#     description = "Custom VPC Public subnet CIDR Blocks"
#     type = list
#     default = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24", "10.0.12.0/24", "10.0.11.0/24", "10.0.10.0/24"]
# }

variable "region" {
  description = "Region to deploy the resources"
  type        = string
  default     = "us-east-1"
}