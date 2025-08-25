// Lambda transform function - replaces Logstash filter
exports.handler = async (event) => {
    const output = [];
    
    for (const record of event.records) {
        try {
            // Decode the data
            const payload = Buffer.from(record.data, 'base64').toString('utf8');
            const data = JSON.parse(payload);
            
            // Apply field mappings (template variables)
            const transformed = {};
            
            %{ for field in fields ~}
            if (data['${field}']) {
                transformed['${field}'] = data['${field}'];
            }
            %{ endfor ~}
            
            %{ for target, source in mappings ~}
            if (data['${source}']) {
                transformed['${target}'] = data['${source}'];
            }
            %{ endfor ~}
            
            // Add timestamp if not present
            if (!transformed['@timestamp']) {
                transformed['@timestamp'] = new Date().toISOString();
            }
            
            // Encode the transformed data
            const outputRecord = {
                recordId: record.recordId,
                result: 'Ok',
                data: Buffer.from(JSON.stringify(transformed)).toString('base64')
            };
            
            output.push(outputRecord);
            
        } catch (error) {
            console.error('Transform error:', error);
            output.push({
                recordId: record.recordId,
                result: 'ProcessingFailed'
            });
        }
    }
    
    return { records: output };
};