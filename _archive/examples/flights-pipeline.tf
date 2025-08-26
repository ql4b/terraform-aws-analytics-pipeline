# Flight Search Results Pipeline - Logstash to Firehose Translation
# Replaces: pipeline.flights.conf

module "flights_analytics" {
  source = "../modules/firehose-analytics"
  
  name = "flights-analytics"
  source_queue_arn = aws_sqs_queue.redis_flights.arn  # Replace Redis input with SQS
  opensearch_domain_arn = aws_opensearch_domain.flights.arn
  
  # Use advanced transform template for complex logic
  transform_template = "${path.module}/../modules/firehose-analytics/templates/flights-transform.js"
  
  transform = {
    # Basic field mappings
    mappings = {
      # Copy search data to structured fields
      "itinerary.origin" = "search_data.departure"
      "itinerary.destination" = "search_data.destination"
      "passengers.adults" = "search_data.adults"
      "passengers.children" = "search_data.children"
      "passengers.infants" = "search_data.infants"
    }
    
    # Custom processing functions
    custom_functions = [
      {
        name = "processFlightResults"
        code = <<-JS
          (results) => {
            if (!results || !results.complete) return [];
            
            return results.complete.map(item => ({
              ...item,
              price_return: parseFloat(item.price_return || 0)
            }));
          }
        JS
      },
      {
        name = "generateFingerprint"
        code = <<-JS
          (data) => {
            const crypto = require('crypto');
            return crypto.createHash('sha256').update(data).digest('hex');
          }
        JS
      },
      {
        name = "formatDate"
        code = <<-JS
          (dateStr) => {
            if (!dateStr) return null;
            const [day, month, year] = dateStr.split('-');
            return new Date(year, month - 1, day).toISOString();
          }
        JS
      }
    ]
    
    # Data enrichment
    enrich = {
      add_fields = {
        "pipeline.version" = "firehose-v1"
        "processed_at" = "${now()}"
      }
      remove_fields = ["results", "event", "success", "search_data"]
    }
  }
  
  opensearch = {
    index_name = "flights"
  }
  
  buffering = {
    interval_seconds = 30  # Faster than default for real-time search
    size_mb = 2
  }
}

# Dual output (like your Logstash config)
module "flights_search_results" {
  source = "../modules/firehose-analytics"
  
  name = "flights-search-results"
  source_queue_arn = aws_sqs_queue.redis_flights.arn  # Same source
  opensearch_domain_arn = aws_opensearch_domain.flights_analytics.arn
  
  transform_template = "${path.module}/../modules/firehose-analytics/templates/flights-transform.js"
  
  transform = {
    # Same transform logic, different index
    custom_functions = [
      {
        name = "processFlightResults"
        code = file("${path.module}/functions/process-flights.js")
      }
    ]
  }
  
  opensearch = {
    index_name = "search-results"
  }
}