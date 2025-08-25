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
    type = string  # "sns", "api_gateway", "eventbridge", "lambda"
    arn  = string
  }))
  default = []
}

variable "sqs_bridge_image_uri" {
  description = "URI of the sqs-bridge image"
  type        = string
  default     = "public.ecr.aws/ql4b/sqs-firehose-bridge:latest"
}

variable "sqs_bridge_command" {
  description = "Command to run sqs-bridge"
  type        = list(string)
  default     = ["handler.run"]
}