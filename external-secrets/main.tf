terraform {
  required_version = ">= 0.13"

  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}
provider "aws" {
  region = "ap-northeast-2"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.example.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.example.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.example.token
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.example.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.example.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.example.token
  load_config_file       = false
}

provider "helm" {
  kubernetes {
    host                   =  data.aws_eks_cluster.example.endpoint
    cluster_ca_certificate =  base64decode(data.aws_eks_cluster.example.certificate_authority[0].data)
    token                  =  data.aws_eks_cluster_auth.example.token 
  }
}

data "aws_eks_cluster" "example" {
  name = data.terraform_remote_state.test.outputs.cluster_name
}
data "aws_eks_cluster_auth" "example" {
  name = data.terraform_remote_state.test.outputs.cluster_name
}


##########################################
# 제일먼저 aws-auth 생성
############################################
resource "kubectl_manifest" "aws-auth-manifest" {
  yaml_body = data.template_file.aws-auth.rendered
}

resource "helm_release" "example" {
  name        = "external-secrets"
  namespace   = "external-secrets"
  repository  = "https://charts.external-secrets.io"
  version     = "0.9.10"
  chart       = "external-secrets"
  create_namespace = true

  set {
    name = "installCRDs"
    value = "true"
  }

  depends_on = [
    kubectl_manifest.aws-auth-manifest
  ]
}

resource "kubectl_manifest" "clusterSecretStore" {
  yaml_body = <<YAML
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: test-store
spec:
  provider:
    aws:
      auth:
        jwt:
          serviceAccountRef:
            name: aws-test-manager
            namespace: external-secrets
      region: ap-northeast-2
      service: SecretsManager
YAML

  depends_on = [
    kubernetes_service_account.serviceaccount,
    helm_release.example
  ]
}

resource "kubectl_manifest" "clustersecert" {
      yaml_body = <<YAML
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: example-external-secret
spec:
  secretStoreRef:
    name: test-store
    kind: ClusterSecretStore
  target:
    name: test
    creationPolicy: Owner
    deletionPolicy: Retain
  data:
  - secretKey: username
    remoteRef:
      key: odark-sm
      property: username
  - secretKey: password
    remoteRef:
      key: odark-sm
      property: password 
YAML      
  depends_on = [kubectl_manifest.clusterSecretStore]
}

resource "kubernetes_service_account" "serviceaccount" {
  metadata {
    name        = "aws-test-manager"
    namespace   = "external-secrets"
    annotations = {
      "eks.amazonaws.com/role-arn" = "arn:aws:iam::682935334295:role/external-secret-test"
    }
  }

  depends_on = [ 
    helm_release.example
  ]
  
}