import { sessionEventRepository } from '@/common/utils/elasticsearchRepository';
import { initializeElasticsearch } from '@/common/utils/elasticsearchClient';
require('dotenv').config();

async function fetchSessionEvent() {
    console.log('Connecting to Elasticsearch...');
    console.log(`Elasticsearch URL: ${process.env.ELASTICSEARCH_URL}`);

    try {
        await initializeElasticsearch();
        console.log('Fetching session event with destNumber = 209...');

        const results = await sessionEventRepository.search({
            destNumber: '209'
        }, { page: 1, limit: 1 });

        if (results.data.length > 0) {
            console.log('Session event found:');
            console.log(JSON.stringify(results.data[0], null, 2));
        } else {
            console.log('No session event found with destNumber = 209');
        }
    } catch (error) {
        console.error('Error fetching session event:', error);
    }
}

// Run the function
fetchSessionEvent()
    .then(() => {
        console.log('Script completed');
        process.exit(0);
    })
    .catch((error) => {
        console.error('Script failed:', error);
        process.exit(1);
    }); 