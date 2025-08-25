locals {
  id            = module.this.id
  context       = module.this.context
  create_queue  = var.create_queue ? true : false
  queue_config  = var.queue_config
  queue_arn     = var.create_queue ? aws_sqs_queue.main[0].arn : var.existing_queue_arn
  data_sources  = var.data_sources
  
}

# Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "s3" {
  name          = join("-", [local.id, "firehose"])
  destination = "extended_s3"

  extended_s3_configuration {
    file_extension    = ".json"
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.backup.arn

    compression_format = "GZIP"
    prefix             = "raw-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "failed-data/"
  }
}

# S3 bucket for failed records
resource "aws_s3_bucket" "backup" {
  bucket = join("-", [local.id, "backup"])
}