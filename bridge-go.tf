# Create placeholder zip with minimal bootstrap
data "archive_file" "sqs_bridge_placeholder" {
  type        = "zip"
  output_path = "${path.module}/sqs-bridge.zip"
  
  source {
    content  = "#!/bin/bash\necho 'placeholder'"
    filename = "bootstrap"
  }
}

# Clone and build Go Lambda function
resource "null_resource" "sqs_bridge_build" {
  depends_on = [data.archive_file.sqs_bridge_placeholder]
  
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
      
      # Replace placeholder with actual zip (use absolute path)
      cp lambda.zip "$(pwd)/../../sqs-bridge.zip"
    EOF
  }
}

locals {
  sqs_bridge_zip_path = "${path.module}/sqs-bridge.zip"
}

module "sqs_bridge_lambda" {
  depends_on = [null_resource.sqs_bridge_build]
  
  source      = "git@github.com:ql4b/terraform-aws-lambda-function.git"
  context     = module.this.context
  attributes  = concat(module.this.attributes, ["sqs", "firehose", "bridge"])

  filename        = local.sqs_bridge_zip_path
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