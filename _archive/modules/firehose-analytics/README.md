# Firehose Analytics Module

**Speedy Gonzales** data pipeline: SQS → Lambda → Firehose → OpenSearch

Replaces your ECS Logstash setup with serverless components. Deploy in 1-2 hours instead of days.

## Architecture

```
SQS Queue → Lambda (SQS Bridge) → Firehose → Lambda (Transform) → OpenSearch
                                      ↓
                                  S3 (Failed Records)
```

## Usage

```hcl
module "my_analytics" {
  source = "./modules/firehose-analytics"
  
  name = "my-pipeline"
  source_queue_arn = aws_sqs_queue.events.arn
  opensearch_domain_arn = aws_opensearch_domain.main.arn
  
  transform = {
    fields = ["timestamp", "user_id", "event_type"]
    mappings = {
      "@timestamp" = "timestamp"
      "user.id" = "user_id"
      "event.type" = "event_type"
    }
  }
  
  opensearch = {
    index_name = "events"
  }
}
```

## What It Replaces

**Before (Logstash):**
```ruby
input {
  sqs { queue => "events" }
}
filter {
  mutate {
    rename => { "user_id" => "[user][id]" }
    rename => { "timestamp" => "@timestamp" }
  }
}
output {
  elasticsearch {
    index => "events"
  }
}
```

**After (Lambda Transform):**
```javascript
// Auto-generated from your config
const transformed = {
  '@timestamp': data.timestamp,
  'user.id': data.user_id,
  'event.type': data.event_type
};
```

## Benefits

- **No infrastructure** - Fully serverless
- **Auto-scaling** - Handles 0 to massive throughput
- **Cost effective** - Pay per use, not per hour
- **Built-in DLQ** - Failed records go to S3
- **Fast deployment** - Minutes, not hours

## Deployment

```bash
terraform apply -target=module.my_analytics
```

That's it! Your pipeline is live.