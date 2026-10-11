SELECT
    srcIP,
    webaclId,
    count() AS blocked_requests,
    groupUniqArray(10)(terminatingRuleId) AS terminating_rules,
    min(receivedAt) AS first_received,
    max(receivedAt) AS last_received
FROM aws_waf_logs
WHERE receivedAt >= {from:DateTime}
  AND receivedAt < {to:DateTime}
  AND sourceType = 'aws-waf'
  AND action = 'BLOCK'
GROUP BY srcIP, webaclId
HAVING blocked_requests >= 20
ORDER BY blocked_requests DESC
