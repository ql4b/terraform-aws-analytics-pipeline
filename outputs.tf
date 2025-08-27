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

output "sqs_bridge" {
  value = try (module.sqs_bridge_lambda[0], null) 
}

output "sqs_bridge_ecr" {
  value = module.sqs_bridge_ecr
}

output "firehose_stream_name" {
  description = "Name of the Kinesis Data Firehose stream"
  value       = aws_kinesis_firehose_delivery_stream.main.name
}

output "s3_bucket_name" {
  description = "Name of the S3 backup bucket"
  value       = aws_s3_bucket.backup.bucket
}

output "firehose_role_arn" {
  description = "ARN of the Firehose IAM role for S3"
  value       = aws_iam_role.firehose_role.arn
}

output "firehose_opensearch_role_arn" {
  description = "ARN of the Firehose IAM role for OpenSearch"
  value       = var.enable_opensearch ? aws_iam_role.firehose_opensearch[0].arn : null
}

