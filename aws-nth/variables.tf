variable "cluster_name" {
  default = "k8s-demo" # VPC의 CIDR 블록 설정
  type = string
}
variable "accountid" {
  default = "682935334295"
  type = string
}
variable "region" {
  default = "ap-northeast-2"
  type = string
}
variable "queue_name" {
  default = "nth_queue"
  type = string
}
# variable "AWS_ACCESS_KEY_ID" {
#   description = "AWS Access Key Id"
#   type    = string
# }

# variable "AWS_SECRET_ACCESS_KEY" {
#   description = "AWS Secret Access Key"
#   type    = string
# }