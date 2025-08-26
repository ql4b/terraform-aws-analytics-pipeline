# Firehose Analytics Pipeline Module
# Data Sources → SQS (buffer/reliability) → Lambda Transform → Firehose → OpenSearch

# SQS Queue (the reliability/buffering layer)
resource "aws_sqs_queue" "main" {
  count = var.create_queue ? 1 : 0
  
  name                       = "${var.name}-pipeline"
  visibility_timeout_seconds = var.queue_config.visibility_timeout_seconds
  message_retention_seconds  = var.queue_config.message_retention_seconds
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.queue_config.max_receive_count
  })
  
  tags = var.tags
}

# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  count = var.create_queue ? 1 : 0
  
  name                      = "${var.name}-pipeline-dlq"
  message_retention_seconds = 1209600  # 14 days
  
  tags = var.tags
}

# Queue policy for data sources
resource "aws_sqs_queue_policy" "main" {
  count     = var.create_queue && length(var.data_sources) > 0 ? 1 : 0
  queue_url = aws_sqs_queue.main[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [for source in var.data_sources : 
            source.type == "sns" ? "sns.amazonaws.com" :
            source.type == "eventbridge" ? "events.amazonaws.com" :
            source.type == "api_gateway" ? "apigateway.amazonaws.com" :
            "lambda.amazonaws.com"
          ]
        }
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.main[0].arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [for source in var.data_sources : source.arn]
          }
        }
      }
    ]
  })
}

locals {
  queue_arn = var.create_queue ? aws_sqs_queue.main[0].arn : var.existing_queue_arn
}

# Lambda function for data transformation
resource "aws_lambda_function" "transform" {
  filename         = data.archive_file.transform_zip.output_path
  function_name    = "${var.name}-transform"
  role            = aws_iam_role.lambda_role.arn
  handler         = "bootstrap"
  runtime         = "provided.al2023"
  timeout         = 60
  memory_size     = 256

  source_code_hash = data.archive_file.transform_zip.output_base64sha256
}

# Transform function code
data "archive_file" "transform_zip" {
  type        = "zip"
  output_path = "/tmp/${var.name}-transform.zip"
  source {
    content = templatefile("${path.module}/templates/transform.js", {
      mappings = var.transform.mappings
      fields   = var.transform.fields
    })
    filename = "index.js"
  }
}

# Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "main" {
  name        = var.name
  destination = "opensearch"

  opensearch_configuration {
    domain_arn = var.opensearch_domain_arn
    role_arn   = aws_iam_role.firehose_role.arn
    index_name = var.opensearch.index_name

    processing_configuration {
      enabled = true
      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = aws_lambda_function.transform.arn
        }
      }
    }

    buffering_interval = var.buffering.interval_seconds
    buffering_size     = var.buffering.size_mb

    s3_configuration {
      role_arn   = aws_iam_role.firehose_role.arn
      bucket_arn = aws_s3_bucket.backup.arn
      prefix     = "failed/"
    }
  }
}

# S3 bucket for failed records
resource "aws_s3_bucket" "backup" {
  bucket = "${var.name}-firehose-backup"
}

# Lambda event source mapping from SQS
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = local.queue_arn
  function_name    = aws_lambda_function.sqs_to_firehose.arn
  batch_size       = var.queue_config.batch_size
}

# Lambda to bridge SQS → Firehose
resource "aws_lambda_function" "sqs_to_firehose" {
  filename         = data.archive_file.bridge_zip.output_path
  function_name    = "${var.name}-sqs-bridge"
  role            = aws_iam_role.lambda_role.arn
  handler         = "bootstrap"
  runtime         = "provided.al2023"
  timeout         = 60

  environment {
    variables = {
      FIREHOSE_STREAM_NAME = aws_kinesis_firehose_delivery_stream.main.name
      HANDLER = "/var/task/sqs-bridge.sh"
    }
  }

  source_code_hash = data.archive_file.bridge_zip.output_base64sha256
}

data "archive_file" "bridge_zip" {
  type        = "zip"
  output_path = "/tmp/${var.name}-bridge.zip"
  source {
    content  = file("${path.module}/templates/bootstrap")
    filename = "bootstrap"
  }
  source {
    content  = file("${path.module}/templates/sqs-bridge.sh")
    filename = "sqs-bridge.sh"
  }
}

# Security Groups for VPC connectivity
resource "aws_security_group" "firehose" {
  count  = var.vpc_config.enabled ? 1 : 0
  name   = "${var.name}-firehose"
  vpc_id = var.vpc_config.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# Allow Firehose to reach OpenSearch
resource "aws_security_group_rule" "firehose_to_opensearch" {
  count                    = var.vpc_config.enabled ? 1 : 0
  type                     = "egress"
  from_port               = 443
  to_port                 = 443
  protocol                = "tcp"
  source_security_group_id = var.opensearch_security_group_id
  security_group_id       = aws_security_group.firehose[0].id
}