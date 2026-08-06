{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
        "autoscaling:*",
        "athena:*",
        "cloudtrail:*",
        "cloudwatch:*",
        "cloudfront:*",
        "config:*",
        "datasync:*",
        "dynamodb:*",
        "ec2:*",
        "ecr:*",
        "ecs:*",
        "elasticloadbalancing:*",
        "events:*",
        "glue:*",
        "guardduty:*",
        "kms:*",
        "lambda:*",
        "logs:*",
        "organizations:DescribeOrganization",
        "pipes:*",
        "rolesanywhere:*",
        "route53:*",
        "route53resolver:*",
        "scheduler:*",
        "securityhub:*",
        "ses:*",
        "s3:*",
        "secretsmanager:*",
        "sns:*",
        "sqs:*",
        "ssm:AddTagsToResource",
        "ssm:DeleteParameter",
        "ssm:DescribeParameters",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:ListTagsForResource",
        "ssm:PutParameter",
        "states:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:*"
      ],
      "Resource": [
        "arn:aws:iam::${account_id}:group/${environment}-dr2-custodial-copy",
        "arn:aws:iam::${account_id}:user/${environment}-dr2-custodial-copy",
        "arn:aws:iam::${account_id}:role/${environment}*",
        "arn:aws:iam::${account_id}:role/${environment_title}*",
        "arn:aws:iam::${account_id}:role/org-wiz-access-role",
        "arn:aws:iam::${account_id}:role/aws-service-role*",
        "arn:aws:iam::${account_id}:policy/${environment}*",
        "arn:aws:iam::${account_id}:policy/${environment_title}*",
        "arn:aws:iam::${account_id}:policy/AWSSSO_DAArchivist",
        "arn:aws:iam::${account_id}:instance-profile/${environment}*"
      ]
    },
    {
      "Action": [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutObject"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::mgmt-dp-terraform-state",
        "arn:aws:s3:::mgmt-dp-terraform-state/*"
      ]
    },
    {
      "Action": [
        "s3:DeleteObject"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::mgmt-dp-terraform-state/env:/${environment}/terraform.state.tflock"
      ]
    }
  ]
}
