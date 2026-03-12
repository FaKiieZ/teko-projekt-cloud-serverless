# 🎫 TEKO Schulprojekt: Serverless Ticketing System (GCP)

Dieses Schulprojekt demonstriert ein hochverfügbares, serverloses Ticket-Buchungssystem auf der Google Cloud Platform (GCP). Es wurde entwickelt, um Lastspitzen effizient zu bewältigen und gleichzeitig durch eine rein serverlose Architektur kosteneffizient zu bleiben.

---

## 🏗️ Architektur-Übersicht

Das System nutzt eine ereignisgesteuerte Warteschlangen-Architektur (Event-Driven Architecture), um Anfragen asynchron zu verarbeiten.

### Komponenten-Details

1. **Validation Function (LF1):** Nimmt HTTP-Requests entgegen, validiert die Eingaben, prüft die grobe Verfügbarkeit und stellt gültige Anfragen in die Pub/Sub-Warteschlange.
2. **Pub/Sub Topic:** Dient als Puffer, um Lastspitzen abzufangen und sicherzustellen, dass keine Bestellung verloren geht.
3. **Worker Function (LF2):** Verarbeitet Nachrichten aus der Warteschlange, führt die finale Datenbank-Transaktion durch (Atomic Update) und reduziert die Kapazität.
4. **CockroachDB Serverless:** Eine verteilte, PostgreSQL-kompatible Datenbank, die automatisch skaliert und im Free-Tier extrem kostengünstig ist.

---

## 🚀 Lokales Setup & Bereitstellung

Das Projekt wird vollständig via Infrastructure as Code (Terraform) verwaltet.

### 1. Voraussetzungen

- **Terraform** installiert ([Download](https://www.terraform.io/downloads))
- **Google Cloud CLI (gcloud)** installiert ([Download](https://cloud.google.com/sdk/docs/install))
- **Ein GCP-Projekt** mit aktivem Rechnungskonto (für Cloud Functions/Build erforderlich)
- **CockroachDB Cloud Account** und ein API-Key für die Cluster-Provisionierung.

### 2. Authentifizierung

Bevor Terraform gestartet werden kann, ist eine Anmeldung bei GCP erforderlich:

```powershell
gcloud auth login
```

### 3. Infrastruktur starten

1. Navigiere in den Ordner: `cd terraform`
2. Kopiere `terraform.tfvars.example` zu `terraform.tfvars`.
3. Trage deine Werte (Projekt-ID, Regionen, Passwörter, Cockroach API-Key) in die `terraform.tfvars` ein.
4. Führe die Bereitstellung aus:

   ```powershell
   terraform init
   terraform apply
   ```

---

## 🧪 Testen des Systems

Das System ist standardmässig **nicht öffentlich** erreichbar. Nur autorisierte Benutzer (siehe `authorized_invokers` in `variables.tf`) können die API aufrufen.

### Manueller Test (PowerShell)

```powershell
$URL = (terraform output -raw api_url)
$TOKEN = (gcloud auth print-identity-token)

curl.exe -X POST $URL `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{"event_id": "1", "user_id": "test-user-001"}'
```

---

## 🚀 Lasttest-Leitfaden (Scale Test)

Das System ist darauf ausgelegt, massiv parallelisierte Anfragen zu verarbeiten. Um einen Test mit z.B. **16.000 Anfragen** durchzuführen, folge diesen Schritten:

### 1. Kapazität in Terraform erhöhen

Stelle sicher, dass die `max_instance_count` in der `terraform/main.tf` hoch genug eingestellt ist:

- **Validation Function:** `50` (kann bis zu 4.000 parallele Requests verarbeiten: 50 Instanzen × 80 Concurrency).
- **Worker Function:** `20` (begrenzt durch DB-Verbindungen im Free-Tier).

### 2. Durchführung mit PowerShell

Nutze das mitgelieferte Skript `test-call.ps1`. Für 16.000 Anfragen wird ein hohes Throttle-Limit empfohlen, aber achte auf die Ressourcen deines lokalen PCs (RAM/CPU):

```powershell
# Beispiel für einen massiven Testlauf
# $totalRequests = 1..16000
# ThrottleLimit 100-500 empfohlen (je nach PC-Leistung)
.\test-call.ps1
```

### 3. Monitoring & Verifikation

Während und nach dem Test kannst du den Erfolg in der GCP Console oder via SQL prüfen:

- **Cloud Functions Logs:** Prüfe auf "SOLD_OUT" Meldungen oder Fehler.
- **SQL Check:**

  ```sql
  -- Prüfe die Anzahl der verkauften Tickets
  SELECT count(*) FROM tickets;
  -- Prüfe die Restkapazität des Events
  SELECT remaining_capacity FROM events WHERE id = '1';
  ```

### ⚠️ Wichtige Hinweise zum Free-Tier

- **Kosten:** 16.000 Requests verbrauchen weniger als 1% des monatlichen GCP Free-Tier Kontingents (2 Mio. Requests).
- **Datenbank:** CockroachDB Serverless erlaubt bis zu 10 Mio. RUs pro Monat. Dieser Test verbraucht ca. 50k-80k RUs.
- **Lokale Limits:** PowerShell kann bei sehr hohen `-ThrottleLimit` (>500) instabil werden. Erhöhe das Limit schrittweise.

---

## 📊 Datenbank-Schema

Das Datenbankschema wird **automatisch via Terraform** provisioniert. Sobald `terraform apply` abgeschlossen ist, sind folgende Tabellen in der CockroachDB vorhanden:

- **events**: Speichert Events, Gesamtkapazität und Restplätze.
- **tickets**: Speichert die vergebenen Tickets mit Referenz zum User und Event.

Ein Beispiel-Event ("Pitbull im Hallenstadion Zürich", 15000 Plätze) wird bei der Initialisierung automatisch erstellt.

---

## 📂 Projektstruktur

```text
.
├── docs/               # Dokumentation & Diagramme
├── terraform/          # Infrastruktur-as-Code (Terraform)
│   ├── src/            # Quellcode der Cloud Functions
│   │   ├── validation/ # Node.js 24 Code (Ingress & Auth)
│   │   └── worker/     # Node.js 24 Code (DB Writing)
│   ├── main.tf         # Haupt-Terraform Datei (GCP & Cockroach)
│   └── variables.tf    # Konfigurations-Variablen
├── test-call.ps1       # Lokales Test-Skript (PowerShell)
└── README.md           # Diese Dokumentation
```

---

## 💰 Kostenkontrolle

Um hohe Kosten während der Entwicklung zu vermeiden:

- **Max Instances:** Die Cloud Functions sind auf 5 Instanzen limitiert.
- **Auto-Delete:** Führe `terraform destroy` aus, wenn das Projekt nicht mehr benötigt wird.
- **Free Tiers:** Das Projekt nutzt primär die Free-Tier Kontingente von GCP und CockroachDB.

---

## Hilfreiche SQL Scripts zum testen

Alle Events laden:

```sql
SELECT * FROM events;
```

Alle Tickets laden:

```sql
SELECT * FROM tickets;
```

Initiales Event auf 15'000 Plätze zurücksetzen:

```sql
UPDATE events SET total_capacity = 15000, remaining_capacity = 15000 WHERE id = 1;
```

Alle Tickets löschen:

```sql
delete from tickets;
```

Zeitspanne der Ticket-Erstellung (Performance-Analyse). Dieses Query kann nach der Ausführung von `test-call.ps1` verwendet werden, um die tatsächliche Durchlaufzeit und Performance des Systems zu messen:

```sql
SELECT
  MIN(created_at) AS first_ticket_created_at,
  MAX(created_at) AS last_ticket_created_at,
  MAX(created_at) - MIN(created_at) AS time_elapsed,
  COUNT(*) AS total_tickets_created
FROM tickets;
```
