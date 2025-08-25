locals {
  id            = module.this.id
  context       = module.this.context
  create_queue  = var.create_queue ? true : false
  queue_config  = var.queue_config
  queue_arn     = var.create_queue ? aws_sqs_queue.main[0].arn : var.existing_queue_arn
  data_sources  = var.data_sources
  
}

# SQS Queue (the reliability/buffering layer)
resource "aws_sqs_queue" "main" {
  count = local.create_queue ? 1 : 0
  name                       = join("-", local.id, "pipeline")
  
  visibility_timeout_seconds = local.queue_config.visibility_timeout_seconds
  message_retention_seconds  = local.queue_config.message_retention_seconds
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = local.queue_config.max_receive_count
  })
  
  tags = module.this.tags
}

# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  count = local.create_queue ? 1 : 0
  name                       = join("-", local.id, "pipeline", "dlq")
  message_retention_seconds = 1209600  # 14 days
  
  tags = module.this.tags
}

# Queue policy for data sources
resource "aws_sqs_queue_policy" "main" {
  count     = local.create_queue && length(local.data_sources) > 0 ? 1 : 0
  queue_url = aws_sqs_queue.main[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [for source in local.data_sources : 
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
            "aws:SourceArn" = [for source in local.data_sources : source.arn]
          }
        }
      }
    ]
  })
}