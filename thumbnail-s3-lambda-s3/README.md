# thumbnail s3-lambda-s3

This example shows how you can 

* Trigger a lambda function when an image is added to an s3 bucket
* Use a shell based lambda function using vips to create thumbnails from the image
* Store the resulting thumbnails into s3

## Performance Results

**Production metrics from AWS CloudWatch:**

```
Cold Start:
Duration: 4604.05ms | Memory: 137MB/1024MB (13%) | Init: 155.20ms

Warm Container:
Duration: 4438.02ms | Memory: 134MB/1024MB (13%) | Init: 66.64ms
```

**Key insights:**
- **87% memory efficiency** - only 137MB used for complete image processing
- **155ms cold start** - incredibly fast for container image with full AWS CLI
- **57% faster warm starts** - container reuse provides significant benefits
- **Consistent performance** - stable memory usage across invocations

## Runtime choice

We use the `full` variant of lambda-shell-runtime because:
- **tiny** (132MB): jq, curl, http-cli - insufficient for S3 operations
- **micro** (221MB): adds awscurl - **corrupts binary data** (PNG files 70% larger)
- **full** (417MB): complete AWS CLI - **handles binary files correctly**

**Critical discovery:** awscurl corrupts binary image files during download, making them unreadable by vips. The AWS CLI properly handles binary data, making the full variant essential for image processing workflows.

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

Since we need to add the tools to perform image manipulation we can use the `terraform-aws-lambda-runtime` module. 

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

We will deploy a single function and we don't need HTTP Api integration so we can use the `terraform-aws-lambda-function` module with container image support:

```hcl
# main.tf
module "lambda_function" {
  source = "git::ssh://github.com/ql4b/terraform-aws-lambda-function.git"

  package_type = "Image"
  image_uri = "${module.lambda_runtime.repository_url}@${data.aws_ecr_image.lambda_image.image_digest}"
  
  memory_size = 1024
  timeout     = 300
  
  image_config = {
    command = ["handler.thumb"]
  }
  
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
touch app/src/.gitkeep
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
```

### Critical IAM Permissions Discovery

Initially, our Lambda function was timing out on S3 downloads. The issue wasn't network timeouts - it was missing IAM permissions.

**Insufficient permissions:**
```hcl
{
  Effect = "Allow"
  Action = ["s3:GetObject"]
  Resource = "${module.source_bucket.bucket_arn}/*"
}
```

**Required permissions:**
```hcl
# IAM permissions for Lambda to access S3
resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "${module.label.id}-s3-access"
  role = module.lambda_function.execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${module.source_bucket.bucket_arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = module.source_bucket.bucket_arn  # Note: no /* suffix
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:PutObjectAcl"]
        Resource = "${module.thumbnails_bucket.bucket_arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = module.thumbnails_bucket.bucket_arn
      }
    ]
  })
}
```

**Key insight:** AWS CLI's `s3 cp` command requires `s3:ListBucket` permission on the bucket ARN (not `/*`) to verify object existence before downloading. This permission is often overlooked but essential for proper S3 operations.

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

## Shell Handler

Now let's create the shell handler that processes S3 events and generates thumbnails:

```bash
# app/src/handler.sh
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
    
    /usr/bin/vipsthumbnail "$input_file" --size="$size" --output="$output_file"
}

# Main handler function
thumb() {
    local event="$1"
    
    # Parse S3 event
    local bucket_key
    bucket_key=$(parse_s3_event "$event")
    local source_bucket="${bucket_key%|*}"
    local object_key="${bucket_key#*|}"
    
    echo "Processing: s3://$source_bucket/$object_key" >&2
    
    # Download image from S3 using AWS CLI
    local input_file="/tmp/input_$(basename "$object_key")"
    aws s3 cp "s3://$source_bucket/$object_key" "$input_file" \
        --cli-read-timeout 20 \
        --cli-connect-timeout 10
    
    # Generate thumbnail
    local thumbnail_file="/tmp/thumb_$(basename "$object_key")"
    generate_thumbnail "$input_file" "$thumbnail_file" "200x200"
    
    # Upload thumbnail to destination bucket
    local thumbnails_bucket="${source_bucket/-source/-thumbnails}"
    local thumbnail_key="thumbnails/$object_key"
    
    aws s3 cp "$thumbnail_file" "s3://$thumbnails_bucket/$thumbnail_key"
    
    # Cleanup
    rm -f "$input_file" "$thumbnail_file"
    
    echo '{
        "statusCode": 200,
        "body": {
            "message": "Thumbnail generated successfully",
            "source": "'$source_bucket/$object_key'",
            "thumbnail": "'$thumbnails_bucket/$thumbnail_key'"
        }
    }'
}
```

## Runtime Configuration

We use vips for high-performance image processing:

```dockerfile
# app/Dockerfile
FROM ghcr.io/ql4b/lambda-shell-runtime:full

# Install vips for high-performance image processing
RUN dnf install -y vips-tools && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Copy function code
COPY src/ /var/task/

# Set handler
CMD ["handler.thumb"]
```

## Deploy and Test

```bash
# Build and push runtime image
./deploy

# Test by uploading an image
aws s3 cp test-image.jpg s3://$(cd infra && tf output -raw source_bucket.bucket_id)/

# Check thumbnail was created
aws s3 ls s3://$(cd infra && tf output -raw thumbnails_bucket.bucket_id)/thumbnails/
```

This example demonstrates:
- **S3 event triggers** for Lambda functions
- **`full` runtime** usage with AWS CLI for S3 operations
- **vips integration** for image processing
- **Shell-first approach** for file processing workflows
- **Real-world AWS service integration** patterns
- **Container image deployment** with enhanced Terraform modules

## Example S3 Event

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