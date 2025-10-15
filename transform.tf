
# Create transform source directory
resource "local_file" "transform_js" {
  count    = local.enable_transform ? 1 : 0
  filename = "/tmp/${module.this.id}-transform-src/index.js"
  content = templatefile("${path.module}/templates/${local.transform_template}", {
    mappings = local.transform.mappings
    fields   = local.transform.fields
  })
}

# Transform Lambda using terraform-aws-lambda-function module
module "transform" {
  count     = local.enable_transform ? 1 : 0
  # checkov:skip=CKV_TF_1: Source is from trusted repository
  source      = "git::https://github.com/ql4b/terraform-aws-lambda-function.git?ref=v1.0.0"
  
  source_dir = "/tmp/${module.this.id}-transform-src"
  
  handler     = "index.handler"
  runtime     = "nodejs22.x"
  timeout     = 60
  memory_size = 256
  
  context    = module.this.context
  attributes = ["transform"]
  
  depends_on = [local_file.transform_js]
}