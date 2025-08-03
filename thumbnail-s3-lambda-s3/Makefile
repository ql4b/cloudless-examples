# Load environment variables
include .env
export

# Add current directory to PATH
export PATH := .:$(PATH)

# Get function name from Terraform output
FUNCTION_NAME := $(shell tf output -json lambda | jq -r .function_name 2>/dev/null || echo "unknown")
REPOSITORY_URL := $(shell tf output -json runtime | jq -r .ecr.repository_url 2>/dev/null )
SOURCE_BUCKET := $(shell tf  output -json source_bucket | jq -r .bucket_id  2>/dev/null || echo "unknown")

# Handler function (can be overridden)
HANDLER ?= handler.thumb
# Detach mode (can be overridden with DETACH=false)
DETACH ?= true

# Default target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  debug     - Print Terraform output values"
	@echo "  build     - Build and push Docker image"
	@echo "  deploy    - Deploy Lambda function"
	@echo "  run       - Run container locally (HANDLER=$(HANDLER), DETACH=$(DETACH))"
	@echo "  exec      - Connect to running container"
	@echo "  test      - Upload test image to trigger function (FILE=$(FILE))"
	@echo "  invoke    - Test function invocation"
	@echo "  logs      - View recent function logs (SINCE=$(SINCE))"
	@echo "  tail      - Tail logs in real-time"
	@echo "  clean     - Remove deployment artifacts"
	@echo ""
	@echo "Function: $(FUNCTION_NAME)"
	@echo "Repository: $(REPOSITORY_URL)"
	@echo "Source Bucket: $(SOURCE_BUCKET)"
	@echo "Handler: $(HANDLER)"

# Debug - print all values
.PHONY: debug
debug:
	@echo "=== Terraform Outputs ==="
	@echo "Lambda output:"
	@tf output -json lambda | jq 2>/dev/null || echo "No lambda output"
	@echo ""
	@echo "ECR output:"
	@tf output -json runtime | jq  2>/dev/null || echo "No ECR output"
	@echo ""
	@echo "Source bucket output:"
	@tf output -json source_bucket | jq  2>/dev/null || echo "No source_bucket output"
	@echo ""
	@echo "=== Parsed Values ==="
	@echo "FUNCTION_NAME: $(FUNCTION_NAME)"
	@echo "REPOSITORY_URL: $(REPOSITORY_URL)"
	@echo "SOURCE_BUCKET: $(SOURCE_BUCKET)"

# Build and push Docker image
.PHONY: build
build:
	@echo "Building Docker image..."
	cd app && docker build -t $(REPOSITORY_URL):latest .
	@echo "Pushing to ECR..."
	docker push $(REPOSITORY_URL):latest
	@echo "✓ Image built and pushed"

# Deploy Lambda function (update function code)
.PHONY: deploy
deploy: build
	@echo "Updating Lambda function..."
	tf apply --auto-approve 
	@echo "✓ Function deployed"

.PHONY: run
run:
	@echo "Running the runtime image locally "
	@if [ "$(DETACH)" = "true" ]; then \
		docker run --rm \
			--entrypoint /usr/local/bin/aws-lambda-rie \
			-p 9000:8080 \
			-v ~/.aws:/root/.aws:rw \
			-v ./app/src/handler.sh:/var/task/handler.sh:rw \
			-v ./app/runtime/bootstrap:/var/runtime/bootstrap:rw \
			-v /tmp/images:/tmp/images:rw \
			--name $(FUNCTION_NAME) \
			--detach \
			$(REPOSITORY_URL):latest \
			/var/runtime/bootstrap \
			$(HANDLER); \
	else \
		docker run --rm \
			--entrypoint /usr/local/bin/aws-lambda-rie \
			-p 9000:8080 \
			-v ~/.aws:/root/.aws:rw \
			-v ./app/src/handler.sh:/var/task/handler.sh:rw \
			-v ./app/runtime/bootstrap:/var/runtime/bootstrap:rw \
			-v /tmp/images:/tmp/images:rw \
			--name $(FUNCTION_NAME) \
			$(REPOSITORY_URL):latest \
			/var/runtime/bootstrap \
			$(HANDLER); \
	fi
		

.PHONY: exec
exec: 
	@CONTAINER_ID=$$(docker ps -q --filter name="$(FUNCTION_NAME)"); \
	if [ -z "$$CONTAINER_ID" ]; then \
		echo "No running container found for $(FUNCTION_NAME). Run 'make run' first."; \
		exit 1; \
	fi; \
	docker exec -it $$CONTAINER_ID /bin/bash


# Test function invocation
.PHONY: invoke
invoke:
	@echo "Invoking $(FUNCTION_NAME)..."
	aws lambda invoke \
		--function-name $(FUNCTION_NAME) \
		--payload '{"test": "data"}' \
		--cli-binary-format raw-in-base64-out \
		/tmp/response.json
	@echo "Response:"
	@cat /tmp/response.json
	@echo

# View recent function logs
SINCE ?= 1h
.PHONY: logs
logs:
	@echo "Recent logs for $(FUNCTION_NAME) (since $(SINCE)):"
	aws logs tail /aws/lambda/$(FUNCTION_NAME) --since $(SINCE) --format short

# Tail function logs in real-time
.PHONY: tail
tail:
	@echo "Tailing logs for $(FUNCTION_NAME)... (Ctrl+C to stop)"
	aws logs tail /aws/lambda/$(FUNCTION_NAME) --follow --format short

# Test with S3 upload
FILE ?= test-image.jpg
.PHONY: test
test:
	@echo "Testing S3 upload trigger with $(FILE)..."
	@if [ -f $(FILE) ]; then \
		aws s3 cp $(FILE) s3://$(SOURCE_BUCKET)/$(FILE); \
		echo "✓ $(FILE) uploaded. Check logs with 'make tail'"; \
	else \
		echo "File $(FILE) not found. Create it first or specify FILE=path/to/image"; \
		exit 1; \
	fi

# Clean deployment artifacts
.PHONY: clean
clean:
	rm -f /tmp/response.json
	@echo "✓ Cleaned deployment artifacts"

# Clean Docker images
.PHONY: clean-docker
clean-docker:
	docker rmi $(REPOSITORY_URL):latest 2>/dev/null || true
	@echo "✓ Cleaned Docker images"