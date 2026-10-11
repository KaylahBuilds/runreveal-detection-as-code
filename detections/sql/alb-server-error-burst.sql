SELECT
    sourceID,
    httpRequestHost,
    count() AS server_errors,
    groupUniqArray(10)(httpResponseStatus) AS response_codes,
    min(receivedAt) AS first_received,
    max(receivedAt) AS last_received
FROM http_logs
WHERE receivedAt >= {from:DateTime}
  AND receivedAt < {to:DateTime}
  AND sourceType = 'alb'
  AND toUInt16OrZero(httpResponseStatus) >= 500
  AND toUInt16OrZero(httpResponseStatus) < 600
GROUP BY sourceID, httpRequestHost
HAVING server_errors >= 10
ORDER BY server_errors DESC
