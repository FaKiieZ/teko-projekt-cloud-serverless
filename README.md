# Teko School Project: Serverless Ticketing System (GCP)

Dieses Projekt demonstriert ein hochskalierbares, serverloses Ticket-Buchungssystem auf der Google Cloud Platform (GCP). Es wurde im Rahmen eines Schulprojekts entwickelt und optimiert für Kosteneffizienz und Ausfallsicherheit.

## 🏛️ Architektur-Übersicht

Das System nutzt eine Warteschlangen-basierte Architektur (Queue-Worker-Pattern), um Lastspitzen abzufangen und Datenintegrität zu garantieren:

1.  **Frontend (Webapp):** Sendet Kaufanfragen direkt an die Cloud Run function.
2.  **Validation Function (LF1):** Prüft die Kapazität in der AlloyDB und reiht gültige Anfragen in Pub/Sub ein.
3.  **Pub/Sub (Queue):** Puffer für eingehende Bestellungen.
4.  **Worker Function (LF2):** Verarbeitet Nachrichten aus der Queue, führt Datenbank-Transaktionen (ACID) durch und reduziert die Kapazität.
5.  **AlloyDB (PostgreSQL):** Hochverfügbare, relationale Datenbank für Events und Tickets.

---

## 🛠️ Lokales Setup & Bereitstellung

Wir nutzen **Terraform** zur Verwaltung der Infrastruktur. Eine passende `terraform.exe` liegt bereits im Hauptverzeichnis.

### 1. Voraussetzungen

- Ein Google Cloud Projekt (ID bereitstellen).
- **Abrechnung (Billing) aktiviert:** Das Projekt MUSS in der Google Cloud Console mit einem aktiven Rechnungskonto verknüpft sein (auch für Free Credits), sonst schlägt das Aktivieren der APIs fehl.
- **Google Cloud CLI (gcloud) installiert:** [Hier herunterladen](https://cloud.google.com/sdk/docs/install)
- **GCP Authentifizierung:** Damit Terraform Zugriff auf dein Konto hat, musst du dich einmalig lokal anmelden:
  ```powershell
  gcloud auth application-default login
  ```
  _Hinweis: Es öffnet sich ein Browserfenster zur Bestätigung._

### 2. Infrastruktur hochfahren

Navigiere in den `terraform` Ordner und bereite deine Variablen vor:

1. Kopiere die Vorlage: `cp terraform.tfvars.example terraform.tfvars` (oder manuell umbenennen)
2. Trage deine echten Werte (Projekt-ID, Passwörter, Secrets) in `terraform.tfvars` ein.

Führe dann die Befehle aus:

```powershell
# In das Terraform Verzeichnis wechseln
cd terraform

# Provider initialisieren (Plugins laden)
../terraform init

# Infrastruktur planen und ausführen
../terraform apply

# --- INFRASTRUKTUR LÖSCHEN (Kosten vermeiden!) ---
# Wenn das Projekt fertig ist oder du Kosten sparen willst:
../terraform destroy
```

---

## 🔐 Sicherheit & API-Nutzung

### Zugriffskontrolle (IAM & Restricted API)

Die API ist **nicht öffentlich** erreichbar. Nur explizit autorisierte Benutzer (du und deine Kollegen) können die API aufrufen.

1.  **Berechtigung erteilen:** Füge die E-Mail-Adressen in der `terraform/terraform.tfvars` unter `authorized_invokers` hinzu:
    ```hcl
    authorized_invokers = [
      "user:deine-email@gmail.com",
      "user:kollege@gmail.com"
    ]
    ```
2.  **Terraform Apply:** Führe `../terraform apply` erneut aus, um die Berechtigungen zu setzen.

### Authentifizierung beim Testen

Da Google Cloud für den IAM-Check den `Authorization`-Header (ID-Token) verwendet, nutzen wir für unser internes Anwendungs-Secret den Header `X-API-Secret`.

**Beispiel-Request (PowerShell/cURL):**
Um die API zu testen, musst du ein Google Identity Token generieren:

```powershell
$URL = (../terraform output -raw api_url)
$TOKEN = (gcloud auth print-identity-token)
$SECRET = "DEIN_API_SECRET_AUS_TFVARS"


curl -X POST $URL `
  -H "Authorization: Bearer $TOKEN" `
  -H "X-API-Secret: $SECRET" `
  -H "Content-Type: application/json" `
  -d '{"event_id": 1, "user_id": "test-user-001"}'
```

### Kostenschutz

- **Max Instances:** Die Cloud Functions sind auf maximal **2 Instanzen** begrenzt, um Kostenexplosionen bei Tests zu vermeiden.
- **Kein Redis:** Alle Kapazitätsprüfungen laufen über die AlloyDB, um zusätzliche Memorystore-Kosten zu sparen.

---

## 📊 Datenbank-Schema (AlloyDB)

Bevor das System funktioniert, muss das Schema in der AlloyDB einmalig angelegt werden:

```sql
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    total_capacity INTEGER NOT NULL,
    remaining_capacity INTEGER NOT NULL
);

CREATE TABLE tickets (
    id UUID PRIMARY KEY,
    event_id INTEGER REFERENCES events(id),
    user_id VARCHAR(255),
    purchased_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Beispiel-Daten
INSERT INTO events (name, total_capacity, remaining_capacity)
VALUES ('Hallenstadion Konzert', 15000, 15000);
```

---

## 📂 Projektstruktur

- `terraform/main.tf`: Die gesamte GCP Infrastruktur (IaC).
- `terraform/variables.tf`: Definition der Variablen.
- `terraform/terraform.tfvars.example`: Vorlage für Geheimnisse (Secrets).
- `terraform/src/validation`: Node.js Code für die Eingangs-Validierung.
- `terraform/src/worker`: Node.js Code für die finale Ticket-Verbuchung.
- `terraform.exe`: Terraform Binary für die lokale Ausführung.
