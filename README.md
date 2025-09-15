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

- **SQS to Firehose Bridge** - Reliable message processing with batching
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

### 2. Deploy SQS Bridge Image

The module automatically creates a private ECR repository for the SQS bridge image. On first `terraform apply`, it will fail with helpful instructions:

```bash
# First apply creates ECR repository and fails with instructions
terraform apply

# Follow the provided commands to push the image:
aws ecr get-login-password | docker login --username AWS --password-stdin <ecr-registry-url>
docker pull public.ecr.aws/ql4b/sqs-firehose-bridge:latest
docker tag public.ecr.aws/ql4b/sqs-firehose-bridge:latest "<repository-url>:latest"
docker push <repository-url>:latest

# Re-apply to create the Lambda function
terraform apply
```

The module includes:
- **Automatic ECR repository creation** with proper naming
- **Image existence checking** to prevent incomplete deployments  
- **Fail-fast behavior** with clear push instructions
- **Automatic Lambda creation** once image is available

**Note**: The single Firehose stream automatically delivers data to both S3 and OpenSearch when `enable_opensearch = true`.

## Deployment Workflow

The module uses a **fail-fast approach** for better UX:

1. **First Apply**: Creates ECR repository and fails with push instructions
2. **Push Image**: Follow the provided commands to push the SQS bridge image
3. **Second Apply**: Creates Lambda function and completes the pipeline

### Why Two-Step Apply?

The two-step process is necessary because:

- **ECR Repository Must Exist First**: The repository needs to be created before you can push an image to it
- **Lambda Requires Valid Image URI**: Lambda functions with `package_type = "Image"` must reference an existing image
- **Terraform Dependency Chain**: The Lambda resource depends on the image existing, but Terraform can't push Docker images natively
- **Better Error Handling**: Instead of a cryptic Lambda deployment failure, you get clear instructions on what to do

This ensures:
- **No incomplete deployments** - Lambda won't be created without the image
- **Clear error messages** - Exact commands provided for image push
- **Automatic detection** - Module checks if image exists before proceeding
- **Consistent naming** - ECR repository follows module naming conventions

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

- `sqs_bridge_ecr.repository_url` - Private ECR repository for the bridge image
- `sqs_bridge.function_name` - Lambda function name (when image exists)
- `sqs_bridge.function_arn` - Lambda function ARN (when image exists)
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

# After first apply, push the image:
# aws ecr get-login-password | docker login --username AWS --password-stdin <registry>
# docker pull public.ecr.aws/ql4b/sqs-firehose-bridge:latest
# docker tag public.ecr.aws/ql4b/sqs-firehose-bridge:latest <repo-url>:latest
# docker push <repo-url>:latest
# terraform apply  # Complete the deployment
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