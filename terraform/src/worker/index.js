const { Client } = require('pg');
const { v4: uuidv4 } = require('uuid');

const pgConfig = {
    host: process.env.ALLOYDB_IP,
    user: 'postgres',
    password: 'change-me-safely', 
    database: 'postgres',
    port: 5432,
};

exports.processTicket = async (cloudEvent) => {
    // 1. Daten aus Pub/Sub lesen
    const messageData = Buffer.from(cloudEvent.data.message.data, 'base64').toString();
    const { event_id, user_id } = JSON.parse(messageData);

    console.log(`Verarbeite Ticketkauf für User: ${user_id}, Event: ${event_id}`);

    const client = new Client(pgConfig);
    try {
        await client.connect();

        // 2. Transaktion starten (Atomarität)
        await client.query('BEGIN');

        // 3. Zeile sperren & Kapazität prüfen (Double-Check & Locking)
        const checkCapacity = await client.query(
            'SELECT remaining_capacity FROM events WHERE id = $1 FOR UPDATE',
            [event_id]
        );

        if (checkCapacity.rows[0].remaining_capacity > 0) {
            // 4. Kapazität verringern
            await client.query(
                'UPDATE events SET remaining_capacity = remaining_capacity - 1 WHERE id = $1',
                [event_id]
            );

            // 5. Ticketkauf verbuchen
            const ticketId = uuidv4();
            await client.query(
                'INSERT INTO tickets (id, event_id, user_id) VALUES ($1, $2, $3)',
                [ticketId, event_id, user_id]
            );

            // 6. Transaktion abschliessen
            await client.query('COMMIT');
            console.log(`Erfolg! Ticket ${ticketId} für ${user_id} erstellt.`);
        } else {
            console.log(`Fehlgeschlagen: Event ${event_id} ist jetzt ausverkauft.`);
            await client.query('ROLLBACK');
        }

    } catch (err) {
        console.error('Kritischer Fehler bei der Ticketverarbeitung:', err);
        if (client) await client.query('ROLLBACK');
        throw err; // Damit Pub/Sub bei Fehlern retried
    } finally {
        await client.end();
    }
};
