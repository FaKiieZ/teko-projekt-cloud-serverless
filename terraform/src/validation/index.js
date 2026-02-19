const { PubSub } = require('@google-cloud/pubsub');
const { Client } = require('pg');

const pubsub = new PubSub();
const topicName = process.env.TOPIC_ID;
const apiSecret = process.env.API_SECRET;

// Postgres Client Konfiguration (AlloyDB)
const pgConfig = {
    host: process.env.ALLOYDB_IP,
    user: 'postgres',
    password: 'change-me-safely', // In Echt über Secret Manager!
    database: 'postgres',
    port: 5432,
};

exports.validateTicket = async (req, res) => {
    // 1. Einfache Sicherheitsprüfung (API Secret)
    // Wir verwenden nun 'x-api-secret', da 'Authorization' für IAM ID-Tokens reserviert ist.
    const apiSecretHeader = req.headers['x-api-secret'];
    if (apiSecretHeader !== apiSecret) {
        return res.status(403).send('Unauthorized: Invalid Secret');
    }

    const { event_id, user_id } = req.body;
    if (!event_id || !user_id) {
        return res.status(400).send('Missing event_id or user_id');
    }

    const client = new Client(pgConfig);
    try {
        await client.connect();

        // 2. Schnelle Abfrage der Restkapazität (nur lesend)
        const result = await client.query(
            'SELECT remaining_capacity FROM events WHERE id = $1',
            [event_id]
        );

        if (result.rows.length === 0 || result.rows[0].remaining_capacity <= 0) {
            return res.status(410).json({ error: 'SOLD_OUT', message: 'Keine Tickets mehr verfügbar' });
        }

        // 3. In die Queue schreiben (Pub/Sub)
        const data = JSON.stringify({ event_id, user_id, timestamp: new Date().toISOString() });
        const messageId = await pubsub.topic(topicName).publishMessage({ data: Buffer.from(data) });

        console.log(`Message ${messageId} published for user ${user_id}`);
        res.status(202).json({ 
            status: 'QUEUED', 
            message: 'Ihre Ticket-Anfrage wird verarbeitet',
            queue_id: messageId 
        });

    } catch (err) {
        console.error('Fehler bei der Validierung:', err);
        res.status(500).send('Interner Serverfehler');
    } finally {
        await client.end();
    }
};
