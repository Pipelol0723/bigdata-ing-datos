# Harness report - andres-cespedes (API local + Kinesis simulado)

Automated score: **20.0 / 70.0**

| Req | Title | Status | Points |
|---|---|---|---|
| R1 | Every API action emits one valid event | passed | 7.0/7 |
| R2 | No event loss under burst, API stays fast | passed | 6.0/6 |
| R3 | Live view fed by the stream (event time) | passed | 7.0/7 |
| R4 | Events reach the S3 landing zone | not_verified | 0.0/4 |
| R5 | Star schema tables per contract | not_verified | 0.0/7 |
| R6 | Star integrity (keys, orphans, duplicates) | not_verified | 0.0/5 |
| R7 | Business queries return the right numbers | not_verified | 0.0/11 |
| R8 | Dirty events handled, refresh in time | not_verified | 0.0/6 |
| R9 | Slowly changing dimension (type 2) | not_verified | 0.0/8 |
| R10 | Partition pruning and scan limit | not_verified | 0.0/4 |
| R11 | Minimal Kinesis stream | not_verified | 0.0/3 |
| R12 | Cost projection | not_verified | 0.0/2 |

## R1 Every API action emits one valid event - passed
- passed: `test_each_action_emits_one_valid_event` 
- evidence: 30 search events for 30 calls; 4 reservation events for 3 reservations + 1 cancel

## R2 No event loss under burst, API stays fast - passed
- passed: `test_burst_no_loss_and_fast_api` 
- evidence: 200 searches, concurrency 50: p95=0.008s, status codes [200]
- evidence: 200 events in the stream for 200 requests

## R3 Live view fed by the stream (event time) - passed
- passed: `test_live_reflects_new_events` 
- passed: `test_live_uses_event_time` 
- evidence: live deltas after 1.4s: searches 10/10, reservations 3/3, cancellations 1/1
- evidence: live searches after replaying 17000 old events: 240

## R4 Events reach the S3 landing zone - not_verified

## R5 Star schema tables per contract - not_verified

## R6 Star integrity (keys, orphans, duplicates) - not_verified

## R7 Business queries return the right numbers - not_verified

## R8 Dirty events handled, refresh in time - not_verified

## R9 Slowly changing dimension (type 2) - not_verified

## R10 Partition pruning and scan limit - not_verified

## R11 Minimal Kinesis stream - not_verified

## R12 Cost projection - not_verified
