# Advanced Analytics Pipeline Example
# Shows EventBridge-style transformations

module "advanced_booking_analytics" {
  source = "../modules/firehose-analytics"
  
  name = "advanced-booking-analytics"
  source_queue_arn = aws_sqs_queue.booking_events.arn
  opensearch_domain_arn = aws_opensearch_domain.analytics.arn
  
  # Advanced transform configuration
  transform = {
    # Extract nested values (EventBridge input_paths style)
    input_paths = {
      "user_id"    = "booking.passenger.id"
      "user_email" = "booking.passenger.email"
      "flight_num" = "booking.flights.0.number"
      "price"      = "booking.pricing.total.amount"
    }
    
    # JSON template with placeholders (EventBridge input_template style)
    input_template = jsonencode({
      "@timestamp" = "$${timestamp}"
      "event" = {
        "type" = "booking_completed"
        "user" = {
          "id" = "$${user_id}"
          "email" = "$${user_email}"
        }
        "booking" = {
          "id" = "$${booking_id}"
          "flight" = "$${flight_num}"
          "amount" = "$${price}"
        }
      }
    })
    
    # Conditional logic
    conditions = [
      {
        field = "amount"
        operator = "gt"
        value = "500"
        then_map = {
          "booking.tier" = "premium"
          "alert.high_value" = "true"
        }
        else_map = {
          "booking.tier" = "standard"
        }
      }
    ]
    
    # Data enrichment
    enrich = {
      add_fields = {
        "pipeline.version" = "2.0"
        "processed_at" = "$${now()}"
      }
      remove_fields = ["internal_id", "debug_info"]
      parse_json_fields = ["metadata", "custom_fields"]
    }
    
    # Custom JavaScript functions
    custom_functions = [
      {
        name = "calculateDiscount"
        code = "(price, tier) => tier === 'premium' ? price * 0.1 : 0"
      }
    ]
  }
  
  opensearch = {
    index_name = "bookings-v2"
  }
}

# Example: Simple EventBridge-style mapping
module "simple_eventbridge_style" {
  source = "../modules/firehose-analytics"
  
  name = "eventbridge-style"
  source_queue_arn = aws_sqs_queue.events.arn
  opensearch_domain_arn = aws_opensearch_domain.analytics.arn
  
  transform = {
    # This mimics EventBridge's input transformer
    input_paths = {
      "id" = "detail.booking.id"
      "status" = "detail.booking.status"
      "timestamp" = "time"
    }
    
    input_template = jsonencode({
      "booking_id" = "$${id}"
      "status" = "$${status}"
      "@timestamp" = "$${timestamp}"
      "source" = "booking-api"
    })
  }
  
  opensearch = {
    index_name = "events"
  }
}