module "label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  namespace = local.namespace
  name      = local.name
}

data "aws_caller_identity" "current" {}

locals {
  profile    = var.profile
  region     = var.region
  identity   = data.aws_caller_identity.current
  account_id = local.identity.account_id
  name       = var.name
  namespace  = var.namespace
  id         = module.label.id
  # prefixes
  ssm_prefix = "${"/"}${join("/", compact([
    module.label.namespace != "" ? module.label.namespace : null,
    module.label.name != "" ? module.label.name : null
  ]))}"
  pascal_prefix      = replace(title(module.label.id), "/\\W+/", "")
}


module "lambda_runtime" {
  source = "git::ssh://github.com/ql4b/terraform-aws-lambda-runtime.git?ref=develop"
  
  deploy_tag = "latest"
  context = module.label.context
  attributes = ["runtime"]
}

data "aws_ecr_image" "lambda_image" {
  repository_name = module.lambda_runtime.ecr.repository_name
  image_tag       = "latest"
}

module "lambda_function" {
  source = "git::ssh://github.com/ql4b/terraform-aws-lambda-function.git"

  source_dir       = "../app/src"
  template_dir     = "../app/template"
  create_templates = true

  context    = module.label.context
  attributes = ["lambda"]

  package_type = "Image"
  image_uri = "${module.lambda_runtime.repository_url}@${data.aws_ecr_image.lambda_image.image_digest}"

  # environment_variables = {
  #   TIMESTAMP = timestamp()
  # }

  memory_size  = 1024
  timeout      =  300
  
  image_config = {
    # entry_point = ["/lambda-entrypoint.sh"]
    command     = ["handler.thumb"]
  }
    
}

module "source_bucket" {
  source = "cloudposse/s3-bucket/aws"
  version = "~> 4.0"
  
  context = module.label.context
  attributes = ["source"]
  
  versioning_enabled = false
  force_destroy = true
}

module "thumbnails_bucket" {
  source = "cloudposse/s3-bucket/aws"
  version = "~> 4.0"
  
  context = module.label.context
  attributes = ["thumbnails"]
  
  versioning_enabled = false
  force_destroy = true
}


# S3 trigger for Lambda
resource "aws_s3_bucket_notification" "image_upload" {
  bucket = module.source_bucket.bucket_id

  lambda_function {
    lambda_function_arn = module.lambda_function.function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ".jpg"
  }

  lambda_function {
    lambda_function_arn = module.lambda_function.function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ".png"
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

# Permission for S3 to invoke Lambda
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_function.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.source_bucket.bucket_arn
}

# IAM permissions for Lambda to access S3
resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "${module.label.id}-s3-access"
  role = module.lambda_function.execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${module.source_bucket.bucket_arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = module.source_bucket.bucket_arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${module.thumbnails_bucket.bucket_arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = module.thumbnails_bucket.bucket_arn
      }
    ]
  })
}