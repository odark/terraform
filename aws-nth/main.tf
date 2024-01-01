provider "aws" {
  region = "ap-northeast-2"
}

# resource "aws_iam_policy" "policy" {
#   name        = "nth-queue-policy"
#   path        = "/"
#   description = "queue for aws node terminate hander"

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [{
#         Effect = "Allow",
#         Principal = {
#             "Service": ["events.amazonaws.com", "sqs.amazonaws.com"]
#         },
#         Action = "sqs:SendMessage",
#         Resource = [
#             "arn:aws:sqs:${var.region}:${var.accountid}:${var.queue_name}"
#         ]
#     }]
#   })
# }

provider "helm" {
  kubernetes {
    host                   =  data.aws_eks_cluster.k8s-demo.endpoint
    cluster_ca_certificate =  base64decode(data.aws_eks_cluster.k8s-demo.certificate_authority[0].data)
    token                  =  data.aws_eks_cluster_auth.k8s-demo.token 
  }
}

resource "aws_sqs_queue" "terraform_queue" {
  name                      = "nth-queue"
  delay_seconds             = 90
  max_message_size          = 2048
  message_retention_seconds = 300
  receive_wait_time_seconds = 10
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.terraform_queue_deadletter.arn
    maxReceiveCount     = 4
  })
#   policy = jsondecode({
#     Statement = [{
#         Effect = "Allow",
#         Principal = {
#             "Service": ["events.amazonaws.com", "sqs.amazonaws.com"]
#         },
#         Action = "sqs:SendMessage",
#         Resource = [
#             "arn:aws:sqs:${var.region}:${var.accountid}:${var.queue_name}"
#         ]
#     }]
#   })
  policy = <<EOF
  {
        "Version": "2012-10-17",
    "Id": "MyQueuePolicy",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {
            "Service": ["events.amazonaws.com", "sqs.amazonaws.com"]
        },
        "Action": "sqs:SendMessage",
        "Resource": [
            "arn:aws:sqs:${var.region}:${var.accountid}:${var.queue_name}"
        ]
    }]
  }
  EOF
  sqs_managed_sse_enabled    = true

  tags = {
    Environment = "production"
  }
}

# resource "aws_sqs_queue" "terraform_queue_deadletter" {
#   name = "terraform-example-deadletter-queue"
#   redrive_allow_policy = jsonencode({
#     redrivePermission = "byQueue",
#     # sourceQueueArns   = [aws_sqs_queue.terraform_queue.arn]
#     sourceQueueArn      = aws_sqs_queue.terraform_queue.arn,
#   })
# }
resource "aws_sqs_queue" "terraform_queue_deadletter" {
  name = "terraform-example-deadletter-queue"
}


resource "aws_autoscaling_lifecycle_hook" "k8s-demo-asg-hook" {
  name                   = "k8s-demo-asg-hook"
  autoscaling_group_name = data.terraform_remote_state.test.outputs.autoscaling_name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 300
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"

  notification_metadata = jsonencode({
    noti = "terminated"
  })

# EventBridge를 사용하지 않고  SQS로 직접 전송하려는 경우 필요
#   notification_target_arn = "arn:aws:sqs:us-east-1:444455556666:queue1*"
#   role_arn                = "arn:aws:iam::123456789012:role/S3Access"
}

resource "aws_cloudwatch_event_rule" "event_rule_1" {
  name        = "k8s-demo-event-rule" 
  description = "Capture each AWS Console Sign In"

  event_pattern = jsonencode({
    source = ["aws.autoscaling"]
    detail-type = [
      "EC2 Instance-terminate Lifecycle Action"
    ]
  })
}

resource "aws_cloudwatch_event_target" "event_rule_target_1" {
  target_id = "1"
  rule      = aws_cloudwatch_event_rule.event_rule_1.name
  arn       = aws_sqs_queue.terraform_queue.arn
}

resource "aws_cloudwatch_event_rule" "event_rule_2" {
  name        = "k8s-demo-event-rule" 
  description = "EC2 Spot Instance Interruption Warning"

  event_pattern = jsonencode({
    source = ["aws.ec2"]
    detail-type = [
      "EC2 Spot Instance Interruption Warning"
    ]
  })
}

resource "aws_cloudwatch_event_target" "event_rule_target_2" {
  target_id = "2"
  rule      = aws_cloudwatch_event_rule.event_rule_2.name
  arn       = aws_sqs_queue.terraform_queue.arn
}

resource "aws_cloudwatch_event_rule" "event_rule_3" {
  name        = "k8s-demo-event-rule" 
  description = "EC2 Instance State-change Notification"

  event_pattern = jsonencode({
    source = ["aws.ec2"]
    detail-type = [
      "EC2 Instance State-change Notification"
    ]
  })
}

resource "aws_cloudwatch_event_target" "event_rule_target_3" {
  target_id = "3"
  rule      = aws_cloudwatch_event_rule.event_rule_3.name
  arn       = aws_sqs_queue.terraform_queue.arn
}

#############################3
resource "aws_iam_policy" "nth-policy" {
  name        = "nth-queue-policy"
  path        = "/"
  description = "queue for aws node terminate hander"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
        Effect = "Allow",
        Action = [
            "autoscaling:CompleteLifecycleAction",
            "autoscaling:DescribeAutoScalingInstances",
            "autoscaling:DescribeTags",
            "ec2:DescribeInstances",
            "sqs:DeleteMessage",
            "sqs:ReceiveMessage"
        ],
        Resource = "*"
    }]
  })
}

resource "helm_release" "example" {
  name        = "aws-node-termination-handler"
  namespace   = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-node-termination-handler"
  version    = "0.21.0"
  create_namespace = true

  set {
    name = "enableSqsTerminationDraining"
    value = "true"
  }
  set {
    name = "queueURL"
    value = "https://sqs.ap-northeast-2.amazonaws.com/${var.accountid}/${var.queue_name}"
  }
}

