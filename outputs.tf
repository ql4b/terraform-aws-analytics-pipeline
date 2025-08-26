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

output "sqs_bridge_ecr" {
  value = module.sqs_bridge_ecr
}

output "sqs_bridge_log_group" {
  value = data.aws_lambda_function.sqs_bridge_lambda.logging_config[0].log_group
}

