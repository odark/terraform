provider "aws" {
  region = "ap-northeast-2"
}

provider "helm" {
  kubernetes {
    host                   =  data.aws_eks_cluster.example.endpoint
    cluster_ca_certificate =  base64decode(data.aws_eks_cluster.example.certificate_authority[0].data)
    token                  =  data.aws_eks_cluster_auth.example.token 
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.example.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.example.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.example.token
}

data "aws_eks_cluster" "example" {
  name = data.terraform_remote_state.test.outputs.cluster_name
}
data "aws_eks_cluster_auth" "example" {
  name = data.terraform_remote_state.test.outputs.cluster_name
}

resource "aws_iam_policy" "policy" {
  name        = "alb-policy"
  description = "policy for alb-controller"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = file("${path.module}/iam_policy.json")
}

resource "kubernetes_service_account" "alb_service_account" {
  metadata {
    name = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "attach-policy-arn" = "arn:aws:iam::${var.accountid}:policy/AWSLoadBalancerControllerIAMPolicy"
      "role-name" = "AmazonEKSLoadBalancerControllerRole"
    }
  }
}

resource "helm_release" "example" {
  name        = "aws-load-balancer-controller"
  namespace   = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.6.2"
  create_namespace = true

  set {
    name = "clusterName"
    value = var.cluster_name
  }
  set {
    name = "serviceAccount.create"
    value = false
  }

  set {
    name = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  depends_on = [ 
    aws_iam_policy.policy,
    kubernetes_service_account.alb_service_account
   ]
}