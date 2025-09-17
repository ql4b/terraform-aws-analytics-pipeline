# Clone and build Go Lambda function
resource "null_resource" "sqs_bridge_build" {
  triggers = {
    config_hash = filemd5("${path.module}/bridge-go.tf")
  }
  
  provisioner "local-exec" {
    command = <<-EOF
      set -e
      BUILD_DIR="${path.module}/.sqs-bridge-build"
      mkdir -p $BUILD_DIR
      cd $BUILD_DIR
      
      if [ ! -d ".git" ]; then
        git clone -b ${var.sqs_bridge_git_ref} https://github.com/ql4b/sqs-firehose-bridge.git .
      else
        git fetch && git checkout ${var.sqs_bridge_git_ref} && git pull
      fi
      
      make build
    EOF
  }
}

locals {
  sqs_bridge_build_dir = "${path.module}/.sqs-bridge-build"
}

module "sqs_bridge_lambda" {
  depends_on = [null_resource.sqs_bridge_build]
  
  source      = "git@github.com:ql4b/terraform-aws-lambda-function.git"
  context     = module.this.context
  attributes  = concat(module.this.attributes, ["sqs", "firehose", "bridge"])

  filename        = "${local.sqs_bridge_build_dir}/lambda.zip"
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