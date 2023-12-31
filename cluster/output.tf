output "endpoint" {
  value = aws_eks_cluster.k8s-demo-cluster.endpoint
}

output "kubeconfig-certificate-authority-data" {
  value = aws_eks_cluster.k8s-demo-cluster.certificate_authority[0].data
}


output "cluster_name" {
  value = aws_eks_cluster.k8s-demo-cluster.name
}

output "node-role" {
  value = aws_iam_role.node-role.arn
}

output "autoscaling_name" {
  value = aws_autoscaling_group.k8s-demo-asg.name
}

output "k8s-demo-oidc" {
  value = aws_iam_openid_connect_provider.k8s-demo-oidc.arn
}