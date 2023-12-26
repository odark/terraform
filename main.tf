terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.30.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
  profile = "default"
}

###################################
#VPC 설정
###################################
resource "aws_vpc" "k8s-vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    "Name" = "k8s-demo-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "k8s-subnet" {
  #count = length(var.availability_zones)
  count = 3
  vpc_id     = aws_vpc.k8s-vpc.id
  cidr_block = "10.0.${count.index * 10 + 1}.0/24"
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    "Name" = "${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.k8s-vpc.id

  tags = {
    Name = "k8s-demo-gw"
  }
}


resource "aws_route_table" "local-route" {
  vpc_id = aws_vpc.k8s-vpc.id

  # since this is exactly the route AWS will create, the route will be adopted
  route {
    cidr_block = aws_vpc.k8s-vpc.cidr_block
    gateway_id = "local"
  }
}

resource "aws_route_table" "gw-route" {
	vpc_id = aws_vpc.k8s-vpc.id

	route {
		cidr_block = "0.0.0.0/0"
		gateway_id = aws_internet_gateway.gw.id
	}
}

# resource "aws_route_table_association" "rta" {
#   count = length(var.availability_zones)
#   route_table_id = aws_route_table.local-route.id
#   subnet_id = aws_subnet.k8s-subnet[count.index].id
# }

#######################################
#EKS IAM Role
#######################################
data "aws_iam_policy_document" "eks-assume-role-doc" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks-role" {
  name               = "k8s-demo-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks-assume-role-doc.json
}

resource "aws_iam_role_policy_attachment" "cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks-role.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks-role.name
}

# Optionally, enable Security Groups for Pods
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html
resource "aws_iam_role_policy_attachment" "cluster-AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks-role.name
}

resource "aws_security_group" "eks" {
	name = "k8s-demo-sg"
	description = "Cluster communication with worker nodes"
	vpc_id = aws_vpc.k8s-vpc.id

	# egress {
	# 	from_port = 0
	# 	to_port = 0
	# 	protocol = "-1"
	# 	cidr_blocks = ["0.0.0.0/0"]
	# }

    # ingress {
    #     from_port   = 0
    #     to_port     = 0
    #     protocol    = "-1"  # 모든 프로토콜
    #     self        = true  # 자기 자신의 보안 그룹
    # }
    tags = {
		Name = "k8s-demo-eks"
	}
	
}

#EKS cluster
resource "aws_eks_cluster" "k8s-demo-cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks-role.arn

  vpc_config {
    security_group_ids = [aws_security_group.eks.id]
    #subnet_ids = [aws_subnet.example1.id, aws_subnet.example2.id]    
    subnet_ids = aws_subnet.k8s-subnet[*].id
    endpoint_public_access = true
	  endpoint_private_access = true
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.cluster-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSServicePolicy,
    aws_iam_role_policy_attachment.cluster-AmazonEKSVPCResourceController,
  ]
}

# ################################
# #EKS Nodegrouup IAM Role
# 노드가 아래 권한이 있어야 노드로써 역할을 할수 있는것이다. 그러기위해 aws_auth 또한 필요함.
# ###############################
resource "aws_iam_role" "node-role" {
  name = "eks-node-group-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "node-role-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node-role.name
}

resource "aws_iam_role_policy_attachment" "node-role-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node-role.name
}

resource "aws_iam_role_policy_attachment" "node-role-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node-role.name
}

resource "aws_iam_instance_profile" "worker" {
	name = "k8s-demo-node-profile"
	role = aws_iam_role.node-role.name
}

#woker sg
resource "aws_security_group" "worker" {
  name        = "kuberkuber-worker"
  description = "Security group for all nodes in the cluster"
  vpc_id      = aws_vpc.k8s-vpc.id



  # ingress {
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]  # 현재는 모든 소스 IP 주소에서 SSH 접속 허용
  #   description = "Allow SSH access from anywhere"
  # }

  tags = {
    "Name" = "k8s-demo-node"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_security_group_rule" "cluster_https_worker_ingress" {
  description              = "Allow pods to communicate with the EKS cluster API."
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks.id
  source_security_group_id = aws_security_group.worker.id
  from_port                = 443
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_security_group_rule" "eks_cluster_ingress_node_https" {
  description              = "Allow pods running extension API servers on port 443 to receive communication from cluster control plane."
  protocol                 = "tcp"
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.eks.id
  from_port                = 443
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_security_group_rule" "worker_egress_internet" {
  description       = "Allow nodes all egress to the Internet."
  protocol          = "-1"
  security_group_id = aws_security_group.worker.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 0
  type              = "egress"
}



resource "aws_security_group_rule" "workers_ingress_self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.worker.id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "worker_ingress_cluster" {
  description              = "Allow worker pods to receive communication from the cluster control plane."
  protocol                 = "tcp"
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.eks.id
  from_port                = 1025
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "worker_ingress_cluster_kubelet" {
  description              = "Allow worker Kubelets to receive communication from the cluster control plane."
  protocol                 = "tcp"
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.eks.id
  from_port                = 10250
  to_port                  = 10250
  type                     = "ingress"
}

############################################
# LaunchConfiguration
############################################
data "aws_ami" "worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.k8s-demo-cluster.version}-v*"]
  }

  most_recent = true
  owners      = ["682935334295"]
}

locals {
  eks_worker_userdata = <<USERDATA
#!/bin/bash
set -ex
/etc/eks/bootstrap.sh '${var.cluster_name}' --b64-cluster-ca '${aws_eks_cluster.k8s-demo-cluster.certificate_authority.0.data}' --apiserver-endpoint '${aws_eks_cluster.k8s-demo-cluster.endpoint}' --container-runtime containerd --kubelet-extra-args ' --container-log-max-files=10 --container-log-max-size=100Mi --node-labels=node.kubernetes.io/instancegroup=application-test'
USERDATA
}

resource "aws_launch_configuration" "k8s-demo-ami" {
  name_prefix   = "k8s-demo-example-"
  #image_id      = data.aws_ami.worker.id
  image_id = "ami-07cc8400108193157"
  #image_id = "ami-0426898ee4f233052"
  instance_type = "t3.medium"
  iam_instance_profile = aws_iam_instance_profile.worker.name
  security_groups             = [aws_security_group.worker.id]
  user_data_base64            = base64encode(local.eks_worker_userdata)
  key_name = "bastion_odark"
  associate_public_ip_address = true

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "k8s-demo-asg" {
  name                 = "k8s-demo-asg-example"
  launch_configuration = aws_launch_configuration.k8s-demo-ami.name
  min_size             = 1
  max_size             = 3
  desired_capacity   = 3
  vpc_zone_identifier  = aws_subnet.k8s-subnet[*].id
  

  lifecycle {
    create_before_destroy = true
  }

  # (Optional) 스케일링 정책, 보안 그룹, 태그 등의 추가 설정 가능

  dynamic "tag" {
    for_each = var.extra_tags
    content {
      key                 = tag.value.key
      value               = tag.value.value
      propagate_at_launch = tag.value.propagate_at_launch
    }
  }

  # tag {
  #   key                 = "Name"
  #   value               = "${var.cluster_name}-test"
  #   propagate_at_launch = true
  # }

  # tag {
  #   key                 = "kubernetes.io/cluster/${var.cluster_name}"
  #   value               = "owned"
  #   propagate_at_launch = true
  # }

  # tag {
  #   key                 = "k8s.io/cluster/${var.cluster_name}"
  #   value               = "owned"
  #   propagate_at_launch = true
  # }
}

#########################################
# aws-auth 생성
###########################################
resource "local_file" "aws-auth" {
  content  = data.template_file.aws-auth.rendered
  filename = "${path.cwd}/.output/aws_auth.yaml"
}

################################################################################
# Route
# IGW로 전체 트래픽이 가도록 Default Routing Table CIDR 수정 및 명시적 서브넷 설정
# Default Routing table ID 획득
#################################################################################
locals {
  default_route_table_id = aws_vpc.k8s-vpc.default_route_table_id
}

resource "aws_route" "default-rt-to-igw" {
  route_table_id = local.default_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id
}

# 명시적 서브넷 설정
# resource "aws_route_table_association" "public-subnet" {
#   count = length(aws_subnet.k8s-subnet)
#   subnet_id = aws_subnet.k8s-subnet[count.index].id
#   route_table_id = local.default_route_table_id
# }

########################################
# helm repo
########################################
# data "aws_eks_cluster_auth" "example" {
#   name = aws_eks_cluster.k8s-demo-cluster.name
# }

# provider "kubernetes" {
#   config_path = "~/.kube/config" # 적절한 경로로 변경하세요
# }

# resource "local_file" "kubeconfig" {
#   filename = "~/.kube/config" # 적절한 경로로 변경하세요
#   content = data.aws_eks_cluster_auth.example.kubeconfig[0].data
# }

# provider "kubernetes" {
#   host                   = aws_eks_cluster.k8s-demo-cluster.endpoint
#   cluster_ca_certificate = base64decode(aws_eks_cluster.k8s-demo-cluster.certificate_authority.0.data)
#   exec {
#     api_version = "client.authentication.k8s.io/v1alpha1"
#     command     = "aws"
#     args = [
#       "eks",
#       "get-token",
#       "--cluster-name",
#       aws_eks_cluster.k8s-demo-cluster.name
#     ]
#   }
# }

data "aws_eks_cluster" "example" {
  name = aws_eks_cluster.k8s-demo-cluster.name
}
data "aws_eks_cluster_auth" "example" {
  name = aws_eks_cluster.k8s-demo-cluster.name
}



# data "aws_iam_policy_document" "external-secret-role-doc" {
#   statement {
#     actions = [
#       "secretsmanager:GetResourcePolicy",
#       "secretsmanager:GetSecretValue",
#       "secretsmanager:DescribeSecret",
#       "secretsmanager:ListSecretVersionIds"
#     ]
#     resources = ["arn:aws:secretsmanager:ap-northeast-2:*:secret:*",]
#     effect = "Allow"
#   }
# }



#-------------------------------
data "aws_iam_policy_document" "external-secret-role-doc" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds"
    ]
    resources = ["arn:aws:secretsmanager:ap-northeast-2:*:secret:*"]
    
  }
}

resource "aws_iam_policy" "external-secret-policy" {
  name        = "external-secret-test"
  policy      = data.aws_iam_policy_document.external-secret-role-doc.json
}

# resource "aws_iam_role" "external-secret-role" {
#   name               = "external-secret-test"
#   #assume_role_policy = data.aws_iam_policy_document.external-secret-role-doc.json
#   #assume_role_policy = aws_iam_policy.external-secret-policy.policy
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Sid    = ""
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         }
#       },
#     ]
#   })
#   #Attach the policy
#   inline_policy {
#     policy = jsonencode(aws_iam_policy.external-secret-policy.policy)
#   }
# }

#------------------------------

# data "aws_iam_policy" "external-secret-policy" {
#   name = "external-secret-test"
# }

# resource "aws_iam_role" "external-secret-role" {
#   name               = "external-secret-test"
#   #assume_role_policy = data.aws_iam_policy_document.external-secret-role-doc.json
#   assume_role_policy = data.aws_iam_policy.external-secret-policy.policy
# }


resource "aws_iam_openid_connect_provider" "k8s-demo-oidc" {
  client_id_list     = ["sts.amazonaws.com"]
  thumbprint_list    = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
  url                = aws_eks_cluster.k8s-demo-cluster.identity[0].oidc[0].issuer
}

locals {
  find_index = "${length(regexall("/", aws_iam_openid_connect_provider.k8s-demo-oidc.arn)) > 0 ? index(split("", aws_iam_openid_connect_provider.k8s-demo-oidc.arn), "/") : -1}"

  oidc_substr = substr(aws_iam_openid_connect_provider.k8s-demo-oidc.arn, local.find_index + 1, -1)
}


resource "aws_iam_role" "external-secret-role" {
  name = "external-secret-test"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity",
        Effect = "Allow",
        Principal = {
          Federated = aws_iam_openid_connect_provider.k8s-demo-oidc.arn
        },
        Condition = {
          StringEquals = {
              "${local.oidc_substr}:sub": "system:serviceaccount:external-secrets:aws-test-manager"
          }
        }
      }
    ]
  })

}

resource "aws_iam_role_policy_attachment" "external-secret-policy-attach" {
  role       = aws_iam_role.external-secret-role.name
  policy_arn = aws_iam_policy.external-secret-policy.arn
}