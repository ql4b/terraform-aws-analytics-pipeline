#!/bin/bash
# SQS to Firehose bridge function

sqs_bridge() {
    local event="$1"
    local stream_name="$FIREHOSE_STREAM_NAME"
    local temp_file="/tmp/firehose_records.json"
    
    # Get record count
    local record_count
    record_count=$(echo "$event" | jq '.Records | length')
    
    # Build Firehose records JSON
    echo "$event" | jq '{
        "Records": [.Records[] | {
            "Data": (.body | @base64)
        }]
    }' > "$temp_file"
    
    # Send to Firehose if we have records
    if [ "$record_count" -gt 0 ]; then
        local result
        result=$(aws firehose put-record-batch \
            --delivery-stream-name "$stream_name" \
            --cli-input-json "file://$temp_file" 2>&1)
        
        if [ $? -eq 0 ]; then
            local failed_count
            failed_count=$(echo "$result" | jq -r '.FailedPutCount // 0')
            
            echo "Sent $record_count records to Firehose" >&2
            
            if [ "$failed_count" -gt 0 ]; then
                echo "$failed_count records failed" >&2
            fi
        else
            echo "Firehose error: $result" >&2
            exit 1
        fi
    fi
    
    # Return Lambda response
    echo '{"statusCode":200,"body":"{\"processed\":'$record_count'}"}'
}

# Call handler with event data
sqs_bridge "$1"