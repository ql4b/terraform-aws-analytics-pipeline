// Advanced Lambda transform function - EventBridge-style transformations
exports.handler = async (event) => {
    const output = [];
    
    // Custom functions (if defined)
    %{ for func in custom_functions ~}
    const ${func.name} = ${func.code};
    %{ endfor ~}
    
    for (const record of event.records) {
        try {
            const payload = Buffer.from(record.data, 'base64').toString('utf8');
            const data = JSON.parse(payload);
            let transformed = {};
            
            // 1. Extract input paths (EventBridge-style)
            const extracted = {};
            %{ for key, path in input_paths ~}
            extracted['${key}'] = getNestedValue(data, '${path}');
            %{ endfor ~}
            
            // 2. Apply input template if provided
            %{ if input_template != null ~}
            const templateStr = `${input_template}`;
            transformed = JSON.parse(templateStr.replace(/\$\{([^}]+)\}/g, (match, key) => {
                return JSON.stringify(extracted[key] || data[key] || '');
            }));
            %{ else ~}
            transformed = { ...data };
            %{ endif ~}
            
            // 3. Basic field mappings
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
            
            // 4. Conditional transformations
            %{ for condition in conditions ~}
            if (evaluateCondition(data['${condition.field}'], '${condition.operator}', '${condition.value}')) {
                %{ for target, source in condition.then_map ~}
                transformed['${target}'] = data['${source}'] || '${source}';
                %{ endfor ~}
            } else {
                %{ for target, source in condition.else_map ~}
                transformed['${target}'] = data['${source}'] || '${source}';
                %{ endfor ~}
            }
            %{ endfor ~}
            
            // 5. Data enrichment
            %{ for field, value in enrich.add_fields ~}
            transformed['${field}'] = '${value}';
            %{ endfor ~}
            
            %{ for field in enrich.remove_fields ~}
            delete transformed['${field}'];
            %{ endfor ~}
            
            %{ for field in enrich.parse_json_fields ~}
            if (transformed['${field}'] && typeof transformed['${field}'] === 'string') {
                try {
                    transformed['${field}'] = JSON.parse(transformed['${field}']);
                } catch (e) {
                    console.warn(`Failed to parse JSON field ${field}:`, e);
                }
            }
            %{ endfor ~}
            
            // 6. Add timestamp if not present
            if (!transformed['@timestamp']) {
                transformed['@timestamp'] = new Date().toISOString();
            }
            
            output.push({
                recordId: record.recordId,
                result: 'Ok',
                data: Buffer.from(JSON.stringify(transformed)).toString('base64')
            });
            
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

// Helper functions
function getNestedValue(obj, path) {
    return path.split('.').reduce((current, key) => current?.[key], obj);
}

function evaluateCondition(value, operator, expected) {
    switch (operator) {
        case 'eq': return value == expected;
        case 'ne': return value != expected;
        case 'gt': return parseFloat(value) > parseFloat(expected);
        case 'lt': return parseFloat(value) < parseFloat(expected);
        case 'contains': return String(value).includes(expected);
        case 'exists': return value !== undefined && value !== null;
        default: return false;
    }
}