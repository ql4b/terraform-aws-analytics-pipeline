locals {
  id            = module.this.id
  context       = module.this.context

  # data sources
  data_sources  = var.data_sources
  
  # queue settings
  create_queue        = var.create_queue ? true : false
  queue_config        = var.queue_config
  queue_arn           = var.create_queue ? aws_sqs_queue.main[0].arn : var.existing_queue_arn

  # transform
  enable_transform    = var.enable_transform
  transform_template  = var.transform_template
  transform           = var.transform

  # opensearch
  enable_opensearch   = var.enable_opensearch
  opensearch_config   = var.opensearch_config
}

# Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "main" {
  name          = join("-", [local.id, "firehose"])
  destination   = local.enable_opensearch ? "opensearch" : "extended_s3"

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
    for_each = local.enable_opensearch ? [1] : []
    content {
      domain_arn              = local.opensearch_config.domain_arn
      role_arn                = aws_iam_role.firehose_opensearch[0].arn
      index_name              = local.opensearch_config.index_name
      index_rotation_period   = local.opensearch_config.index_rotation_period
      
      buffering_size          = local.opensearch_config.buffering_size
      buffering_interval      = local.opensearch_config.buffering_interval
      
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