// SQS to Firehose bridge function
const AWS = require('aws-sdk');
const firehose = new AWS.Firehose();

exports.handler = async (event) => {
    const streamName = process.env.FIREHOSE_STREAM_NAME;
    const records = [];
    
    // Process SQS messages
    for (const sqsRecord of event.Records) {
        try {
            const data = sqsRecord.body;
            
            records.push({
                Data: Buffer.from(data, 'utf8')
            });
            
        } catch (error) {
            console.error('Error processing SQS record:', error);
            throw error;
        }
    }
    
    // Send to Firehose
    if (records.length > 0) {
        const params = {
            DeliveryStreamName: streamName,
            Records: records
        };
        
        try {
            const result = await firehose.putRecordBatch(params).promise();
            console.log(`Sent ${records.length} records to Firehose`);
            
            if (result.FailedPutCount > 0) {
                console.error(`${result.FailedPutCount} records failed`);
            }
            
        } catch (error) {
            console.error('Firehose error:', error);
            throw error;
        }
    }
    
    return {
        statusCode: 200,
        body: JSON.stringify({
            processed: records.length
        })
    };
};