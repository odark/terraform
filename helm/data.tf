data "terraform_remote_state" "test" {
  backend = "remote"

  config = {
    organization = "odark"
    hostname = "app.terraform.io"
    workspaces = {
      name = "test"
    }
  }
}
