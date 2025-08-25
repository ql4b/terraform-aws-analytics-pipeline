resource "aws_iam_role" "firehose_role" {
  name = join("-", [module.this.id, "firehose-role" ])

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
}

locals {
  firehose_statements = concat([
    {
      Effect = "Allow"
      Action = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject"
      ]
      Resource = [
        aws_s3_bucket.backup.arn,
        "${aws_s3_bucket.backup.arn}/*"
      ]
    },
    {
      Effect = "Allow"
      Action = [
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:*:*:*"
    }
  ], var.enable_transform ? [{
    Effect = "Allow"
    Action = [
      "lambda:InvokeFunction"
    ]
    Resource = module.transform[0].function_arn
  }] : [])
}

resource "aws_iam_role_policy" "firehose_policy" {
  name = join("-", [module.this.id, "firehose-policy" ])
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = local.firehose_statements
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = join("-", [module.this.id, "lambda-policy" ])
  role = module.sqs_bridge_lambda.execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = local.queue_arn
      },
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.main.arn
      }
    ]
  })
}