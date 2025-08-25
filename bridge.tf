locals {
    sqs_bridge_image_uri  = var.sqs_bridge_image_uri 
    sqs_bridge_command    = var.sqs_bridge_command
    sqs_batch_size        = var.queue_config.batch_size
}


module "sqs_bridge_ecr" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1"
  
  context              = module.this.context
  attributes           = concat(module.this.attributes, ["sqs", "bridge"])
  
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

module "sqs_bridge_lambda" {
  source               = "git@github.com:ql4b/terraform-aws-lambda-function.git"
  context              = module.this.context
  attributes           = concat(module.this.attributes, ["sqs", "bridge", "lambda"])

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
}

resource "aws_lambda_event_source_mapping" "sqs_bridge_trigger" {
  event_source_arn = local.queue_arn
  function_name    = module.sqs_bridge_lambda.function_arn
  batch_size       = var.queue_config.batch_size
}