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
  value = module.sqs_bridge_lambda
}