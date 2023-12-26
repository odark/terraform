terraform {
  backend "remote" {
    hostname = "app.terraform.io"
    organization = "odark"

    workspaces {
      name = "test"
    }
  }
}