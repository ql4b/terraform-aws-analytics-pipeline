# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# SQS Queue (the reliability/buffering layer)
resource "aws_sqs_queue" "main" {
  count = local.create_queue ? 1 : 0
  name                       = join("-", [local.id, "pipeline"])

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
  name                       = join("-", [local.id, "pipeline", "dlq"])
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

# For data source with type == "sns" subscribe the queue to sns topic
# NOTE: This resource always requires a provider alias `aws.sns_source`.
# The root module must supply it via the `providers` map, either:
#   aws.sns_source = aws           # same region (default)
#   aws.sns_source = aws.<alias>   # cross-region (e.g., aws.virginia)
resource "aws_sns_topic_subscription" "sqs" {
  for_each = {
    for idx, source in local.data_sources : idx => source
    if source.type == "sns"
  }
  
  provider = aws.sns_source
  
  topic_arn             = each.value.arn
  protocol              = "sqs"
  endpoint              = aws_sqs_queue.main[0].arn
  raw_message_delivery = false
  
}

# API Gateway analytics should be handled at the application level
# (Lambda function sends to SNS/SQS directly)