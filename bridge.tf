locals {
    sqs_bridge_image_uri        = "${module.sqs_bridge_ecr.repository_url}:latest"
    sqs_bridge_command          = var.sqs_bridge_command
    sqs_batch_size              = var.queue_config.batch_size
    sqs_bridge_image_tag        = "latest"
    sqs_bridge_image_exists     = try(data.external.sqs_bridge_ecr_image_probe.result.exists, "false") == "true"
    sqs_bridge_image_digest     = try(data.external.sqs_bridge_ecr_image_probe.result.digest, null)
    sqs_bridge_public_image    = var.sqs_bridge_public_image
}


module "sqs_bridge_ecr" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1"
  
  context              = module.this.context
  attributes           = concat(module.this.attributes, ["sqs", "firehose", "bridge"])
  
  image_tag_mutability = "MUTABLE"
  scan_images_on_push  = true
  force_delete         = true
}

# 
data "external" "sqs_bridge_ecr_image_probe" {
  # Requires AWS CLI available on the machine/runner doing terraform.
  program = ["bash", "-lc", <<-BASH
    set -euo pipefail
    # Try to get the image digest; if not found, return exists=false.
    if aws ecr describe-images \
        --repository-name "${module.sqs_bridge_ecr.repository_name}" \
        --image-ids imageTag="${local.sqs_bridge_image_tag}" \
        --query 'imageDetails[0].imageDigest' \
        --output text 2>/dev/null | grep -v 'None' >/dev/null; then
      digest=$(aws ecr describe-images \
        --repository-name "${module.sqs_bridge_ecr.repository_name}" \
        --image-ids imageTag="${local.sqs_bridge_image_tag}" \
        --query 'imageDetails[0].imageDigest' \
        --output text)
      jq -n --arg exists "true" --arg digest "$digest" '{exists:$exists, digest:$digest}'
    else
      jq -n --arg exists "false" '{exists:$exists}'
    fi
  BASH
  ]
}

# Stop execution and instruct user how to push the the newly created ECR repo
resource "terraform_data" "fail_fast_if_no_image" {
  depends_on = [ module.sqs_bridge_ecr ]
  lifecycle {
    precondition {
      condition = local.sqs_bridge_image_exists
      error_message = <<EOM
ECR repo created: ${module.sqs_bridge_ecr.repository_url}"
Push your image and re-apply:"
      
aws ecr get-login-password | docker login --username AWS --password-stdin ${replace(module.sqs_bridge_ecr.repository_url, "/${module.sqs_bridge_ecr.repository_name}", "")}
docker pull ${local.sqs_bridge_public_image}
docker tag  ${local.sqs_bridge_public_image} "${module.sqs_bridge_ecr.repository_url}:${local.sqs_bridge_image_tag}"
docker push ${module.sqs_bridge_ecr.repository_url}:${local.sqs_bridge_image_tag}
EOM
    }
  }
  
}

module "sqs_bridge_lambda" {
  count                = local.sqs_bridge_image_exists ? 1 : 0
  source               = "git@github.com:ql4b/terraform-aws-lambda-function.git"
  context              = module.this.context
  attributes           = concat(module.this.attributes, ["sqs", "firehose", "bridge"])

  package_type         = "Image"
  image_uri            = local.sqs_bridge_image_uri
  architecture         = "arm64"
  image_config = {
    command            = local.sqs_bridge_command
  }
  source_dir      = null
  timeout         = 300
  memory_size     = 1024

  environment_variables = {
    FIREHOSE_STREAM_NAME = aws_kinesis_firehose_delivery_stream.main.name
  }

  depends_on = [  module.sqs_bridge_ecr ]
}

resource "aws_lambda_event_source_mapping" "sqs_bridge_trigger" {
  count            = local.sqs_bridge_image_exists ? 1 : 0
  event_source_arn = local.queue_arn
  function_name    = module.sqs_bridge_lambda[0].function_arn
  batch_size       = var.queue_config.batch_size
}