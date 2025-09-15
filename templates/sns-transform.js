// SNS message transform - unwraps Message and extracts MessageAttributes
exports.handler = async (event) => {
    const output = [];
    
    for (const record of event.records) {
        try {
            const payload = Buffer.from(record.data, 'base64').toString('utf8');
            const snsMessage = JSON.parse(payload)
            // Parse the actual message content
            const data = JSON.parse(decodeURIComponent(
                snsMessage.Message)
            );
            
            // Extract MessageAttributes
            const attributes = {};
            if (snsMessage.MessageAttributes) {
                for (const [key, attr] of Object.entries(snsMessage.MessageAttributes)) {
                    attributes[key] = attr.Value;
                }
            }
            
            const transformed = {
                // Add SNS metadata
                messageId: snsMessage.MessageId,
                timestamp: snsMessage.Timestamp,
                topicArn: snsMessage.TopicArn,
                topic: snsMessage.TopicArn.split(':').pop(),
                ...attributes,
                
                // Include data based on fields and mappings configuration
                %{ if length(fields) == 0 && length(mappings) == 0 ~}
                // No fields or mappings specified - include all data
                ...data,
                %{ else ~}
                // Include specified fields only
                %{ for field in fields ~}
                ...(data['${field}'] !== undefined && { '${field}': data['${field}'] }),
                %{ endfor ~}
                %{ endif ~}
                
                %{ for target, source in mappings ~}
                ...(data['${source}'] !== undefined && { '${target}': data['${source}'] }),
                %{ endfor ~}
            };
            
            // Add @timestamp if not present
            if (!transformed['@timestamp']) {
                transformed['@timestamp'] = snsMessage.Timestamp;
            }
            
            output.push({
                recordId: record.recordId,
                result: 'Ok',
                data: Buffer.from(JSON.stringify(transformed)).toString('base64')
            });
            
        } catch (error) {
            console.error('SNS transform error:', error);
            output.push({
                recordId: record.recordId,
                result: 'ProcessingFailed'
            });
        }
    }
    
    return { records: output };
};