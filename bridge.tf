locals {
    sqs_bridge_image_uri  = var.sqs_bridge_image_uri
    sqs_bridge_command    = var.sqs_bridge_command  
}

module "sqs_bridge_lambda" {
  source               = "git@github.com:ql4b/terraform-aws-lambda-function.git"
  context              = module.this.context
  attributes           = concat(module.this.attributes, ["sqs", "bridge", "lambda"])

  package_type         = "Image"
  image_uri            = local.sqs_bridge_image_uri
  image_config = {
    command            = local.sqs_bridge_command
  }
  source_dir = null

  environment_variables = {
    FIREHOSE_STREAM_NAME = aws_kinesis_firehose_delivery_stream.main.name
  }
}