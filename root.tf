locals {
  terraform_state_bucket_name  = "mgmt-dp-terraform-state"
  terraform_role_arns          = jsonencode([module.environment_roles_intg.terraform_role_arn, module.environment_roles_staging.terraform_role_arn, module.environment_roles_prod.terraform_role_arn])
  code_deploy_bucket_name      = "mgmt-dp-code-deploy"
  environments                 = toset(["intg", "staging", "prod"])
  dev_notifications_channel_id = "C052LJASZ08"
  department_terraform_github_environments = [
    "dr2-intg",
    "dr2-staging",
    "dr2-prod",
    "dr2-mgmt"
  ]
  dr2_terraform_repositories = [
    { name : "dr2-ingest@770892421", branch = "*" }
  ]
  dr2_terraform_github_environments = [
    "intg",
    "staging",
    "prod",
    "sbox",
    "mgmt"
  ]
  dr2_code_deploy_repositories  = [{ name : "dr2-ingest@770892421" }]
  dr2_code_deploy_environments  = ["intg", "staging", "prod"]
  dr2_image_deploy_repositories = [{ name : "dr2-custodial-copy@754853041" }]
  environments_roles = {
    intg    = module.environment_roles_intg.terraform_role_arn
    staging = module.environment_roles_staging.terraform_role_arn
    prod    = module.environment_roles_prod.terraform_role_arn
  }
}

module "dr2_terraform_repository_filters" {
  source       = "./github_repository_filters"
  repositories = local.dr2_terraform_repositories
  environments = local.dr2_terraform_github_environments
}

module "dr2_code_deploy_repository_filters" {
  source       = "./github_repository_filters"
  repositories = local.dr2_code_deploy_repositories
  environments = local.dr2_code_deploy_environments
}

module "dr2_image_deploy_repository_filters" {
  source       = "./github_repository_filters"
  repositories = local.dr2_image_deploy_repositories
  environments = local.dr2_code_deploy_environments
}

module "terraform_config" {
  source  = "./da-terraform-configurations/"
  project = "dr2"
}

module "terraform_s3_bucket" {
  source      = "git::https://github.com/nationalarchives/da-terraform-modules.git//s3"
  bucket_name = local.terraform_state_bucket_name
  bucket_policy = templatefile("${path.module}/templates/s3/terraform_state_policy.json.tpl", {
    intg_role_arn    = module.environment_roles_intg.terraform_role_arn
    staging_role_arn = module.environment_roles_staging.terraform_role_arn
    prod_role_arn    = module.environment_roles_prod.terraform_role_arn
  })
}

module "environment_roles_intg" {
  providers = {
    aws = aws.intg
  }
  source                    = "./environment_roles"
  account_number            = data.aws_ssm_parameter.intg_account_number.value
  environment               = "intg"
  management_account_number = data.aws_caller_identity.current.account_id
  terraform_repository_filters = jsonencode(concat(
    module.dr2_terraform_repository_filters.repository_environments["intg"]
  ))
}

module "environment_roles_staging" {
  providers = {
    aws = aws.staging
  }
  source                    = "./environment_roles"
  account_number            = data.aws_ssm_parameter.staging_account_number.value
  environment               = "staging"
  management_account_number = data.aws_caller_identity.current.account_id
  terraform_repository_filters = jsonencode(concat(
    module.dr2_terraform_repository_filters.repository_environments["staging"]
  ))
}

module "environment_roles_prod" {
  providers = {
    aws = aws.prod
  }
  source                    = "./environment_roles"
  account_number            = data.aws_ssm_parameter.prod_account_number.value
  environment               = "prod"
  management_account_number = data.aws_caller_identity.current.account_id
  terraform_repository_filters = jsonencode(concat(
    module.dr2_terraform_repository_filters.repository_environments["prod"]
  ))
}

module "environment_roles_mgmt" {
  source                    = "./environment_roles"
  account_number            = data.aws_caller_identity.current.account_id
  environment               = "mgmt"
  management_account_number = data.aws_caller_identity.current.account_id
  terraform_repository_filters = jsonencode(concat(
    module.dr2_terraform_repository_filters.repository_environments["mgmt"]
  ))
}

module "code_deploy_bucket" {
  source      = "git::https://github.com/nationalarchives/da-terraform-modules.git//s3"
  bucket_name = local.code_deploy_bucket_name
  bucket_policy = templatefile("${path.module}/templates/s3/code_deploy.json.tpl", {
    intg_account_number    = data.aws_ssm_parameter.intg_account_number.value,
    staging_account_number = data.aws_ssm_parameter.staging_account_number.value
    prod_account_number    = data.aws_ssm_parameter.prod_account_number.value
  })
  create_log_bucket = false
}

module "code_build_role" {
  source = "git::https://github.com/nationalarchives/da-terraform-modules.git//iam_role"
  assume_role_policy = templatefile("${path.module}/templates/iam_role/github_assume_role.json.tpl", {
    account_id   = data.aws_caller_identity.current.account_id,
    repo_filters = jsonencode(module.dr2_code_deploy_repository_filters.repository_environment_filters)
  })
  name = "MgmtDPGithubCodeDeploy"
  policy_attachments = {
    code_upload_policy = module.code_build_policy.policy_arn
  }
  tags = {}
}

module "code_build_policy" {
  source        = "git::https://github.com/nationalarchives/da-terraform-modules.git//iam_policy"
  name          = "MgmtDPGithubCodeDeployPolicy"
  policy_string = templatefile("${path.module}/templates/iam_policy/code_build.json.tpl", { code_deploy_bucket = local.code_deploy_bucket_name })
}

resource "aws_ecrpublic_repository" "judgment_package_anonymiser" {
  provider        = aws.us_east_1
  repository_name = "anonymiser"

  catalog_data {
    architectures     = ["ARM"]
    description       = "This image takes production judgment packages from TRE and anonymises them"
    operating_systems = ["Linux"]
  }
}

resource "aws_ecr_registry_scanning_configuration" "enhanced_scanning" {
  scan_type = "ENHANCED"
}

module "custodial_copy_backend_repository" {
  source          = "git::https://github.com/nationalarchives/da-terraform-modules.git//ecr"
  repository_name = "dr2-custodial-copy-backend"
  repository_policy = templatefile("${path.module}/templates/ecr/cross_account_repository_policy.json.tpl", {
    allowed_principals = jsonencode([
      "arn:aws:iam::${data.aws_ssm_parameter.intg_account_number.value}:role/intg-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.staging_account_number.value}:role/staging-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.prod_account_number.value}:role/prod-dr2-custodial-copy"
    ]),
    account_number = data.aws_caller_identity.current.account_id
  })
  lifecycle_policy = templatefile("${path.module}/templates/ecr/lifecycle_policy.json.tpl", {})
  common_tags      = {}
  image_source_url = "https://github.com/nationalarchives/dr2-custodial-copy"
}

module "custodial_copy_db_builder_repository" {
  source          = "git::https://github.com/nationalarchives/da-terraform-modules.git//ecr"
  repository_name = "dr2-custodial-copy-db-builder"
  repository_policy = templatefile("${path.module}/templates/ecr/cross_account_repository_policy.json.tpl", {
    allowed_principals = jsonencode([
      "arn:aws:iam::${data.aws_ssm_parameter.intg_account_number.value}:role/intg-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.staging_account_number.value}:role/staging-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.prod_account_number.value}:role/prod-dr2-custodial-copy"
    ]),
    account_number = data.aws_caller_identity.current.account_id
  })
  lifecycle_policy = templatefile("${path.module}/templates/ecr/lifecycle_policy.json.tpl", {})
  common_tags      = {}
  image_source_url = "https://github.com/nationalarchives/dr2-custodial-copy"
}

module "custodial_copy_webapp_repository" {
  source          = "git::https://github.com/nationalarchives/da-terraform-modules.git//ecr"
  repository_name = "dr2-custodial-copy-webapp"
  repository_policy = templatefile("${path.module}/templates/ecr/cross_account_repository_policy.json.tpl", {
    allowed_principals = jsonencode([
      "arn:aws:iam::${data.aws_ssm_parameter.intg_account_number.value}:role/intg-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.staging_account_number.value}:role/staging-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.prod_account_number.value}:role/prod-dr2-custodial-copy"
    ]),
    account_number = data.aws_caller_identity.current.account_id
  })
  lifecycle_policy = templatefile("${path.module}/templates/ecr/lifecycle_policy.json.tpl", {})
  common_tags      = {}
  image_source_url = "https://github.com/nationalarchives/dr2-custodial-copy"
}

module "custodial_copy_reindexer_repository" {
  source          = "git::https://github.com/nationalarchives/da-terraform-modules.git//ecr"
  repository_name = "dr2-custodial-copy-re-indexer"
  repository_policy = templatefile("${path.module}/templates/ecr/cross_account_repository_policy.json.tpl", {
    allowed_principals = jsonencode([
      "arn:aws:iam::${data.aws_ssm_parameter.intg_account_number.value}:role/intg-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.staging_account_number.value}:role/staging-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.prod_account_number.value}:role/prod-dr2-custodial-copy"
    ]),
    account_number = data.aws_caller_identity.current.account_id
  })
  lifecycle_policy = templatefile("${path.module}/templates/ecr/lifecycle_policy.json.tpl", {})
  common_tags      = {}
  image_source_url = "https://github.com/nationalarchives/dr2-custodial-copy"
}

module "custodial_copy_confirmer_repository" {
  source          = "git::https://github.com/nationalarchives/da-terraform-modules.git//ecr"
  repository_name = "dr2-custodial-copy-confirmer"
  repository_policy = templatefile("${path.module}/templates/ecr/cross_account_repository_policy.json.tpl", {
    allowed_principals = jsonencode([
      "arn:aws:iam::${data.aws_ssm_parameter.intg_account_number.value}:role/intg-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.staging_account_number.value}:role/staging-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.prod_account_number.value}:role/prod-dr2-custodial-copy"
    ]),
    account_number = data.aws_caller_identity.current.account_id
  })
  lifecycle_policy = templatefile("${path.module}/templates/ecr/lifecycle_policy.json.tpl", {})
  common_tags      = {}
  image_source_url = "https://github.com/nationalarchives/dr2-custodial-copy"
}

module "custodial_copy_tape_confirmer_repository" {
  source          = "git::https://github.com/nationalarchives/da-terraform-modules.git//ecr"
  repository_name = "dr2-custodial-copy-tape-confirmer"
  repository_policy = templatefile("${path.module}/templates/ecr/cross_account_repository_policy.json.tpl", {
    allowed_principals = jsonencode([
      "arn:aws:iam::${data.aws_ssm_parameter.intg_account_number.value}:role/intg-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.staging_account_number.value}:role/staging-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.prod_account_number.value}:role/prod-dr2-custodial-copy"
    ]),
    account_number = data.aws_caller_identity.current.account_id
  })
  lifecycle_policy = templatefile("${path.module}/templates/ecr/lifecycle_policy.json.tpl", {})
  common_tags      = {}
  image_source_url = "https://github.com/nationalarchives/dr2-custodial-copy"
}

module "custodial_copy_reconciler_repository" {
  source          = "git::https://github.com/nationalarchives/da-terraform-modules.git//ecr"
  repository_name = "dr2-custodial-copy-reconciler"
  repository_policy = templatefile("${path.module}/templates/ecr/cross_account_repository_policy.json.tpl", {
    allowed_principals = jsonencode([
      "arn:aws:iam::${data.aws_ssm_parameter.intg_account_number.value}:role/intg-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.staging_account_number.value}:role/staging-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.prod_account_number.value}:role/prod-dr2-custodial-copy"
    ]),
    account_number = data.aws_caller_identity.current.account_id
  })
  common_tags      = {}
  image_source_url = "https://github.com/nationalarchives/dr2-custodial-copy"
}

module "mock_tape_api_repository" {
  source          = "git::https://github.com/nationalarchives/da-terraform-modules.git//ecr"
  repository_name = "dr2-custodial-copy-mock-tape-api"
  repository_policy = templatefile("${path.module}/templates/ecr/cross_account_repository_policy.json.tpl", {
    allowed_principals = jsonencode([
      "arn:aws:iam::${data.aws_ssm_parameter.intg_account_number.value}:role/intg-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.staging_account_number.value}:role/staging-dr2-custodial-copy",
      "arn:aws:iam::${data.aws_ssm_parameter.prod_account_number.value}:role/prod-dr2-custodial-copy"
    ]),
    account_number = data.aws_caller_identity.current.account_id
  })
  common_tags      = {}
  image_source_url = "https://github.com/nationalarchives/dr2-custodial-copy"
}

module "image_deploy_role" {
  source = "git::https://github.com/nationalarchives/da-terraform-modules.git//iam_role"
  assume_role_policy = templatefile("${path.module}/templates/iam_role/github_assume_role.json.tpl", {
    account_id   = data.aws_caller_identity.current.account_id,
    repo_filters = jsonencode(module.dr2_image_deploy_repository_filters.repository_environment_filters)
  })
  name = "MgmtDPGithubImageDeploy"
  policy_attachments = {
    image_deploy_policy = module.image_deploy_policy.policy_arn
  }
  tags = {}
}

module "image_deploy_policy" {
  source = "git::https://github.com/nationalarchives/da-terraform-modules.git//iam_policy"
  name   = "MgmtDPGithubImageDeployPolicy"
  policy_string = templatefile("${path.module}/templates/iam_policy/image_deploy.json.tpl", {
    event_bus_arn = "arn:aws:events:${data.aws_region.current_region.name}:${data.aws_caller_identity.current.account_id}:event-bus/default"
  })
}

module "eventbridge_alarm_notifications_destination" {
  source                     = "git::https://github.com/nationalarchives/da-terraform-modules//eventbridge_api_destination"
  authorisation_header_value = "Bearer ${data.aws_ssm_parameter.slack_token.value}"
  name                       = "mgmt-eventbridge-slack-destination"
}

module "image_scan_vulnerability_alerts" {
  source              = "git::https://github.com/nationalarchives/da-terraform-modules//eventbridge_api_destination_rule"
  event_pattern       = templatefile("${path.module}/templates/eventbridge/image_scan_vulnerability_event_pattern.json.tpl", {})
  name                = "mgmt-eventbridge-image-scan-vulnerabilities"
  api_destination_arn = module.eventbridge_alarm_notifications_destination.api_destination_arn
  api_destination_input_transformer = {
    input_paths = {
      "repositoryName" = "$.detail.repository-name"
    }
    input_template = templatefile("${path.module}/templates/eventbridge/slack_message_input_template.json.tpl", {
      channel_id   = data.aws_ssm_parameter.dr2_notifications_slack_channel.value
      slackMessage = ":alert-noflash-slow: Vulnerabilities found in the <repositoryName> image. Log into ECR in the management account for more details"
    })
  }
}

module "enhanced_scanning_inspector_findings_alerts" {
  source = "git::https://github.com/nationalarchives/da-terraform-modules//eventbridge_api_destination_rule"
  event_pattern = templatefile("${path.module}/templates/eventbridge/generic_event_pattern.json.tpl", {
    source      = "aws.inspector2",
    detail_type = "Inspector2 Finding"
  })
  name                = "mgmt-ecr-inspector-findings"
  api_destination_arn = module.eventbridge_alarm_notifications_destination.api_destination_arn
  api_destination_input_transformer = {
    input_paths = {
      "vulnerabilityId" : "$.detail.packageVulnerabilityDetails.vulnerabilityId",
      "repositoryName" : "$.detail.resources[0].details.awsEcrContainerImage.repositoryName",
      "severity" : "$.detail.severity"
    }
    input_template = templatefile("${path.module}/templates/eventbridge/slack_message_input_template.json.tpl", {
      channel_id   = local.dev_notifications_channel_id
      slackMessage = ":alert-noflash-slow: Vulnerability <vulnerabilityId> with <severity> severity found in repository <repositoryName>"
    })
  }
}

module "enhanced_scanning_inspector_initial_scan_alert" {
  source              = "git::https://github.com/nationalarchives/da-terraform-modules//eventbridge_api_destination_rule"
  event_pattern       = templatefile("${path.module}/templates/eventbridge/vulnerability_findings_event_pattern.json.tpl", {})
  name                = "mgmt-ecr-inspector-initial-scan"
  api_destination_arn = module.eventbridge_alarm_notifications_destination.api_destination_arn
  api_destination_input_transformer = {
    input_paths = {
      "totalFindings" : "$.detail.finding-severity-counts.TOTAL",
      "repositoryName" : "$.detail.repository-name"
    }
    input_template = templatefile("${path.module}/templates/eventbridge/slack_message_input_template.json.tpl", {
      channel_id   = local.dev_notifications_channel_id
      slackMessage = ":alert-noflash-slow: Initial scan complete for `<repositoryName>` <totalFindings> vulnerabilities found"
    })
  }
}

module "dev_slack_message_eventbridge_rule" {
  source              = "git::https://github.com/nationalarchives/da-terraform-modules//eventbridge_api_destination_rule"
  api_destination_arn = module.eventbridge_alarm_notifications_destination.api_destination_arn
  event_pattern       = templatefile("${path.module}/templates/eventbridge/custom_detail_type_event_pattern.json.tpl", { detail_type = "DR2DevMessage" })
  name                = "mgmt-dr2-eventbridge-dev-slack-message"
  api_destination_input_transformer = {
    input_paths = {
      "slackMessage" = "$.detail.slackMessage"
    }
    input_template = templatefile("${path.module}/templates/eventbridge/slack_message_input_template.json.tpl", {
      channel_id   = local.dev_notifications_channel_id
      slackMessage = "<slackMessage>"
    })
  }
}

module "library_put_events_role" {
  source = "git::https://github.com/nationalarchives/da-terraform-modules.git//iam_role"
  assume_role_policy = templatefile("${path.module}/templates/iam_role/github_assume_role.json.tpl", {
    account_id = data.aws_caller_identity.current.account_id,
    repo_filters = jsonencode([
      "repo:nationalarchives/da-aws-clients@641821052:ref:refs/heads/main",
      "repo:nationalarchives/dr2-preservica-client@632653323:ref:refs/heads/main"
    ])
  })
  name = "mgmt-library-put-events-role"
  policy_attachments = {
    image_deploy_policy = module.library_put_events_policy.policy_arn
  }
  tags = {}
}

module "library_put_events_policy" {
  source = "git::https://github.com/nationalarchives/da-terraform-modules.git//iam_policy"
  name   = "mgmt-library-put-events-policy"
  policy_string = templatefile("${path.module}/templates/iam_policy/put_event.json.tpl", {
    event_bus_arn = "arn:aws:events:${data.aws_region.current_region.name}:${data.aws_caller_identity.current.account_id}:event-bus/default"
  })
}
