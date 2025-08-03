# thumbnail s3-lambda-s3

This example shows how you can 

* Trigger a lambda function when ad image is added to an s3 bucket
* Use a shell based lambda function using an imagemagick layer to create thumbnails from the image
* Store the resulting thumbnails into s3


## Runtime choice

## Setup


Bootstrap using `cloudless-infra` 

```bash
# Bootstrap into existing project
curl -sL https://raw.githubusercontent.com/ql4b/cloudless-infra/main/bootstrap | bash

```

Edit `.env`

```bash
AWS_PROFILE=ql4b
AWS_REGION=us-east-1
NAMESPACE=cloudless-examples
NAME=thumbnails

TF_VAR_name=${NAME}
TF_VAR_namespace=${NAMESPACE}
TF_VAR_region=${AWS_REGION}
TF_VAR_profile=${AWS_PROFILE}


TERRAFORM_VERSION="v1.12.2"
TERRAFORM_BIN="/usr/local/bin/terraform-$TERRAFORM_VERSION"
```

```bash
set -a
source .env
PATH="$(pwd):$PATH"
set +a
```

Since we need to add the tools to perform image manipulation we can use the `aws-terraform-aws-lambda-runtime`  module. 

```hcl
#main.tf 
module "lambda_runtime" {
  source = "git::ssh://github.com/ql4b/terraform-aws-lambda-runtime.git?ref=develop"
  
  deploy_tag = "latest"
  context = module.label.context
  attributes = ["runtime"]
}
# output.tf
output runtime {
    value = module.lambda_runtime
}
```

We will deploy a single function and we don't need HTTP Api integration so we can use the `aws-terraform-lambda-funtction module`

```hcl
# main.tf
module "lambda_function" {
  source = "git::ssh://github.com/ql4b/terraform-aws-lambda-function.git"

  source_dir       = "../app/src"
  template_dir     = "../app/src"
  create_templates = true
  
  context    = module.label.context
  attributes = ["lambda"]
    
}
# output.tf
output lambda {
    value = module.lambda_function

}
```

```bash
mkdir -p app/src
touc app/src/.gitkeep
tf init
tf apply
```

Now we need to add the S3 buckets for source images and thumbnails:

```hcl
# main.tf
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
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${module.thumbnails_bucket.bucket_arn}/*"
      }
    ]
  })
}
```

```hcl
# output.tf
output source_bucket {
  value = module.source_bucket
}

output thumbnails_bucket {
  value = module.thumbnails_bucket
}
```

```bash
tf apply
```

```
env = {
  "account_id" = "703177223665"
  "id" = "cloudless-examples-thumbnails"
  "name" = "thumbnails"
  "namespace" = "cloudless-examples"
  "profile" = "ql4b"
  "region" = "us-east-1"
}
lambda = {
  "execution_role_arn" = "arn:aws:iam::703177223665:role/cloudless-examples-thumbnails-lambda-execution"
  "execution_role_name" = "cloudless-examples-thumbnails-lambda-execution"
  "function_arn" = "arn:aws:lambda:us-east-1:703177223665:function:cloudless-examples-thumbnails-lambda"
  "function_invoke_arn" = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:703177223665:function:cloudless-examples-thumbnails-lambda/invocations"
  "function_last_modified" = "2025-08-02T23:23:22.522+0000"
  "function_name" = "cloudless-examples-thumbnails-lambda"
  "function_qualified_arn" = "arn:aws:lambda:us-east-1:703177223665:function:cloudless-examples-thumbnails-lambda:$LATEST"
  "function_source_code_hash" = "hYek/xVZpI6gTPT6ehCvBILMWdUlgOSwIhG5S0UZeRA="
  "function_source_code_size" = 1591
  "function_version" = "$LATEST"
  "log_group_arn" = "arn:aws:logs:us-east-1:703177223665:log-group:/aws/lambda/cloudless-examples-thumbnails-lambda"
  "log_group_name" = "/aws/lambda/cloudless-examples-thumbnails-lambda"
  "package_path" = ".terraform/modules/lambda_function/.terraform/tmp/cloudless-examples-thumbnails-lambda.zip"
  "package_size" = 1591
  "ssm_parameters" = {
    "function_arn" = "/cloudless-examples-thumbnails-lambda/function_arn"
    "function_name" = "/cloudless-examples-thumbnails-lambda/function_name"
    "invoke_arn" = "/cloudless-examples-thumbnails-lambda/invoke_arn"
  }
  "template_files" = tomap({
    "bootstrap" = "../app/src/bootstrap"
    "handler" = "../app/src/handler.sh"
    "makefile" = "../app/src/Makefile"
  })
}
runtime = {
  "ecr" = {
    "registry_id" = "703177223665"
    "repository_arn" = "arn:aws:ecr:us-east-1:703177223665:repository/cloudless-examples-thumbnails-runtime-lambda-runtime"
    "repository_arn_map" = {
      "cloudless-examples-thumbnails-runtime-lambda-runtime" = "arn:aws:ecr:us-east-1:703177223665:repository/cloudless-examples-thumbnails-runtime-lambda-runtime"
    }
    "repository_name" = "cloudless-examples-thumbnails-runtime-lambda-runtime"
    "repository_url" = "703177223665.dkr.ecr.us-east-1.amazonaws.com/cloudless-examples-thumbnails-runtime-lambda-runtime"
    "repository_url_map" = {
      "cloudless-examples-thumbnails-runtime-lambda-runtime" = "703177223665.dkr.ecr.us-east-1.amazonaws.com/cloudless-examples-thumbnails-runtime-lambda-runtime"
    }
  }
  "image" = {
    "arn" = "arn:aws:ecr:us-east-1:703177223665:repository/cloudless-examples-thumbnails-runtime-lambda-runtime:latest"
    "name" = "703177223665.dkr.ecr.us-east-1.amazonaws.com/cloudless-examples-thumbnails-runtime-lambda-runtime:latest"
    "ssm_name" = "/cloudless-examples/thumbnails/runtime/image"
  }
  "repository_arn" = "arn:aws:ecr:us-east-1:703177223665:repository/cloudless-examples-thumbnails-runtime-lambda-runtime"
  "repository_url" = "703177223665.dkr.ecr.us-east-1.amazonaws.com/cloudless-examples-thumbnails-runtime-lambda-runtime"
}
source_bucket = {
  "bucket_arn" = "arn:aws:s3:::cloudless-examples-thumbnails-source"
  "bucket_id" = "cloudless-examples-thumbnails-source"
  "bucket_domain_name" = "cloudless-examples-thumbnails-source.s3.amazonaws.com"
}
thumbnails_bucket = {
  "bucket_arn" = "arn:aws:s3:::cloudless-examples-thumbnails-thumbnails"
  "bucket_id" = "cloudless-examples-thumbnails-thumbnails"
  "bucket_domain_name" = "cloudless-examples-thumbnails-thumbnails.s3.amazonaws.com"
}
```

## Shell Handler

Now let's create the shell handler that processes S3 events and generates thumbnails:

```bash
# app/src/handler.sh
#!/bin/bash
set -euo pipefail

# Parse S3 event and extract bucket/key
parse_s3_event() {
    local event="$1"
    echo "$event" | jq -r '.Records[0].s3.bucket.name + "|" + .Records[0].s3.object.key'
}

# Generate thumbnail using compiled vips
generate_thumbnail() {
    local input_file="$1"
    local output_file="$2"
    local size="${3:-200}"
    
    /usr/bin/vipsthumbnail "$input_file" --size="$size" --output="$output_file" -Q 85
}

# Main handler function
thumbnail_handler() {
    local event="$1"
    
    # Parse S3 event
    local bucket_key
    bucket_key=$(parse_s3_event "$event")
    local source_bucket="${bucket_key%|*}"
    local object_key="${bucket_key#*|}"
    
    echo "Processing: s3://$source_bucket/$object_key"
    
    # Download image from S3
    local input_file="/tmp/input_$(basename "$object_key")"
    awscurl --service s3 "https://s3.amazonaws.com/$source_bucket/$object_key" > "$input_file"
    
    # Generate thumbnail
    local thumbnail_file="/tmp/thumb_$(basename "$object_key")"
    generate_thumbnail "$input_file" "$thumbnail_file" "200x200"
    
    # Upload thumbnail to destination bucket
    local thumbnails_bucket="${source_bucket/-source/-thumbnails}"
    local thumbnail_key="thumbnails/$object_key"
    
    awscurl --service s3 \
        --method PUT \
        --data-binary "@$thumbnail_file" \
        "https://s3.amazonaws.com/$thumbnails_bucket/$thumbnail_key"
    
    # Cleanup
    rm -f "$input_file" "$thumbnail_file"
    
    echo '{
        "statusCode": 200,
        "body": {
            "message": "Thumbnail generated successfully",
            "source": "'"$source_bucket/$object_key"'",
            "thumbnail": "'"$thumbnails_bucket/$thumbnail_key"'"
        }
    }'
}

# Call handler with event data
thumbnail_handler "$1"
```

## Runtime Configuration

We use a minimal ImageMagick install to keep the runtime size reasonable:

```dockerfile
# app/Dockerfile
FROM ghcr.io/ql4b/lambda-shell-runtime:full

# Install ImageMagick for image processing
RUN dnf update -y && \
    dnf install -y ImageMagick && \
    dnf clean all && \
    rm -rf /var/cache/dnf /tmp/* /var/tmp/*

# Copy function code
COPY src/ /var/task/

# Set handler
CMD ["handler.thumbnail_handler"]
```

Using `ffmpeg` for image processing - more commonly available and lighter than ImageMagick.

## Deploy and Test

```bash
# Build and push runtime image
cd app
docker build -t $(tf output -json runtime | jq -r .repository_url):latest .
# Login to ecr 
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $(tf output -json runtime | jq -r .repository_url | cut -d'/' -f1)

docker push $(tf output -json runtime | jq -r .repository_url):latest

# Update Lambda function
cd ../infra
tf apply

# Test by uploading an image
aws s3 cp test-image.jpg s3://$(tf output -raw source_bucket.bucket_id)/

# Check thumbnail was created
aws s3 ls s3://$(tf output -raw thumbnails_bucket.bucket_id)/thumbnails/
```

This example demonstrates:
- **S3 event triggers** for Lambda functions
- **`micro` runtime** usage with `awscurl` for S3 operations
- **ImageMagick integration** for image processing
- **Shell-first approach** for file processing workflows
- **Real-world AWS service integration** patterns
```

Example event

```json
{
  "Records": [
    {
      "eventVersion": "2.1",
      "eventSource": "aws:s3",
      "awsRegion": "us-east-1",
      "eventTime": "2025-08-03T05:23:55.551Z",
      "eventName": "ObjectCreated:Put",
      "userIdentity": {
        "principalId": "AWS:AIDA2HOFA5XY5FWNKXQGU"
      },
      "requestParameters": {
        "sourceIPAddress": "79.153.75.24"
      },
      "responseElements": {
        "x-amz-request-id": "6TK8D8BYJ7W9XGZK",
        "x-amz-id-2": "Nf6VC73B1tSoVqVjY/s1DuNxtn4vfyilH/UDtxFOFS9+IKX3kMTVa7ygSASY4bGwOaz/tBf+RyBnsYit3ptfMOfVbeCUASx8L/bDsWxkDIk="
      },
      "s3": {
        "s3SchemaVersion": "1.0",
        "configurationId": "tf-s3-lambda-20250803041823336000000001",
        "bucket": {
          "name": "cloudless-examples-thumbnails-source",
          "ownerIdentity": {
            "principalId": "A7NNOKBUOQWTA"
          },
          "arn": "arn:aws:s3:::cloudless-examples-thumbnails-source"
        },
        "object": {
          "key": "source.png",
          "size": 171094,
          "eTag": "5e59897841d62e8005179d2d3ed0a8b2",
          "sequencer": "00688EF26B3A0222AA"
        }
      }
    }
  ]
}
```