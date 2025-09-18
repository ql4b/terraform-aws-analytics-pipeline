# Clone and build Go Lambda function
resource "null_resource" "sqs_bridge_build" {
  triggers = {
    config_hash = filemd5("${path.module}/bridge.tf")
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
      
      # Copy built zip to module directory
      TARGET_PATH="${path.module}/sqs-bridge.zip"
      TARGET_DIR="$(dirname "$TARGET_PATH")"
      echo "Creating directory: $TARGET_DIR"
      mkdir -p "$TARGET_DIR"
      echo "Copying lambda.zip to $TARGET_PATH"
      cp lambda.zip "$TARGET_PATH"
    EOF
  }

  provisioner "local-exec" {
    command = "test -f ${local.sqs_bridge_zip_path} || exit 1"
  }
}

# data "local_file" "zip" {
#   depends_on = [null_resource.sqs_bridge_build]
#   filename = local.sqs_bridge_zip_path
# }

resource "local_file" "zip_check" {
  depends_on = [null_resource.sqs_bridge_build]
  
  content  = "zip ready"
  filename = "${path.module}/.zip-ready"
  
  provisioner "local-exec" {
    command = "while [ ! -f ${local.sqs_bridge_zip_path} ]; do sleep 1; done"
  }
}

locals {
  sqs_bridge_zip_path = "${path.module}/sqs-bridge.zip"
}

module "sqs_bridge_lambda" {
  # depends_on = [null_resource.sqs_bridge_build]
  depends_on = [ local_file.zip_check ]
  
  source      = "git@github.com:ql4b/terraform-aws-lambda-function.git"
  context     = module.this.context
  attributes  = concat(module.this.attributes, ["sqs", "firehose", "bridge"])

  filename        = local.sqs_bridge_zip_path
  # filename          = data.local_file.zip.filename
  source_dir      = null
  runtime         = "provided.al2023"
  architecture    = "arm64"
  timeout         = 300
  memory_size     = 512

  environment_variables = {
    FIREHOSE_STREAM_NAME = aws_kinesis_firehose_delivery_stream.main.name
    BUILD_TRIGGER = null_resource.sqs_bridge_build.id  # Force update when build changes
  }
}

resource "aws_lambda_event_source_mapping" "sqs_bridge_trigger" {
  event_source_arn = local.queue_arn
  function_name    = module.sqs_bridge_lambda.function_arn
  batch_size       = var.queue_config.batch_size
}