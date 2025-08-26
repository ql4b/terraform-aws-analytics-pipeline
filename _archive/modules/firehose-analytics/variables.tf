variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

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
    max_receive_count         = optional(number, 3)
    batch_size               = optional(number, 10)
  })
  default = {}
}

variable "opensearch_domain_arn" {
  description = "ARN of the OpenSearch domain"
  type        = string
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

variable "opensearch" {
  description = "OpenSearch index configuration"
  type = object({
    index_name = string
  })
}

variable "buffering" {
  description = "Firehose buffering configuration"
  type = object({
    interval_seconds = number
    size_mb         = number
  })
  default = {
    interval_seconds = 60
    size_mb         = 5
  }
}

variable "data_sources" {
  description = "Data sources that will send to this pipeline"
  type = list(object({
    type = string  # "sns", "api_gateway", "eventbridge", "lambda"
    arn  = string
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "transform_template" {
  description = "Custom transform template file path (overrides built-in template)"
  type        = string
  default     = null
}