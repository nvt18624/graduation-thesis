data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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

# ── IAM Role for App EC2 instances (ECR pull + SSM) ──────────────────────────

resource "aws_iam_role" "app_ec2" {
  name = "${var.prefix}-app-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-app-ec2-role" }
}

# SSM Agent – required for EventBridge to send Run Command
resource "aws_iam_role_policy_attachment" "app_ec2_ssm" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ECR pull – least privilege: only pull from repos owned by this prefix
resource "aws_iam_policy" "app_ecr_pull" {
  name        = "${var.prefix}-app-ecr-pull"
  description = "Allow app EC2s to pull images from their ECR repos"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRGetToken"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
        ]
        Resource = [for app, repo in aws_ecr_repository.apps : repo.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_ec2_ecr" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = aws_iam_policy.app_ecr_pull.arn
}

resource "aws_iam_instance_profile" "app_ec2" {
  name = "${var.prefix}-app-ec2-profile"
  role = aws_iam_role.app_ec2.name
}

# ── IAM Role for EventBridge to send SSM Run Command ─────────────────────────

resource "aws_iam_role" "eventbridge_ssm" {
  name = "${var.prefix}-eventbridge-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-eventbridge-ssm-role" }
}

resource "aws_iam_role_policy" "eventbridge_ssm" {
  role = aws_iam_role.eventbridge_ssm.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:SendCommand"]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.id}::document/AWS-RunShellScript",
          "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:instance/*",
        ]
      }
    ]
  })
}

# ── EventBridge rule: auto-deploy when ECR image pushed ──────────────────────

resource "aws_cloudwatch_event_rule" "ecr_push" {
  for_each = var.apps

  name        = "${var.prefix}-${each.key}-ecr-push"
  description = "Auto-deploy ${each.key} when a new image is pushed to ECR"

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Action"]
    detail = {
      action-type     = ["PUSH"]
      result          = ["SUCCESS"]
      repository-name = ["${var.prefix}-${each.key}"]
    }
  })

  tags = { App = each.key }
}

resource "aws_cloudwatch_event_target" "ssm_deploy" {
  for_each = var.apps

  rule     = aws_cloudwatch_event_rule.ecr_push[each.key].name
  arn      = "arn:aws:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:document/AWS-RunShellScript"
  role_arn = aws_iam_role.eventbridge_ssm.arn

  run_command_targets {
    key    = "tag:App"
    values = [each.key]
  }

  input_transformer {
    input_paths = {
      image_tag = "$.detail.image-tag"
      repo      = "$.detail.repository-name"
      account   = "$.account"
      region    = "$.region"
    }
    # EventBridge substitutes <variable> at runtime; Terraform interpolates ${...} at plan time
    input_template = <<-TEMPLATE
    {
      "commands": [
        "REGISTRY=<account>.dkr.ecr.<region>.amazonaws.com",
        "IMAGE=$REGISTRY/<repo>:<image_tag>",
        "aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin $REGISTRY",
        "docker pull $IMAGE",
        "docker stop ${each.key} 2>/dev/null || true",
        "docker rm ${each.key} 2>/dev/null || true",
        "docker run -d --name ${each.key} --restart unless-stopped -p ${each.value.app_port}:${each.value.app_port} $IMAGE",
        "echo Deploy ${each.key}:$IMAGE done"
      ]
    }
    TEMPLATE
  }
}
