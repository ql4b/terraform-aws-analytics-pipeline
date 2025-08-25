locals {
    sqs_bridge_image_uri  = "703177223665.dkr.ecr.us-east-1.amazonaws.com/ql4b-sqs-firehose-bridge-sqs-bridge:latest" 
                          # module.sqs_bridge_ecr.repository_url
    sqs_bridge_command    = var.sqs_bridge_command
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
  source_dir = null

  environment_variables = {
    FIREHOSE_STREAM_NAME = aws_kinesis_firehose_delivery_stream.main.name
  }
}