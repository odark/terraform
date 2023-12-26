variable "cluster_name" {
  default = "k8s-demo" # VPC의 CIDR 블록 설정
  type = string
}

variable "instance_type" {
 default = "t3.medium"
 type    = string
}

variable "availability_zones" {
  default = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"] # 사용할 가용 영역들
}

variable "extra_tags" {
  default = [
    {
    key                 = "Name"
    value               = "k8s-demo"
    propagate_at_launch = true
    },
    {
    key                 = "kubernetes.io/cluster/k8s-demo"
    value               = "owned"
    propagate_at_launch = true
    },
    {
    key                 = "k8s.io/cluster/k8s-demo"
    value               = "owned"
    propagate_at_launch = true
    }
  ]
}

variable "AWS_ACCESS_KEY_ID" {
  description = "AWS Access Key ID"
}

variable "AWS_SECRET_ACCESS_KEY" {
  description = "AWS Secret Access Key"
}


