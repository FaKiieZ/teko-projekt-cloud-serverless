$url = "https://us-central1-teko-serverless-ticketing.cloudfunctions.net/validation-function"
$token = gcloud auth print-identity-token
$totalRequests = 1..45

$totalRequests | ForEach-Object -Parallel {
    $currentUrl = $using:url
    $currentToken = $using:token
    
    curl.exe -s -o /dev/null -w "%{http_code}\n" -X POST $currentUrl `
             -H "Authorization: Bearer $currentToken" `
             -H "Content-Type: application/json" `
             -d '{"event_id": 1,"user_id": 1}'
} -ThrottleLimit 15