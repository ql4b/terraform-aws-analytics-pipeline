// Flight Search Results Transform - Complex Logstash equivalent
const crypto = require('crypto');

exports.handler = async (event) => {
    const output = [];
    
    for (const record of event.records) {
        try {
            const payload = Buffer.from(record.data, 'base64').toString('utf8');
            const data = JSON.parse(payload);
            
            // 1. Process flight results (Ruby code equivalent)
            if (data.results && data.results.complete) {
                data.results.complete = data.results.complete.map(item => ({
                    ...item,
                    price_return: parseFloat(item.price_return || 0)
                }));
            }
            
            // 2. Split results into individual documents (Logstash split equivalent)
            const solutions = data.results?.complete || [];
            
            for (const solution of solutions) {
                const transformed = {
                    solution: solution,
                    '@timestamp': new Date().toISOString()
                };
                
                // 3. Date processing
                if (data.search_data?.departure_date) {
                    transformed.itinerary = {
                        departure_date: formatDate(data.search_data.departure_date),
                        origin: data.search_data.departure,
                        destination: data.search_data.destination
                    };
                }
                
                if (data.search_data?.return_date) {
                    transformed.itinerary.return_date = formatDate(data.search_data.return_date);
                }
                
                // 4. Passenger data
                transformed.passengers = {
                    adults: parseInt(data.search_data?.adults || 0),
                    children: parseInt(data.search_data?.children || 0),
                    infants: parseInt(data.search_data?.infants || 0)
                };
                
                // 5. Generate search strings and fingerprints
                const searchStr = [
                    data.search_data?.departure,
                    data.search_data?.destination,
                    data.search_data?.departure_date,
                    data.search_data?.return_date,
                    data.search_data?.adults,
                    data.search_data?.children,
                    data.search_data?.infants
                ].join('-');
                
                const itineraryStr = [
                    data.search_data?.departure,
                    data.search_data?.destination,
                    data.search_data?.departure_date,
                    data.search_data?.return_date
                ].join('-');
                
                // 6. Generate fingerprints (SHA256)
                transformed.search_fingerprint = crypto.createHash('sha256').update(searchStr).digest('hex');
                transformed.itinerary_fingerprint = crypto.createHash('sha256').update(itineraryStr).digest('hex');
                
                // 7. Generate route and IDs
                transformed.route = (data.search_data?.departure || '') + (data.search_data?.destination || '');
                transformed.itinerary_solution = `${solution.id_solution}-${transformed.itinerary_fingerprint}`;
                
                // 8. Generate final document ID
                const idSource = `${solution.id_solution}${transformed.search_fingerprint}`;
                transformed.id = crypto.createHash('sha256').update(idSource).digest('hex');
                
                // 9. Add processing metadata
                transformed.pipeline = {
                    version: 'firehose-v1',
                    processed_at: new Date().toISOString()
                };
                
                // Output each solution as separate record
                output.push({
                    recordId: record.recordId + '-' + solutions.indexOf(solution),
                    result: 'Ok',
                    data: Buffer.from(JSON.stringify(transformed)).toString('base64')
                });
            }
            
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

// Helper function to format dates (dd-MM-yyyy to ISO)
function formatDate(dateStr) {
    if (!dateStr) return null;
    const [day, month, year] = dateStr.split('-');
    return new Date(year, month - 1, day).toISOString();
}