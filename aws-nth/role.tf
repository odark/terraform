provider "kubernetes" {
  host                   = data.aws_eks_cluster.k8s-demo.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.k8s-demo.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.k8s-demo.token
}

# locals {
#   find_index  = "${length(regexall("/", aws_iam_openid_connect_provider.k8s-demo-oidc.arn)) > 0 ? index(split("", aws_iam_openid_connect_provider.k8s-demo-oidc.arn), "/") : -1}"
#   oidc_substr = substr(aws_iam_openid_connect_provider.k8s-demo-oidc.arn, local.find_index + 1, -1)
# }
locals {
  find_index  = "${length(regexall("/", data.aws_iam_openid_connect_provider.example.arn)) > 0 ? index(split("", data.aws_iam_openid_connect_provider.example.arn), "/") : -1}"
  oidc_substr = substr(data.aws_iam_openid_connect_provider.example.arn, local.find_index + 1, -1)
}

data "aws_eks_cluster" "k8s-demo" {
  name = data.terraform_remote_state.test.outputs.cluster_name
}
data "aws_eks_cluster_auth" "k8s-demo" {
  name = data.terraform_remote_state.test.outputs.cluster_name
}

# resource "aws_iam_openid_connect_provider" "k8s-demo-oidc" {
#   client_id_list     = ["sts.amazonaws.com"]
#   thumbprint_list    = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
#   url                = data.aws_eks_cluster.k8s-demo.identity[0].oidc[0].issuer
# }

data "aws_iam_openid_connect_provider" "example" {
  arn = data.terraform_remote_state.test.outputs.k8s-demo-oidc
}

resource "aws_iam_policy" "policy" {
  name        = "htn_policy"
  path        = "/"
  description = "IAM Policy for aws-node-termination-handler Deployment:"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
            "autoscaling:CompleteLifecycleAction",
            "autoscaling:DescribeAutoScalingInstances",
            "autoscaling:DescribeTags",
            "ec2:DescribeInstances",
            "sqs:DeleteMessage",
            "sqs:ReceiveMessage"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "nth-role" {
  name = "external-secret-test"

  assume_role_policy = jsonencode({
    Version    = "2012-10-17",
    Statement  = [
      {
        Action = "sts:AssumeRoleWithWebIdentity",
        Effect = "Allow",
        Principal = {
          #Federated = aws_iam_openid_connect_provider.k8s-demo-oidc.arn
          Federated = data.aws_iam_openid_connect_provider.example.arn
        },
        Condition = {
          StringEquals = {
              "${local.oidc_substr}:sub": "system:serviceaccount:kube-system:aws-node-termination-handler-sa",
              "${local.oidc_substr}:aud": "sts.amazonaws.com"
          }
        }
      }
    ]
  })

}

resource "aws_iam_role_policy_attachment" "nth-policy-attach" {
  role       = aws_iam_role.nth-role.name
  policy_arn = aws_iam_policy.policy.arn
}

resource "kubernetes_service_account" "serviceaccount" {
  metadata {
    name        = "aws-node-termination-handler-sa"
    namespace   = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = "arn:aws:iam::${var.accountid}:role/${aws_iam_role.nth-role.name}"
    }
  }

  depends_on = [ 
    aws_iam_role_policy_attachment.nth-policy-attach
  ]
  
}