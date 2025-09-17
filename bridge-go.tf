# Clone and build Go Lambda function
data "external" "sqs_bridge_build" {
  program = ["bash", "-c", <<-EOF
    set -e
    BUILD_DIR="${path.module}/.sqs-bridge-build"
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    
    if [ ! -d ".git" ]; then
      git clone https://github.com/ql4b/sqs-firehose-bridge.git?ref=next .
    else
      git pull
    fi
    
    make build
    echo "{\"build_dir\":\"$BUILD_DIR\"}"
  EOF
  ]
}

module "sqs_bridge_lambda" {
  depends_on = [data.external.sqs_bridge_build]
  
  source      = "git@github.com:ql4b/terraform-aws-lambda-function.git"
  context     = module.this.context
  attributes  = concat(module.this.attributes, ["sqs", "firehose", "bridge"])

  source_dir      = data.external.sqs_bridge_build.result.build_dir
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