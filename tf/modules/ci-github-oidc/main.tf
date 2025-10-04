resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "GitHubOIDCAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Lock to a single repo + branch (pushes to that branch)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.repo_sub]
    }

    # Examples if you later want to allow more (uncomment & adjust):
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/tags/*",
        "repo:${var.github_owner}/${var.github_repo}:pull_request",
        "repo:${var.github_owner}/${var.github_repo}:environment:prod"
      ]
    }
  }
}

data "aws_iam_policy_document" "deploy_policy" {
  statement {
    sid     = "S3ListBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.bucket_arn]
    # If prefix specified, scope ListBucket to that prefix
    condition {
      test     = "StringEqualsIfExists"
      variable = "s3:prefix"
      values   = [var.s3_key_prefix]
    }
  }

  statement {
    sid     = "S3ObjectRW"
    effect  = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:AbortMultipartUpload",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts"
    ]
    resources = [local.bucket_objs]
  }

  # CloudFront invalidation (optional)
  dynamic "statement" {
    for_each = var.cloudfront_arn == null ? [] : [1]
    content {
      sid     = "CloudFrontInvalidate"
      effect  = "Allow"
      actions = [
        "cloudfront:CreateInvalidation",
        "cloudfront:GetInvalidation"
      ]
      resources = [var.cloudfront_arn]
    }
  }
}

resource "aws_iam_policy" "deploy" {
  name        = "GithubActionsS3DeployPolicy"
  description = "Allow S3 sync to site bucket and optional CloudFront invalidation"
  policy      = data.aws_iam_policy_document.deploy_policy.json
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = "GithubActionsDeployRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags = {
    ManagedBy = "Terraform"
    Purpose   = "GitHubActionsDeploy"
  }
}

resource "aws_iam_role_policy_attachment" "attach_deploy" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.deploy.arn
}