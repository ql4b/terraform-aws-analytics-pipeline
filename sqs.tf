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
resource "aws_sns_topic_subscription" "sqs" {
  for_each = {
    for idx, source in local.data_sources : idx => source
    if source.type == "sns"
  }
  
  topic_arn = each.value.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.main[0].arn
}

# For data source with type == "api_gateway" create SQS integration
resource "aws_api_gateway_integration" "sqs" {
  for_each = {
    for idx, source in local.data_sources : idx => source
    if source.type == "api_gateway"
  }
  
  rest_api_id = split("/", each.value.arn)[1]
  resource_id = "*"
  http_method = "POST"
  
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.main[0].name}"
  
  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-amz-json-1.0'"
  }
  
  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody={\"timestamp\":\"$context.requestTime\",\"method\":\"$context.httpMethod\",\"path\":\"$context.resourcePath\",\"sourceIp\":\"$context.identity.sourceIp\",\"requestId\":\"$context.requestId\",\"body\":$input.body}"
  }
}