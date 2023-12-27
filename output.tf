output "endpoint" {
  value = aws_eks_cluster.k8s-demo-cluster.endpoint
}

output "kubeconfig-certificate-authority-data" {
  value = aws_eks_cluster.k8s-demo-cluster.certificate_authority[0].data
}


output "cluster_name" {
  value = aws_eks_cluster.k8s-demo-cluster.name
}


output "rendered_file" {
  value = data.template_file.aws-auth.rendered
  description = "aws-auth yaml create"
}