locals {
  id            = module.this.id
  context       = module.this.context
  create_queue  = var.create_queue ? true : false
  queue_config  = var.queue_config
  queue_arn     = var.create_queue ? aws_sqs_queue.main[0].arn : var.existing_queue_arn
  data_sources  = var.data_sources

  transform = var.transform
  enable_transform = var.enable_transform
  transform_template = var.transform_template
}

# Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "main" {
  name          = join("-", [local.id, "firehose"])
  destination = var.enable_opensearch ? "opensearch" : "extended_s3"

  extended_s3_configuration {
    file_extension    = ".json"
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.backup.arn

    compression_format = "GZIP"
    prefix             = "raw-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "failed-data/"

    dynamic "processing_configuration" {
      for_each = local.enable_transform ? [1] : []
      content {
        enabled = true
        processors {
          type = "Lambda"
          parameters {
            parameter_name  = "LambdaArn"
            parameter_value = module.transform[0].function_arn
          }
        }
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_s3.name
    }
  }

  dynamic "opensearch_configuration" {
    for_each = var.enable_opensearch ? [1] : []
    content {
      domain_arn = var.opensearch_config.domain_arn
      role_arn   = aws_iam_role.firehose_opensearch[0].arn
      index_name = var.opensearch_config.index_name
      
      buffering_size     = var.opensearch_config.buffering_size
      buffering_interval = var.opensearch_config.buffering_interval
      
      dynamic "processing_configuration" {
        for_each = local.enable_transform ? [1] : []
        content {
          enabled = true
          processors {
            type = "Lambda"
            parameters {
              parameter_name  = "LambdaArn"
              parameter_value = module.transform[0].function_arn
            }
          }
        }
      }

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose_opensearch[0].name
        log_stream_name = aws_cloudwatch_log_stream.firehose_opensearch[0].name
      }
      
      s3_backup_mode = "FailedDocumentsOnly"
      s3_configuration {
        role_arn   = aws_iam_role.firehose_opensearch[0].arn
        bucket_arn = aws_s3_bucket.backup.arn
        prefix     = "opensearch-failed/"
        
        compression_format = "GZIP"
        
        cloudwatch_logging_options {
          enabled         = true
          log_group_name  = aws_cloudwatch_log_group.firehose_opensearch[0].name
          log_stream_name = aws_cloudwatch_log_stream.firehose_opensearch_s3[0].name
        }
      }
    }
  }
}

# S3 bucket for failed records
resource "aws_s3_bucket" "backup" {
  bucket = join("-", [local.id, "backup"])
}

# IAM role for Firehose to write to OpenSearch
resource "aws_iam_role" "firehose_opensearch" {
  count = var.enable_opensearch ? 1 : 0
  name  = join("-", [local.id, "firehose", "opensearch", "role"])

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose_opensearch" {
  count = var.enable_opensearch ? 1 : 0
  name  = join("-", [local.id, "firehose", "opensearch", "policy"])
  role  = aws_iam_role.firehose_opensearch[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow"
        Action = [
          "es:DescribeElasticsearchDomain",
          "es:DescribeElasticsearchDomains",
          "es:DescribeElasticsearchDomainConfig",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "opensearch:DescribeDomain",
          "opensearch:DescribeDomains",
          "opensearch:DescribeDomainConfig",
          "opensearch:ESHttpPost",
          "opensearch:ESHttpPut"
        ]
        Resource = [
          var.opensearch_config.domain_arn,
          "${var.opensearch_config.domain_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = aws_cloudwatch_log_group.firehose_opensearch[0].arn
      }
    ], local.enable_transform ? [{
      Effect = "Allow"
      Action = [
        "lambda:InvokeFunction"
      ]
      Resource = module.transform[0].function_arn
    }] : [])
  })
}

# CloudWatch log group for OpenSearch Firehose
resource "aws_cloudwatch_log_group" "firehose_opensearch" {
  count             = var.enable_opensearch ? 1 : 0
  name              = "/aws/kinesisfirehose/${local.id}-opensearch"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "firehose_opensearch" {
  count          = var.enable_opensearch ? 1 : 0
  name           = "opensearch-delivery"
  log_group_name = aws_cloudwatch_log_group.firehose_opensearch[0].name
}

resource "aws_cloudwatch_log_stream" "firehose_opensearch_s3" {
  count          = var.enable_opensearch ? 1 : 0
  name           = "s3-backup"
  log_group_name = aws_cloudwatch_log_group.firehose_opensearch[0].name
}