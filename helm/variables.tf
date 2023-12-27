variable "cluster_name" {
  default = "k8s-demo" # VPC의 CIDR 블록 설정
  type = string
}

variable "state_file_path" {
  default = "../terraform.tfstate"
}

# variable "AWS_ACCESS_KEY_ID" {
#   description = "AWS Access Key ID"
# }

# variable "AWS_SECRET_ACCESS_KEY" {
#   description = "AWS Secret Access Key"
# }
