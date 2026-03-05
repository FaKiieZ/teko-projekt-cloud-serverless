const { Client } = require("pg");

const pgConfig = {
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: 26257,
  ssl: {
    rejectUnauthorized: false, // Für CockroachDB Serverless oft nötig
  },
};

async function init() {
  const client = new Client(pgConfig);
  try {
    console.log("Connecting to CockroachDB...");
    await client.connect();
    console.log("Connected. Initializing schema...");

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

    // Initialer Seed (nur falls noch kein Event existiert)
    const check = await client.query("SELECT id FROM events LIMIT 1");
    if (check.rows.length === 0) {
      console.log("Inserting initial event...");
      await client.query(
        "INSERT INTO events (id, event_name, total_capacity, remaining_capacity) VALUES ('1', 'Pitbull im Hallenstadion Zürich', 15000, 15000)",
      );
    }

    console.log("Database initialization finished successfully.");
  } catch (err) {
    console.error("Error during DB initialization:", err.message);
    process.exit(1);
  } finally {
    await client.end();
  }
}

init();
