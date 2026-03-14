# ── Trust policy chung cho EC2 ────────────────────────────────────────────────
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ── Elasticsearch IAM Role ────────────────────────────────────────────────────
resource "aws_iam_role" "elasticsearch" {
  name               = "${var.prefix}-elasticsearch-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = { Name = "${var.prefix}-elasticsearch-role" }
}

resource "aws_iam_role_policy_attachment" "elasticsearch_ssm" {
  role       = aws_iam_role.elasticsearch.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "elasticsearch_cloudwatch" {
  role       = aws_iam_role.elasticsearch.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "elasticsearch" {
  name = "${var.prefix}-elasticsearch-profile"
  role = aws_iam_role.elasticsearch.name
}

# ── Kibana IAM Role ───────────────────────────────────────────────────────────
resource "aws_iam_role" "kibana" {
  name               = "${var.prefix}-kibana-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = { Name = "${var.prefix}-kibana-role" }
}

resource "aws_iam_role_policy_attachment" "kibana_ssm" {
  role       = aws_iam_role.kibana.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "kibana_cloudwatch" {
  role       = aws_iam_role.kibana.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "kibana" {
  name = "${var.prefix}-kibana-profile"
  role = aws_iam_role.kibana.name
}

# ── Logstash IAM Role ─────────────────────────────────────────────────────────
resource "aws_iam_role" "logstash" {
  name               = "${var.prefix}-logstash-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = { Name = "${var.prefix}-logstash-role" }
}

resource "aws_iam_role_policy_attachment" "logstash_ssm" {
  role       = aws_iam_role.logstash.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "logstash_cloudwatch" {
  role       = aws_iam_role.logstash.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Logstash-specific: 
resource "aws_iam_policy" "logstash_s3_read" {
  count       = length(var.log_s3_bucket_arns) > 0 ? 1 : 0
  name        = "${var.prefix}-logstash-s3-read"
  description = "Logstash: read-only access to S3 log buckets (least privilege)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = var.log_s3_bucket_arns
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "logstash_s3" {
  count      = length(var.log_s3_bucket_arns) > 0 ? 1 : 0
  role       = aws_iam_role.logstash.name
  policy_arn = aws_iam_policy.logstash_s3_read[0].arn
}

resource "aws_iam_instance_profile" "logstash" {
  name = "${var.prefix}-logstash-profile"
  role = aws_iam_role.logstash.name
}
