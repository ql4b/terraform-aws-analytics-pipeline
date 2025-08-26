output "firehose_stream_name" {
  description = "Name of the Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.main.name
}

output "firehose_stream_arn" {
  description = "ARN of the Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.main.arn
}

output "transform_lambda_arn" {
  description = "ARN of the transform Lambda function"
  value       = aws_lambda_function.transform.arn
}

output "bridge_lambda_arn" {
  description = "ARN of the SQS bridge Lambda function"
  value       = aws_lambda_function.sqs_to_firehose.arn
}

output "backup_bucket_name" {
  description = "Name of the S3 backup bucket"
  value       = aws_s3_bucket.backup.bucket
}

output "queue_url" {
  description = "URL of the SQS queue for sending data"
  value       = var.create_queue ? aws_sqs_queue.main[0].url : null
}

output "queue_arn" {
  description = "ARN of the SQS queue"
  value       = local.queue_arn
}

output "dlq_url" {
  description = "URL of the dead letter queue"
  value       = var.create_queue ? aws_sqs_queue.dlq[0].url : null
}