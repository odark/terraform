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

