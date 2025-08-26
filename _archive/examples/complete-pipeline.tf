# Complete Analytics Pipeline - Queue included!
# Now the module IS the complete pipeline infrastructure

module "booking_analytics_complete" {
  source = "../modules/firehose-analytics"
  
  name = "booking-analytics"
  opensearch_domain_arn = aws_opensearch_domain.analytics.arn
  
  # Queue is created automatically as part of the pipeline
  queue_config = {
    visibility_timeout_seconds = 300
    max_receive_count         = 3
    batch_size               = 10
  }
  
  # Define your data sources (they'll get permission to send to the queue)
  data_sources = [
    {
      type = "sns"
      arn  = aws_sns_topic.booking_events.arn
    },
    {
      type = "lambda"
      arn  = aws_lambda_function.booking_processor.arn
    }
  ]
  
  transform = {
    mappings = {
      "@timestamp" = "timestamp"
      "booking.id" = "booking_id"
      "user.id" = "user_id"
    }
  }
  
  opensearch = {
    index_name = "bookings"
  }
}

# Your data sources just send to the pipeline queue
resource "aws_sns_topic_subscription" "to_pipeline" {
  topic_arn = aws_sns_topic.booking_events.arn
  protocol  = "sqs"
  endpoint  = module.booking_analytics_complete.queue_arn
}

# Multiple pipelines from same source
module "user_analytics" {
  source = "../modules/firehose-analytics"
  
  name = "user-analytics"
  opensearch_domain_arn = aws_opensearch_domain.analytics.arn
  
  # Same data source, different processing
  data_sources = [
    {
      type = "sns"
      arn  = aws_sns_topic.booking_events.arn
    }
  ]
  
  transform = {
    mappings = {
      "user.id" = "user_id"
      "user.email" = "email"
      "event.type" = "event_type"
    }
  }
  
  opensearch = {
    index_name = "users"
  }
}

# Example: Use existing queue
module "existing_queue_pipeline" {
  source = "../modules/firehose-analytics"
  
  name = "legacy-pipeline"
  create_queue = false
  existing_queue_arn = aws_sqs_queue.legacy_events.arn
  opensearch_domain_arn = aws_opensearch_domain.analytics.arn
  
  transform = {
    mappings = {
      "legacy.id" = "id"
    }
  }
  
  opensearch = {
    index_name = "legacy"
  }
}