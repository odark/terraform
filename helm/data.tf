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


data "template_file" "aws-auth" {
  template = file("${path.module}/templates/aws_auth.yaml.tpl")

  vars = {
    rolearn   = data.terraform_remote_state.test.outputs.node-role
  }
}