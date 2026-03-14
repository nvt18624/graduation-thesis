resource "aws_ecr_repository" "apps" {
  for_each = var.apps

  name                 = "${var.prefix}-${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.prefix}-${each.key}"
    App  = each.key
  }
}

resource "aws_ecr_lifecycle_policy" "apps" {
  for_each   = var.apps
  repository = aws_ecr_repository.apps[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged image after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "keep maximum 20 image"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ── IAM User for developer ───────────────────────────────────────────────
resource "aws_iam_user" "devs" {
  for_each = var.users

  name = each.key
  path = "/cicd/"

  tags = {
    Name      = each.key
    ManagedBy = "terraform"
    Role      = "cicd-user"
  }
}

# Access key (admin take this output to dev user)
resource "aws_iam_access_key" "devs" {
  for_each = var.users
  user     = aws_iam_user.devs[each.key].name
}

# ── Policy per user  ────────────────
data "aws_iam_policy_document" "user_policy" {
  for_each = var.users

  statement {
    sid       = "ECRGetToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushAllowedApps"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
    ]

    resources = [
      for app in each.value.allowed_apps :
      aws_ecr_repository.apps[app].arn
    ]
  }

  statement {
    sid    = "SSMSendCommand"
    effect = "Allow"
    actions = [
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
    ]
    resources = ["arn:aws:ec2:*:*:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/App"
      values   = each.value.allowed_apps
    }
  }

  statement {
    sid    = "SSMRunCommandDoc"
    effect = "Allow"
    actions = [
      "ssm:SendCommand",
    ]
    resources = ["arn:aws:ssm:*:*:document/AWS-RunShellScript"]
  }

  statement {
    sid    = "EC2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/App"
      values   = each.value.allowed_apps
    }
  }
}

resource "aws_iam_policy" "user_policy" {
  for_each = var.users

  name        = "${var.prefix}-${each.key}-policy"
  description = "Least privilege: ${each.key} chỉ deploy được apps: ${join(", ", each.value.allowed_apps)}"
  policy      = data.aws_iam_policy_document.user_policy[each.key].json

  tags = {
    User      = each.key
    AllowedApps = join(",", each.value.allowed_apps)
  }
}

resource "aws_iam_user_policy_attachment" "devs" {
  for_each = var.users

  user       = aws_iam_user.devs[each.key].name
  policy_arn = aws_iam_policy.user_policy[each.key].arn
}

resource "aws_security_group" "apps" {
  for_each = var.apps

  name        = "${var.prefix}-sg-${each.key}"
  description = "SG for app ${each.key}: on allow port ${each.value.app_port} from internal VPC"
  vpc_id      = var.vpc_id

  ingress {
    description = "App port from internal VPC"
    from_port   = each.value.app_port
    to_port     = each.value.app_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}-sg-${each.key}"
    App  = each.key
  }
}
