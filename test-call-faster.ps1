# Lasttest-Skript für 16.000 Anfragen mit hey.exe
# Nutzung: Vorher $url setzen

$url = "BITTE_HIER_URL_VON_TERRAFORM_OUTPUT_EINTRAGEN"

Write-Host "Hole Authentifizierungstoken..." -ForegroundColor Cyan
$token = gcloud auth print-identity-token

# 1. Create a temporary file for the payload to avoid Windows escaping issues
$payloadFile = ".\hey_payload.json"
$payload = '{ "event_id": "1", "user_id": "hey-loadtest-user" }'
Set-Content -Path $payloadFile -Value $payload

Write-Host "Starte Lasttest mit 16'000 Anfragen (Concurrency: 250) an $url..." -ForegroundColor Cyan

# 2. Execute hey.exe
# -n 16000 : Total requests
# -c 250   : Concurrent requests (matches your ThrottleLimit)
# -m POST  : HTTP Method
# -H ...   : Headers (Token and Content-Type)
# -D ...   : Path to the payload file

.\hey.exe -n 16000 -c 250 -m POST `
    -H "Authorization: Bearer $token" `
    -H "Content-Type: application/json" `
    -D $payloadFile `
    $url

# 3. Cleanup the temporary payload file
Remove-Item -Path $payloadFile -ErrorAction SilentlyContinue

Write-Host "`nTest abgeschlossen." -ForegroundColor Green