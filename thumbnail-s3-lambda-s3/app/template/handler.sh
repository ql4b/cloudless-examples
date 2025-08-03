#!/bin/bash

# Example Lambda handler function
api_handler() {
    local event="$1"
    local name=$(echo "$event" | jq -r '.name // "World"')
    
    echo '{
        "statusCode": 200,
        "body": "Hello, '"$name"'!"
    }'
}

# Call handler with event data
api_handler "$1"