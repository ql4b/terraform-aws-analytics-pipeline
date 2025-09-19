# Pre-built Lambda Assets

This directory contains pre-built Lambda function binaries to avoid:
- Build-time race conditions
- Go toolchain requirements
- Network dependencies during terraform apply

## sqs-bridge.zip

Pre-built binary from [sqs-firehose-bridge](https://github.com/ql4b/sqs-firehose-bridge)

**Build process:**
```bash
git clone https://github.com/ql4b/sqs-firehose-bridge
cd sqs-firehose-bridge
make build
cp lambda.zip ../terraform-aws-analytics-pipeline/assets/sqs-bridge.zip
```

**Update schedule:** Updated with each module release