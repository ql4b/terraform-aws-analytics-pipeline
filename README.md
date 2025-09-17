# terraform-aws-analytics-pipeline

> Complete analytics pipeline from SQS to S3 and OpenSearch with optional data transformation

Terraform module that creates a complete analytics pipeline: SQS → Lambda Bridge → Kinesis Data Firehose → S3 + OpenSearch, with optional Lambda data transformation.

![analytics-pipeline](./doc/analytics-pipeline.jpg)


## Architecture

```
Data Sources → SQS Queue → Lambda Bridge → Kinesis Data Firehose → S3 + OpenSearch
                                              ↓
                                        Transform Lambda (optional)
```

## Features

- **Go-based SQS Bridge** - High-performance Lambda with `provided.al2023` runtime
- **No ECR Dependency** - Automatic Git clone and build from source
- **Optional Data Transformation** - Lambda-based field mapping and filtering
- **Dual Destinations** - S3 storage + OpenSearch analytics in single stream
- **SNS Integration** - Built-in support for SNS message unwrapping
- **Multi-source Support** - SNS (only SNS for now but will add more)
- **Minimal Configuration** - Sensible defaults, easy customization

## Quick Start

### 1. Deploy Infrastructure

```hcl
module "analytics" {
  source = "git::https://github.com/ql4b/terraform-aws-analytics-pipeline.git"
  
  context    = module.label.context
  attributes = ["analytics"]
  
  # Data transformation (optional)
  enable_transform   = true
  transform_template = "sns-transform.js"  # For SNS messages
  
  transform = {
    fields = ["orderID", "price", "currency"]
    mappings = {
      "@timestamp" = "created_at"
      "booking.id" = "orderID"
    }
  }
  
  # Data sources
  data_sources = [{
    type = "sns"
    arn  = aws_sns_topic.events.arn
  }]

  providers = {
    # Mandatory: always map aws.sns_source
    # Same region → point to default provider
    aws.sns_source = aws

    # Cross region → point to a specific alias, e.g.:
    # aws.sns_source = aws.virginia
  }

}
```

### 2. Deploy with Go Bridge

The module automatically clones and builds the Go-based SQS bridge:

```bash
# Single apply - no ECR setup needed
terraform apply
```

The module includes:
- **Automatic Git clone** from `sqs-firehose-bridge` repository
- **Go build process** with ARM64 optimization
- **Configurable Git ref** for version control
- **No Docker/ECR dependency** - pure Terraform workflow

**Note**: The single Firehose stream automatically delivers data to both S3 and OpenSearch when `enable_opensearch = true`.

## Deployment Workflow

The module uses a **single-step deployment** with automatic build:

1. **Single Apply**: Clones Go source, builds Lambda, and deploys complete pipeline

### Go Bridge Build Process

The build process is fully automated:

- **Git Clone**: Automatically clones from `github.com/ql4b/sqs-firehose-bridge`
- **Version Control**: Use `sqs_bridge_git_ref` to specify branch/tag
- **ARM64 Build**: Optimized for Lambda ARM64 architecture
- **Zip Packaging**: Creates minimal deployment package with only the binary
- **Dependency Management**: No ECR, Docker, or manual image management

This ensures:
- **Single command deployment** - Complete pipeline in one `terraform apply`
- **Version pinning** - Control exact source version via Git ref
- **Reproducible builds** - Same source always produces same binary
- **Minimal overhead** - No container registry or image management

## Configuration

### Transform Templates

- **`transform.js`** - Basic field mapping and filtering
- **`sns-transform.js`** - SNS message unwrapping with MessageAttributes extraction

### Transform Configuration

```hcl
transform = {
  # Fields to include (empty = all fields)
  fields = ["field1", "field2"]
  
  # Field mappings (target = source)
  mappings = {
    "@timestamp"    = "created_at"
    "booking.id"    = "orderID"
    "user.email"    = "email"
  }
}
```

#### SNS Transform Field Behavior

The `sns-transform.js` template handles field inclusion based on your configuration:

- **Case 1:** `fields = []` and `mappings = {}` → Include all original data
- **Case 2:** `fields = ["field1"]` and `mappings = {}` → Include only specified fields  
- **Case 3:** `fields = []` and `mappings = {"new": "old"}` → Include only mapped fields (no duplicates)
- **Case 4:** `fields = ["field1"]` and `mappings = {"new": "old"}` → Include specified fields + mapped fields

**Example:**
```hcl
# Case 3: Only mapped fields
transform = {
  fields = []
  mappings = {
    "order_id" = "orderId"
    "user_email" = "email"
  }
}
```

**Input:** `{"orderId": "123", "email": "user@example.com", "amount": 99.99}`

**Output:** `{"messageId": "...", "timestamp": "...", "order_id": "123", "user_email": "user@example.com"}`

*Note: `amount` is excluded because it's not in fields or mappings.*

### Data Sources

```hcl
data_sources = [
  {
    type = "sns"
    arn  = aws_sns_topic.events.arn
  }
]
```

## Outputs

- `sqs_bridge.function_name` - Lambda function name
- `sqs_bridge.function_arn` - Lambda function ARN
- `firehose_stream_name` - Main Kinesis Data Firehose stream name
- `s3_bucket_name` - S3 bucket for analytics data and failed records
- `queue_url` - SQS queue URL for sending data
- `queue_arn` - SQS queue ARN



### Components

- **SQS Queue** - Reliable message buffering with DLQ
- **Lambda Bridge** - Polls SQS and forwards to Firehose
- **Transform Lambda** - Optional data transformation (Node.js 22)
- **Kinesis Data Firehose** - Managed delivery to dual destinations
- **S3 Bucket** - Compressed, partitioned storage + failed records backup
- **OpenSearch** - Real-time analytics and dashboards

## Examples

### Basic Analytics Pipeline

```hcl
module "analytics" {
  source = "git::https://github.com/ql4b/terraform-aws-analytics-pipeline.git"
  
  context = module.label.context
  
  data_sources = [{
    type = "sns"
    arn  = aws_sns_topic.events.arn
  }]
}

# Single command deployment - no manual steps needed
# terraform apply
```

### Version Control

```hcl
module "analytics" {
  source = "git::https://github.com/ql4b/terraform-aws-analytics-pipeline.git"
  
  context = module.label.context
  
  # Pin to specific version
  sqs_bridge_git_ref = "v1.2.0"  # or "main", "develop", etc.
  
  data_sources = [{
    type = "sns"
    arn  = aws_sns_topic.events.arn
  }]
}
```

### SNS Message Processing

```hcl
module "analytics" {
  source = "git::https://github.com/ql4b/terraform-aws-analytics-pipeline.git"
  
  context = module.label.context
  
  enable_transform   = true
  transform_template = "sns-transform.js"
  
  transform = {
    fields = []  # Include all fields
    mappings = {
      "@timestamp" = "created_at"
    }
  }
  
  data_sources = [{
    type = "sns"
    arn  = aws_sns_topic.booking_events.arn
  }]
}
```

**Example SQS message:**
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "method": "POST",
  "path": "/events",
  "sourceIp": "192.168.1.1",
  "requestId": "abc-123-def",
  "body": {
    "event": "order_placed",
    "orderId": "123"
  }
}
```

## Requirements

- Terraform >= 1.0
- AWS provider >= 5.0
- Docker (for image deployment)

## License

MIT