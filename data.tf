data "template_file" "aws-auth" {
  template = file("${path.module}/templates/aws_auth.yaml.tpl")

  vars = {
    rolearn   = aws_iam_role.node-role.arn
  }
}