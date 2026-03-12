const { Pool } = require("pg");
const { v4: uuidv4 } = require("uuid");

const pgConfig = {
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: 26257,
  ssl: true,
  max: 10, // Maximal 10 Connections pro Instanz
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
};

// Globaler Pool zur Wiederverwendung (ausserhalb der Handler-Funktion)
const pool = new Pool(pgConfig);

exports.processTicket = async (cloudEvent) => {
  let messageData;
  let event_id, user_id;

  try {
    // Daten aus Pub/Sub lesen
    messageData = Buffer.from(cloudEvent.data, "base64").toString();
    const parsedData = JSON.parse(messageData);
    event_id = parsedData.event_id;
    user_id = parsedData.user_id;

    console.log(
      `Verarbeite Ticketkauf für User: ${user_id}, Event: ${event_id}`,
    );

    /**
     * ATOMIC TICKET PURCHASE:
     * 1. Common Table Expression (CTE) versucht, die Kapazität zu reduzieren.
     * 2. Falls erfolgreich (remaining_capacity > 0), wird eine Zeile zurückgegeben.
     * 3. Der INSERT nutzt dieses Ergebnis als Quelle. Findet das UPDATE nicht statt,
     *    wird auch kein Ticket eingefügt.
     * 4. Alles passiert in einem einzigen Datenbank-Roundtrip.
     */
    const ticketId = uuidv4();
    const query = `
      WITH updated AS (
        UPDATE events
        SET remaining_capacity = remaining_capacity - 1
        WHERE id = $1 AND remaining_capacity > 0
        RETURNING id
      )
      INSERT INTO tickets (id, event_id, user_id)
      SELECT $2, $1, $3
      FROM updated
      RETURNING id;
    `;

    const result = await pool.query(query, [event_id, ticketId, user_id]);

    if (result.rowCount > 0) {
      console.log(`Erfolg! Ticket ${ticketId} für ${user_id} erstellt.`);
    } else {
      console.log(
        `Fehlgeschlagen: Event ${event_id} ist ausverkauft oder existiert nicht.`,
      );
      // In diesem Fall wurde kein Update gemacht, also keine Tickets verkauft
    }
  } catch (err) {
    console.error("Kritischer Fehler bei der Ticketverarbeitung:", err);
    throw err; // Damit Pub/Sub bei Fehlern retried
  }
};
