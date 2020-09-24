provider "aws" {
}

locals {
  block_not_user2 = false
  allow_user2     = false
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "bucket" {
  force_destroy = "true"
}

resource "aws_s3_bucket_object" "object" {
  key     = "text.txt"
  content = "Hello world!"
  bucket  = aws_s3_bucket.bucket.bucket
}

resource "aws_s3_bucket_object" "tagged_object" {
  key     = "tagged.txt"
  content = "Hello world!"
  bucket  = aws_s3_bucket.bucket.bucket
  tags = {
    access = "secret"
  }
}

resource "aws_s3_bucket_object" "tagged_object2" {
  key     = "tagged2.txt"
  content = "Hello world!"
  bucket  = aws_s3_bucket.bucket.bucket
  tags = {
    access = "restricted"
  }
}

# this data source and the local variable contains the terraform user/role's principal
data "aws_arn" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  currentArn = length(regexall("^assumed-role", data.aws_arn.current.resource)) > 0 ? "arn:${data.aws_arn.current.partition}:iam::${data.aws_arn.current.account}:role/${regex("^[^/]*/([^/]*)/", data.aws_arn.current.resource)[0]}" : data.aws_caller_identity.current.arn
}

data "aws_iam_policy_document" "bucket_policy_document" {
  dynamic "statement" {
    for_each = local.block_not_user2 ? [1] : []
    content {
      effect    = "Deny"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.bucket.arn}/${aws_s3_bucket_object.object.key}"]
      not_principals {
        type        = "AWS"
        identifiers = [aws_iam_user.user2.arn]
      }
      # make sure the terraform principal is exempt to avoid Forbidden errors during terraform plan
      condition {
        test     = "StringNotLike"
        variable = "aws:PrincipalArn"
        values   = [local.currentArn]
      }
    }
  }
  dynamic "statement" {
    for_each = local.allow_user2 ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.bucket.arn}/${aws_s3_bucket_object.object.key}"]
      principals {
        type        = "AWS"
        identifiers = [aws_iam_user.user2.arn]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  count  = data.aws_iam_policy_document.bucket_policy_document.statement != null ? 1 : 0
  bucket = aws_s3_bucket.bucket.bucket

  policy = data.aws_iam_policy_document.bucket_policy_document.json
}

resource "random_id" "id" {
  byte_length = 8
}

resource "aws_iam_user" "user1" {
  name = "user1-${random_id.id.hex}"
  tags = {
    access = "restricted"
  }
}

resource "aws_iam_access_key" "user1_ak" {
  user = aws_iam_user.user1.name
}

resource "aws_iam_user_policy" "user1_policy" {
  user = aws_iam_user.user1.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.bucket.arn}/${aws_s3_bucket_object.object.key}"
    },
    {
      "Action": [
        "sts:AssumeRole"
      ],
      "Effect": "Allow",
      "Resource": "${aws_iam_role.role.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_group" "tag_based_access_group" {
  name = "group-${random_id.id.hex}"
}

resource "aws_iam_group_policy" "group_policy" {
  group = aws_iam_group.tag_based_access_group.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
		{
      "Action": [
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.bucket.arn}/*",
			"Condition": {"StringEquals": {"s3:ExistingObjectTag/access": "$${aws:PrincipalTag/access}"}}

		}
  ]
}
EOF
}

resource "aws_iam_group_membership" "team" {
  name = aws_iam_group.tag_based_access_group.name

  users = [
    aws_iam_user.user1.name,
  ]

  group = aws_iam_group.tag_based_access_group.name
}

output "user1_access_key_id" {
  value = aws_iam_access_key.user1_ak.id
}

output "user1_secret_access_key" {
  value = aws_iam_access_key.user1_ak.secret
}

resource "aws_iam_user" "user2" {
  name = "user2-${random_id.id.hex}"
}

resource "aws_iam_user_policy" "user2_policy" {
  user = aws_iam_user.user2.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.bucket.arn}/*",
			"Condition": {"StringEquals": {"s3:ExistingObjectTag/access": "secret"}}
    }
  ]
}
EOF
}

resource "aws_iam_access_key" "user2_ak" {
  user = aws_iam_user.user2.name
}

output "user2_access_key_id" {
  value = aws_iam_access_key.user2_ak.id
}

output "user2_secret_access_key" {
  value = aws_iam_access_key.user2_ak.secret
}

output "bucket" {
  value = aws_s3_bucket.bucket.bucket
}

output "key" {
  value = aws_s3_bucket_object.object.key
}

output "tagged_key" {
  value = aws_s3_bucket_object.tagged_object.key
}

output "tagged_key2" {
  value = aws_s3_bucket_object.tagged_object2.key
}

data "aws_iam_policy_document" "assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "role" {
  assume_role_policy = data.aws_iam_policy_document.assume-role-policy.json
}

output "role" {
  value = aws_iam_role.role.arn
}
