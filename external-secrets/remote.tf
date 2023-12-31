# terraform {
#   backend "local" {
#     path = var.state_file_path
#   }
# }

# Using a single workspace:
terraform {
  backend "remote" {
    hostname = "app.terraform.io"
    organization = "odark"

    workspaces {
      name = "external-secrets"
    }
  }
}


