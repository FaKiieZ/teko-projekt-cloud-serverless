# 🎫 Teko School Project: Serverless Ticketing System (GCP)

Dieses Schulprojekt demonstriert ein hochverfügbares, serverloses Ticket-Buchungssystem auf der Google Cloud Platform (GCP). Es wurde entwickelt, um Lastspitzen effizient zu bewältigen und gleichzeitig durch eine rein serverlose Architektur kosteneffizient zu bleiben.

---

## 🏗️ Architektur-Übersicht

Das System nutzt eine ereignisgesteuerte Warteschlangen-Architektur (Event-Driven Architecture), um Anfragen asynchron zu verarbeiten:

```mermaid
graph LR
    subgraph "Client"
        U[Benutzer / Test-Script]
    end

    subgraph "Ingress & Queue"
        LF1[Validation Function <br/><i>Cloud Run Function</i>]
        Queue[(Pub/Sub <br/><i>Ticket Queue</i>)]
    end

    subgraph "Processing & Persistence"
        LF2[Worker Function <br/><i>Cloud Run Function</i>]
        DB[(CockroachDB Serverless <br/><i>PostgreSQL compatible</i>)]
    end

    %% Datenfluss
    U -->|1. Ticket-Anfrage (HTTP)| LF1
    LF1 -->|2. Validieren & Einreihen| Queue
    Queue -->|3. Event-Trigger| LF2
    LF2 -->|4. Transaktion verbuchen| DB
```

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
gcloud auth application-default login
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

### Lasttest / Batch-Test

Im Root-Verzeichnis befindet sich ein PowerShell-Skript `test-call.ps1`, das mehrere Anfragen parallel sendet, um die Skalierung und die Warteschlange zu testen. Passe die `$url` im Skript an deinen Output an und starte es.

---

## 📊 Datenbank-Schema

Die **Validation Function** prüft beim ersten Aufruf automatisch, ob das Schema in der CockroachDB existiert. Falls nicht, wird es automatisch mit folgendem Aufbau angelegt:

- **events**: Speichert Events, Gesamtkapazität und Restplätze.
- **tickets**: Speichert die vergebenen Tickets mit Referenz zum User und Event.

Ein Beispiel-Event ("TEKO Konzert", 35 Plätze) wird bei der Initialisierung automatisch erstellt.

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
