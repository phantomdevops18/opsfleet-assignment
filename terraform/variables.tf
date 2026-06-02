variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "innovate-poc"
}

variable "cluster_version" {
  type    = string
  default = "1.33"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "karpenter_chart_version" {
  type    = string
  default = "1.0.6"
}

variable "tags" {
  type = map(string)
  default = {
    Project   = "innovate-poc"
    ManagedBy = "terraform"
  }
}
