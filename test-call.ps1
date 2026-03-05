# Lasttest-Skript für 16.000 Anfragen
# Nutzung: Vorher $URL setzen oder direkt im Skript anpassen

$url = "BITTE_HIER_URL_VON_TERRAFORM_OUTPUT_EINTRAGEN"
$token = gcloud auth print-identity-token
$requests = 1..16000

Write-Host "Starte Lasttest mit 16'000 Anfragen an $url..." -ForegroundColor Cyan

$requests | ForEach-Object -Parallel {
    $currentUrl = $using:url
    $currentToken = $using:token
    $id = $_
    
    $payload = "{`"event_id`": `"1`", `"user_id`": `"test-user-$id`"}"
    
    # Sendet Request und speichert den Status Code
    $statusCode = curl.exe -s -o /dev/null -w "%{http_code}" -X POST $currentUrl `
             -H "Authorization: Bearer $currentToken" `
             -H "Content-Type: application/json" `
             -d $payload
             
    # Output mit ID und Status Code
    Write-Host "[$id] Status: $statusCode"
} -ThrottleLimit 250

Write-Host "`nTest abgeschlossen." -ForegroundColor Green
