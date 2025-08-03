# shellcheck disable=SC2148
# No shebang - this file should be sourced, not executed

echo "DEBUG: handler.sh" >&2

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
    echo "Processing S3 event..." >&2
    aws --version >&2
    
    # Parse S3 event
    local bucket_key
    bucket_key=$(parse_s3_event "$event")
    local source_bucket="${bucket_key%|*}"
    local object_key="${bucket_key#*|}"
    
    echo "Processing: s3://$source_bucket/$object_key" >&2
    
    # # Download image from S3 using AWS CLI
    local input_file="/tmp/input_$(basename "$object_key")"
    echo "Downloading to: $input_file" >&2

    aws s3 cp "s3://$source_bucket/$object_key" "$input_file" \
        --cli-read-timeout 20 \
        --cli-connect-timeout 10
    echo "Downloaded $(wc -c < "$input_file") bytes" >&2

    

    # # # Generate thumbnail
    local thumbnail_file="/tmp/thumb_$(basename "$object_key")"
    generate_thumbnail "$input_file" "$thumbnail_file" "200x200"
    echo "Thumbnail generated: $thumbnail_file" >&2
    
    # # Upload thumbnail to destination bucket
    local thumbnails_bucket="${source_bucket/-source/-thumbnails}"
    local thumbnail_key="thumbnails/$object_key"
    
    aws s3 cp "$thumbnail_file" "s3://$thumbnails_bucket/$thumbnail_key"
    # echo "Uploaded to: s3://$thumbnails_bucket/$thumbnail_key" >&2
    
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