output "serviceaccount" {
  value = kubernetes_service_account.serviceaccount.id

}

output "redenered_yaml" {
  value = kubectl_manifest.aws-auth-manifest.yaml_body_parsed
}