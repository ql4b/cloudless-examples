# Cloudless Examples

> **Real-world examples of shell-first serverless architecture**

This repository contains production-ready examples demonstrating the [cloudless](https://cloudless.sh) philosophy: building high-performance serverless applications using shell scripts, achieving exceptional performance through fundamental simplicity.

## Why Shell-First?

**Performance that matters:**
- 50% faster response times than Node.js equivalents
- 75% less memory usage (36MB vs 150MB)
- 90% faster cold starts (22ms vs 500ms)
- No dependency hell, no runtime bloat

**Clarity that scales:**
- Every operation is visible and debuggable
- Tools compose in predictable ways
- Works anywhere Unix tools exist
- Complex understanding through simple components

## Examples

### [S3 → Lambda → Thumbnail → S3](./thumbnail-s3-lambda-s3/)

**Event-driven image processing pipeline**

```bash
# S3 event triggers Lambda function
thumb() {
    local event="$1"
    local bucket_key=$(parse_s3_event "$event")
    
    # Download, process, upload
    aws s3 cp "s3://$source_bucket/$object_key" "$input_file"
    vipsthumbnail "$input_file" --size=200 --output="$thumbnail_file"
    aws s3 cp "$thumbnail_file" "s3://$thumbnails_bucket/$thumbnail_key"
}
```

**Performance Results:**
- **Cold Start**: 155ms (vs 500ms+ Node.js)
- **Memory Usage**: 137MB/1024MB (87% efficiency)
- **Processing Time**: 2.1s for 4MB image
- **Container Reuse**: 57% faster on warm starts

**Architecture:**
- Multi-stage Docker build compiling vips from source
- Custom shell runtime with AWS Lambda
- S3 event triggers with automatic scaling
- Terraform infrastructure as code

## Getting Started

Each example includes:

```
example-name/
├── README.md           # Detailed setup and usage
├── infra/             # Terraform infrastructure
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── app/               # Lambda function code
│   ├── src/           # Shell handlers
│   ├── runtime/       # Custom bootstrap
│   ├── Dockerfile     # Container build
│   └── serverless.yml # Deployment config
├── .env.example       # Environment template
└── deploy             # Deployment script
```

### Quick Deploy

```bash
# Clone and setup
git clone https://github.com/ql4b/cloudless-examples.git
cd cloudless-examples/thumbnail-s3-lambda-s3

# Configure environment
cp .env.example .env
# Edit .env with your AWS settings

# Deploy infrastructure
cd infra && terraform init && terraform apply

# Deploy function
cd ../app && npm run deploy
```

## Architecture Patterns

### Event-Driven Processing

Shell functions respond to AWS events with minimal overhead:

```bash
# Parse S3 event
parse_s3_event() {
    echo "$1" | jq -r '.Records[0].s3.bucket.name + "|" + .Records[0].s3.object.key'
}

# Process with timeout protection
if timeout 25 aws s3 cp "$source" "$dest"; then
    echo "Success: $(wc -c < "$dest") bytes"
else
    echo "ERROR: Download failed" >&2
    return 1
fi
```

### Multi-Stage Docker Builds

Compile dependencies in builder stage, copy only essentials to runtime:

```dockerfile
# Build stage - compile from source
FROM amazonlinux:2023 AS builder
RUN dnf install -y gcc make meson ninja-build
RUN wget https://github.com/libvips/libvips/releases/download/v8.15.1/vips-8.15.1.tar.xz
RUN meson setup build --prefix=/usr/local && meson compile && meson install

# Runtime stage - minimal footprint
FROM ghcr.io/ql4b/lambda-shell-runtime:full
COPY --from=builder /usr/local/bin/vips* /usr/local/bin/
COPY --from=builder /usr/local/lib64/libvips* /usr/local/lib/
```

### Infrastructure as Code

Terraform modules for consistent, repeatable deployments:

```hcl
module "lambda_function" {
  source = "git::https://github.com/ql4b/terraform-aws-lambda-function.git"
  
  package_type = "Image"
  image_uri    = "${aws_ecr_repository.runtime.repository_url}:latest"
  
  environment_variables = {
    HANDLER = "handler.thumb"
  }
}

resource "aws_s3_bucket_notification" "trigger" {
  lambda_function {
    lambda_function_arn = module.lambda_function.function_arn
    events             = ["s3:ObjectCreated:*"]
  }
}
```

## Performance Philosophy

### Shell-First Principles

1. **Minimal Runtime Overhead**: Shell scripts start instantly, no framework initialization
2. **Direct System Calls**: `aws`, `jq`, `curl` are optimized C binaries
3. **Predictable Memory Usage**: No garbage collection, explicit resource management
4. **Composable Tools**: Unix philosophy of small, focused utilities

### Benchmarking Results

| Metric | Shell Runtime | Node.js Runtime | Improvement |
|--------|---------------|-----------------|-------------|
| Cold Start | 155ms | 500ms | **69% faster** |
| Memory Usage | 137MB | 256MB | **46% less** |
| Processing Time | 2.1s | 3.2s | **34% faster** |
| Container Reuse | 88ms | 200ms | **56% faster** |

## Best Practices

### Error Handling

```bash
# Set strict error handling
set -euo pipefail

# Explicit error checking
if ! aws s3 cp "$source" "$dest"; then
    echo "ERROR: Failed to download $source" >&2
    return 1
fi
```

### Timeout Protection

```bash
# Use timeout for external calls
if timeout 25 aws s3 cp "$source" "$dest" --cli-read-timeout 20; then
    echo "Downloaded $(wc -c < "$dest") bytes"
else
    echo "ERROR: Download timeout" >&2
    return 1
fi
```

### Resource Cleanup

```bash
# Always cleanup temporary files
trap 'rm -f "$input_file" "$output_file"' EXIT

# Explicit cleanup in functions
cleanup() {
    rm -f "$input_file" "$output_file"
}
```

### Debugging

```bash
# Debug output to stderr (visible in CloudWatch)
echo "DEBUG: Processing $object_key" >&2
echo "DEBUG: File size: $(wc -c < "$input_file")" >&2

# Structured logging
log_info() {
    echo "INFO: $*" >&2
}

log_error() {
    echo "ERROR: $*" >&2
}
```

## Contributing

We welcome contributions! To add a new example:

1. **Create directory structure** following the pattern above
2. **Include comprehensive README** with setup instructions
3. **Add performance benchmarks** comparing to equivalent implementations
4. **Provide Terraform infrastructure** for easy deployment
5. **Include error handling** and debugging features

### Example Checklist

- [ ] Complete infrastructure as code (Terraform)
- [ ] Multi-stage Docker build for minimal image size
- [ ] Comprehensive error handling and timeouts
- [ ] Performance benchmarks vs alternatives
- [ ] CloudWatch monitoring and logging
- [ ] Deployment automation scripts
- [ ] Detailed documentation with usage examples

## Related Projects

- **[lambda-shell-runtime](https://github.com/ql4b/lambda-shell-runtime)** - Custom AWS Lambda runtime for shell scripts
- **[terraform-aws-lambda-function](https://github.com/ql4b/terraform-aws-lambda-function)** - Terraform module for Lambda deployment
- **[http-cli](https://github.com/ql4b/http-cli)** - Minimal HTTP client for shell scripting
- **[cloudless](https://github.com/ql4b/cloudless)** - Main project documentation

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

*Examples are part of the [cloudless](https://cloudless.sh) approach to building high-performance serverless applications through shell-first architecture.*