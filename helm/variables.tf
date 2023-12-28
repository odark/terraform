variable "cluster_name" {
  default = "k8s-demo" # VPC의 CIDR 블록 설정
  type = string
}

variable "state_file_path" {
  default = "../terraform.tfstate"
}

