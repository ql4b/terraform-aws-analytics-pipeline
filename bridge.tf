# Pre-built SQS-Firehose bridge Lambda
module "sqs_bridge_lambda" {
  # checkov:skip=CKV_TF_1: Source is from trusted repository
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.0.0"
  
  context     = module.this.context
  attributes  = concat(module.this.attributes, ["sqs", "firehose", "bridge"])

  filename        = "${path.module}/assets/sqs-bridge.zip"
  source_dir      = null
  runtime         = "provided.al2023"
  architecture    = "arm64"
  timeout         = 300
  memory_size     = 512

  environment_variables = {
    FIREHOSE_STREAM_NAME = aws_kinesis_firehose_delivery_stream.main.name
  }
}

resource "aws_lambda_event_source_mapping" "sqs_bridge_trigger" {
  event_source_arn = local.queue_arn
  function_name    = module.sqs_bridge_lambda.function_arn
  batch_size       = var.queue_config.batch_size
}