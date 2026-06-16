# terraform-aws-analytics-pipeline

> Complete analytics pipeline from SQS to S3 and OpenSearch with optional data transformation

Terraform module that creates a complete analytics pipeline: SQS → Lambda Bridge → Kinesis Data Firehose → S3 + OpenSearch, with optional Lambda data transformation.

![analytics-pipeline](https://raw.githubusercontent.com/ql4b/terraform-aws-analytics-pipeline/main/doc/analytics-pipeline-v2.jpg)


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
- **Dynamic Partitioning** - Inline JQ metadata extraction for S3 prefix partitioning
- **Dual Destinations** - S3 storage + OpenSearch analytics in single stream
- **SNS Integration** - Built-in support for SNS message unwrapping
- **Multi-source Support** - SNS (only SNS for now but will add more)
- **Minimal Configuration** - Sensible defaults, easy customization

## Quick Start

### 1. Deploy Infrastructure

```hcl
module "analytics" {
  source  = "ql4b/analytics-pipeline/aws"
  version = "~> 1.0"
  
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

### Dynamic Partitioning

Use `dynamic_partitioning_keys` to extract partition keys from records using JQ expressions. This enables Firehose to route records into different S3 prefixes based on record content.

```hcl
module "analytics" {
  source  = "ql4b/analytics-pipeline/aws"
  version = "~> 1.0"

  context = module.label.context

  enable_dynamic_partitioning = true
  dynamic_partitioning_keys   = "{repo: .repo}"
  prefix                      = "raw-data/repo=!{partitionKeyFromQuery:repo}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"

  data_sources = [{
    type = "sns"
    arn  = aws_sns_topic.events.arn
  }]
}
```

The JQ expression defines which fields become partition keys. The extracted keys are referenced in `prefix` via `!{partitionKeyFromQuery:<key>}`.

Multiple keys:

```hcl
dynamic_partitioning_keys = "{source: .source, metric: .metric}"
prefix                    = "raw-data/source=!{partitionKeyFromQuery:source}/metric=!{partitionKeyFromQuery:metric}/"
```

Can be combined with `enable_transform = true` — both Lambda and MetadataExtraction processors will be applied.

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
  source  = "ql4b/analytics-pipeline/aws"
  version = "~> 1.0"
  
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
  source  = "ql4b/analytics-pipeline/aws"
  version = "~> 1.0"
  
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
  source  = "ql4b/analytics-pipeline/aws"
  version = "~> 1.0"
  
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
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.25.0 |
| <a name="provider_aws.sns_source"></a> [aws.sns\_source](#provider\_aws.sns\_source) | 6.25.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.6.1 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_sqs_bridge_lambda"></a> [sqs\_bridge\_lambda](#module\_sqs\_bridge\_lambda) | ql4b/lambda-function/aws | ~> 1.0 |
| <a name="module_this"></a> [this](#module\_this) | cloudposse/label/null | 0.25.0 |
| <a name="module_transform"></a> [transform](#module\_transform) | ql4b/lambda-function/aws | ~> 1.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.firehose](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.firehose_opensearch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_stream.firehose_opensearch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_stream) | resource |
| [aws_cloudwatch_log_stream.firehose_opensearch_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_stream) | resource |
| [aws_cloudwatch_log_stream.firehose_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_stream) | resource |
| [aws_iam_role.firehose_opensearch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.firehose_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.firehose_opensearch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.firehose_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.lambda_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_kinesis_firehose_delivery_stream.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kinesis_firehose_delivery_stream) | resource |
| [aws_lambda_event_source_mapping.sqs_bridge_trigger](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping) | resource |
| [aws_s3_bucket.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_sns_topic_subscription.sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_sqs_queue.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [local_file.transform_js](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_buffering_interval"></a> [buffering\_interval](#input\_buffering\_interval) | Firehose buffer interval in seconds. | `number` | `300` | no |
| <a name="input_buffering_size"></a> [buffering\_size](#input\_buffering\_size) | Firehose buffer size in MB. Minimum 64 when dynamic partitioning is enabled. | `number` | `5` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object for setting entire context at once.<br/>See description of individual variables for details.<br/>Leave string and numeric variables as `null` to use default value.<br/>Individual variable settings (non-null) override settings in context object,<br/>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_create_queue"></a> [create\_queue](#input\_create\_queue) | Whether to create SQS queue (true) or use existing (false) | `bool` | `true` | no |
| <a name="input_data_sources"></a> [data\_sources](#input\_data\_sources) | Data sources that will send to this pipeline | <pre>list(object({<br/>    type = string  # "sns", "eventbridge", "lambda"<br/>    arn  = string<br/>  }))</pre> | `[]` | no |
| <a name="input_delimiter"></a> [delimiter](#input\_delimiter) | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| <a name="input_descriptor_formats"></a> [descriptor\_formats](#input\_descriptor\_formats) | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>   format = string<br/>   labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| <a name="input_dynamic_partitioning_keys"></a> [dynamic\_partitioning\_keys](#input\_dynamic\_partitioning\_keys) | JQ expression for dynamic partitioning metadata extraction (e.g. '{repo: .repo}'). | `string` | `null` | no |
| <a name="input_dynamic_partitioning_retry_duration_seconds"></a> [dynamic\_partitioning\_retry\_duration\_seconds](#input\_dynamic\_partitioning\_retry\_duration\_seconds) | Retry duration for dynamic partitioning (in seconds) | `number` | `300` | no |
| <a name="input_enable_dynamic_partitioning"></a> [enable\_dynamic\_partitioning](#input\_enable\_dynamic\_partitioning) | Enable dynamic partitioning in Firehose | `bool` | `false` | no |
| <a name="input_enable_opensearch"></a> [enable\_opensearch](#input\_enable\_opensearch) | Enable OpenSearch destination | `bool` | `false` | no |
| <a name="input_enable_transform"></a> [enable\_transform](#input\_enable\_transform) | Enable Lambda data transformation | `bool` | `false` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| <a name="input_existing_queue_arn"></a> [existing\_queue\_arn](#input\_existing\_queue\_arn) | ARN of existing SQS queue (only if create\_queue = false) | `string` | `null` | no |
| <a name="input_id_length_limit"></a> [id\_length\_limit](#input\_id\_length\_limit) | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| <a name="input_label_key_case"></a> [label\_key\_case](#input\_label\_key\_case) | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| <a name="input_label_value_case"></a> [label\_value\_case](#input\_label\_value\_case) | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| <a name="input_labels_as_tags"></a> [labels\_as\_tags](#input\_labels\_as\_tags) | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_opensearch_config"></a> [opensearch\_config](#input\_opensearch\_config) | OpenSearch configuration | <pre>object({<br/>    domain_arn            = string<br/>    index_name            = optional(string, "analytics")<br/>    index_rotation_period = optional(string, "OneMonth") <br/>    buffering_size        = optional(number, 5)<br/>    buffering_interval    = optional(number, 60)<br/>  })</pre> | <pre>{<br/>  "domain_arn": "-"<br/>}</pre> | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | S3 prefix for Firehose delivery | `string` | `"raw-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"` | no |
| <a name="input_queue_config"></a> [queue\_config](#input\_queue\_config) | SQS queue configuration | <pre>object({<br/>    visibility_timeout_seconds = optional(number, 300)<br/>    message_retention_seconds  = optional(number, 1209600)  # 14 days<br/>    max_receive_count          = optional(number, 3)<br/>    batch_size                 = optional(number, 10)<br/>  })</pre> | `{}` | no |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |
| <a name="input_transform"></a> [transform](#input\_transform) | Data transformation configuration | <pre>object({<br/>    # Basic field operations<br/>    fields   = optional(list(string), [])<br/>    mappings = optional(map(string), {})<br/>    <br/>    # Advanced transformations (EventBridge-style)<br/>    input_paths = optional(map(string), {})  # Extract nested values<br/>    input_template = optional(string, null)   # JSON template with placeholders<br/>    <br/>    # Custom JavaScript functions<br/>    custom_functions = optional(list(object({<br/>      name = string<br/>      code = string<br/>    })), [])<br/>    <br/>    # Conditional logic<br/>    conditions = optional(list(object({<br/>      field     = string<br/>      operator  = string  # eq, ne, gt, lt, contains, exists<br/>      value     = string<br/>      then_map  = map(string)<br/>      else_map  = optional(map(string), {})<br/>    })), [])<br/>    <br/>    # Data enrichment<br/>    enrich = optional(object({<br/>      add_fields = optional(map(string), {})<br/>      remove_fields = optional(list(string), [])<br/>      parse_json_fields = optional(list(string), [])<br/>    }), {})<br/>  })</pre> | <pre>{<br/>  "fields": [],<br/>  "mappings": {}<br/>}</pre> | no |
| <a name="input_transform_template"></a> [transform\_template](#input\_transform\_template) | Transform template to use (transform.js or sns-transform.js) | `string` | `"transform.js"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_dlq_url"></a> [dlq\_url](#output\_dlq\_url) | URL of the dead letter queue |
| <a name="output_firehose_opensearch_role_arn"></a> [firehose\_opensearch\_role\_arn](#output\_firehose\_opensearch\_role\_arn) | ARN of the Firehose IAM role for OpenSearch |
| <a name="output_firehose_role_arn"></a> [firehose\_role\_arn](#output\_firehose\_role\_arn) | ARN of the Firehose IAM role for S3 |
| <a name="output_firehose_stream_name"></a> [firehose\_stream\_name](#output\_firehose\_stream\_name) | Name of the Kinesis Data Firehose stream |
| <a name="output_queue_arn"></a> [queue\_arn](#output\_queue\_arn) | ARN of the SQS queue |
| <a name="output_queue_url"></a> [queue\_url](#output\_queue\_url) | URL of the SQS queue for sending data |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | Name of the S3 backup bucket |
| <a name="output_sqs_bridge"></a> [sqs\_bridge](#output\_sqs\_bridge) | n/a |
<!-- END_TF_DOCS -->