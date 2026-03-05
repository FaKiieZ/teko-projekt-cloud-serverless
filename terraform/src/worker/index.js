const { Client } = require("pg");
const { v4: uuidv4 } = require("uuid");

const pgConfig = {
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: 26257,
  ssl: true,
};

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

    const client = new Client(pgConfig);
    await client.connect();

    // Transaktion starten
    await client.query("BEGIN");

    // Zeile sperren & Kapazität prüfen (Double-Check & Locking)
    const checkCapacity = await client.query(
      "SELECT remaining_capacity FROM events WHERE id = $1 FOR UPDATE",
      [event_id],
    );

    if (checkCapacity.rows[0].remaining_capacity > 0) {
      // Kapazität verringern
      await client.query(
        "UPDATE events SET remaining_capacity = remaining_capacity - 1 WHERE id = $1",
        [event_id],
      );

      // Ticketkauf verbuchen
      const ticketId = uuidv4();
      await client.query(
        "INSERT INTO tickets (id, event_id, user_id) VALUES ($1, $2, $3)",
        [ticketId, event_id, user_id],
      );

      // Transaktion abschliessen
      await client.query("COMMIT");
      console.log(`Erfolg! Ticket ${ticketId} für ${user_id} erstellt.`);
    } else {
      console.log(`Fehlgeschlagen: Event ${event_id} ist jetzt ausverkauft.`);
      await client.query("ROLLBACK");
    }

    await client.end();
  } catch (err) {
    console.error("Kritischer Fehler bei der Ticketverarbeitung:", err);
    throw err; // Damit Pub/Sub bei Fehlern retried
  }
};
