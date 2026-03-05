const { PubSub } = require("@google-cloud/pubsub");
const { Client } = require("pg");

const pubsub = new PubSub();
const topicName = process.env.TOPIC_ID;

// Postgres Client Konfiguration (CockroachDB)
const pgConfig = {
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: 26257,
  ssl: true,
};

let schemaInitialized = false;

async function initializeSchema(client) {
  if (schemaInitialized) return;

  try {
    // Prüfen ob events Tabelle bereits existiert (über ein Query)
    try {
      await client.query("SELECT 1 FROM events LIMIT 1");
      console.log("Schema already exists");
      schemaInitialized = true;
      return;
    } catch (checkErr) {
      // Tabelle existiert noch nicht
      if (checkErr.code !== "42P01") {
        throw checkErr; // Wenn ein anderer Fehler auftritt, diesen werfen.
      }
    }

    console.log("Creating database schema...");

    await client.query(`
      CREATE TABLE IF NOT EXISTS events (
        id STRING PRIMARY KEY,
        event_name STRING NOT NULL,
        total_capacity INT NOT NULL,
        remaining_capacity INT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS tickets (
        id STRING PRIMARY KEY,
        event_id STRING NOT NULL REFERENCES events(id),
        user_id STRING NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_tickets_event_id ON tickets(event_id);
    `);

    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_tickets_user_id ON tickets(user_id);
    `);

    await client.query(
      "INSERT INTO events (id, event_name, total_capacity, remaining_capacity) VALUES ('1', 'TEKO Konzert vo Giuseppe', 35, 35)",
    );

    console.log("Schema initialized successfully");
    schemaInitialized = true;
  } catch (err) {
    console.error("Schema initialization error:", err.message);
    schemaInitialized = false;
    throw err;
  }
}

exports.validateTicket = async (req, res) => {
  const { event_id, user_id } = req.body;
  if (!event_id || !user_id) {
    return res.status(400).send("Missing event_id or user_id");
  }

  const client = new Client(pgConfig);
  try {
    await client.connect();

    // Schema bei erstem Durchlauf generieren
    await initializeSchema(client);

    // Schnelle Abfrage der Restkapazität
    const result = await client.query(
      "SELECT remaining_capacity FROM events WHERE id = $1",
      [event_id],
    );

    if (result.rows.length === 0 || result.rows[0].remaining_capacity <= 0) {
      return res
        .status(410)
        .json({ error: "SOLD_OUT", message: "Keine Tickets mehr verfügbar" });
    }

    // In die Queue schreiben (Pub/Sub)
    const data = JSON.stringify({
      event_id,
      user_id,
      timestamp: new Date().toISOString(),
    });
    const messageId = await pubsub
      .topic(topicName)
      .publishMessage({ data: Buffer.from(data) });

    console.log(`Message ${messageId} published for user ${user_id}`);
    res.status(202).json({
      status: "QUEUED",
      message: "Ihre Ticket-Anfrage wird verarbeitet",
      queue_id: messageId,
    });
  } catch (err) {
    console.error("Fehler bei der Validierung:", err.message, err.stack);
    res.status(500).json({
      error: "Internal Server Error",
      message: err.message,
      details: process.env.NODE_ENV === "development" ? err.stack : undefined,
    });
  } finally {
    await client.end();
  }
};
