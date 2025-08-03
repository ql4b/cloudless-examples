# Function name from environment variable
FUNCTION_NAME := $(or $(FUNCTION_NAME),$(error FUNCTION_NAME environment variable not set))

# Default target
.PHONY: help
help:
	@echo "Usage: export FUNCTION_NAME=your-function-name"
	@echo ""
	@echo "Available targets:"
	@echo "  deploy    - Package and deploy function code"
	@echo "  invoke    - Test function invocation"
	@echo "  logs      - View function logs"
	@echo "  clean     - Remove deployment artifacts"

# Package and deploy function code
.PHONY: deploy
deploy:
	@echo "Packaging function..."
	zip -r function.zip bootstrap handler.sh
	@echo "Deploying to $(FUNCTION_NAME)..."
	aws lambda update-function-code \
		--function-name $(FUNCTION_NAME) \
		--zip-file fileb://function.zip
	@echo "✓ Function deployed"

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

# View function logs
.PHONY: logs
logs:
	@echo "Tailing logs for $(FUNCTION_NAME)..."
	aws logs tail /aws/lambda/$(FUNCTION_NAME) --follow

# Clean deployment artifacts
.PHONY: clean
clean:
	rm -f function.zip
	rm -f /tmp/response.json
	@echo "✓ Cleaned deployment artifacts"