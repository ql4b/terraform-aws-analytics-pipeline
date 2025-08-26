# Example: Booking Analytics Pipeline
# Deploy this with: terraform apply -target=module.booking_analytics

module "booking_analytics" {
  source = "../modules/firehose-analytics"
  
  name = "booking-analytics"
  
  # Your existing SQS queue
  source_queue_arn = aws_sqs_queue.booking_events.arn
  
  # Your existing OpenSearch domain
  opensearch_domain_arn = aws_opensearch_domain.analytics.arn
  
  # Transform configuration (replaces your Logstash filter)
  transform = {
    fields = ["timestamp", "booking_id", "user_id", "amount", "status", "carrier"]
    mappings = {
      "@timestamp"    = "timestamp"
      "booking.id"    = "booking_id" 
      "user.id"       = "user_id"
      "amount.eur"    = "amount"
      "booking.status" = "status"
      "airline.code"  = "carrier"
    }
  }
  
  # OpenSearch index config
  opensearch = {
    index_name = "bookings"
  }
  
  # Buffering (tune for your volume)
  buffering = {
    interval_seconds = 60    # Buffer for 1 minute
    size_mb         = 5      # Or until 5MB
  }
  
  tags = {
    Environment = "production"
    Project     = "airswitch"
  }
}

# Example SQS queue (if you don't have one)
resource "aws_sqs_queue" "booking_events" {
  name = "booking-events"
  
  # DLQ for failed messages
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.booking_events_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "booking_events_dlq" {
  name = "booking-events-dlq"
}

# Example OpenSearch domain (if you don't have one)
resource "aws_opensearch_domain" "analytics" {
  domain_name    = "booking-analytics"
  engine_version = "OpenSearch_2.3"
  
  cluster_config {
    instance_type  = "t3.small.search"
    instance_count = 1
  }
  
  ebs_options {
    ebs_enabled = true
    volume_size = 20
  }
}