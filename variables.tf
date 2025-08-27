variable "create_queue" {
  description = "Whether to create SQS queue (true) or use existing (false)"
  type        = bool
  default     = true
}

variable "existing_queue_arn" {
  description = "ARN of existing SQS queue (only if create_queue = false)"
  type        = string
  default     = null
}

variable "queue_config" {
  description = "SQS queue configuration"
  type = object({
    visibility_timeout_seconds = optional(number, 300)
    message_retention_seconds  = optional(number, 1209600)  # 14 days
    max_receive_count          = optional(number, 3)
    batch_size                 = optional(number, 10)
  })
  default = {}
}

variable "data_sources" {
  description = "Data sources that will send to this pipeline"
  type = list(object({
    type = string  # "sns", "eventbridge", "lambda"
    arn  = string
  }))
  default = []
}

variable "sqs_bridge_image_uri" {
  description = "URI of the sqs-bridge image (must be private ECR in same account)"
  type        = string
  default     = null
}

variable "sqs_bridge_command" {
  description = "Command to run sqs-bridge"
  type        = list(string)
  default     = ["handler.run"]
}

variable "enable_transform" {
  description = "Enable Lambda data transformation"
  type        = bool
  default     = false
}

variable "transform_template" {
  description = "Transform template to use (transform.js or sns-transform.js)"
  type        = string
  default     = "transform.js"
}

variable "transform" {
  description = "Data transformation configuration"
  type = object({
    # Basic field operations
    fields   = optional(list(string), [])
    mappings = optional(map(string), {})
    
    # Advanced transformations (EventBridge-style)
    input_paths = optional(map(string), {})  # Extract nested values
    input_template = optional(string, null)   # JSON template with placeholders
    
    # Custom JavaScript functions
    custom_functions = optional(list(object({
      name = string
      code = string
    })), [])
    
    # Conditional logic
    conditions = optional(list(object({
      field     = string
      operator  = string  # eq, ne, gt, lt, contains, exists
      value     = string
      then_map  = map(string)
      else_map  = optional(map(string), {})
    })), [])
    
    # Data enrichment
    enrich = optional(object({
      add_fields = optional(map(string), {})
      remove_fields = optional(list(string), [])
      parse_json_fields = optional(list(string), [])
    }), {})
  })
  default = {
    fields   = []
    mappings = {}
  }
}

variable "enable_opensearch" {
  description = "Enable OpenSearch destination"
  type        = bool
  default     = false
}

variable "opensearch_config" {
  description = "OpenSearch configuration"
  type = object({
    domain_arn            = string
    index_name            = optional(string, "analytics")
    index_rotation_period = optional(string, "OneMonth") 
    buffering_size        = optional(number, 5)
    buffering_interval    = optional(number, 60)
  })
  default = {
    domain_arn = "-"
  }
}

variable "sqs_bridge_public_image" {
  type    = string
  default = "public.ecr.aws/ql4b/sqs-firehose-bridge:latest" 
}

