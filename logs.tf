# CloudWatch log group for Firehose
resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${join("-", [local.id, "firehose"])}"
  retention_in_days = 7
  tags              = module.this.tags
}

resource "aws_cloudwatch_log_stream" "firehose_s3" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

# CloudWatch log group for OpenSearch Firehose
resource "aws_cloudwatch_log_group" "firehose_opensearch" {
  count             = var.enable_opensearch ? 1 : 0
  name              = "/aws/kinesisfirehose/${local.id}-opensearch"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "firehose_opensearch" {
  count          = var.enable_opensearch ? 1 : 0
  name           = "opensearch-delivery"
  log_group_name = aws_cloudwatch_log_group.firehose_opensearch[0].name
}

resource "aws_cloudwatch_log_stream" "firehose_opensearch_s3" {
  count          = var.enable_opensearch ? 1 : 0
  name           = "s3-backup"
  log_group_name = aws_cloudwatch_log_group.firehose_opensearch[0].name
}