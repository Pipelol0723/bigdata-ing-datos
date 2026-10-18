# Harness report - andres-cespedes

Automated score: **10.0 / 70.0**

| Req | Title | Status | Points |
|---|---|---|---|
| R1 | Flight search latency | not_verified | 0.0/4 |
| R2 | No overselling under concurrency | not_verified | 0.0/10 |
| R3 | Reservation retrieval | not_verified | 0.0/3 |
| R4 | EMR job produces curated Parquet | not_verified | 0.0/8 |
| R5 | Glue Catalog tables per contract | not_verified | 0.0/6 |
| R6 | Athena correctness and partition pruning | not_verified | 0.0/8 |
| R7 | Analytics endpoint backed by Athena | not_verified | 0.0/8 |
| R8 | Customer flow in browser | passed | 6.0/6 |
| R9 | Manager panel matches endpoint | passed | 4.0/4 |
| R10 | No leftover EMR / bounded EMR hours | not_verified | 0.0/5 |
| R11 | Simple low-cost architecture | not_verified | 0.0/4 |
| R12 | Cost projection | not_verified | 0.0/4 |

## R1 Flight search latency - not_verified

## R2 No overselling under concurrency - not_verified

## R3 Reservation retrieval - not_verified

## R4 EMR job produces curated Parquet - not_verified

## R5 Glue Catalog tables per contract - not_verified

## R6 Athena correctness and partition pruning - not_verified

## R7 Analytics endpoint backed by Athena - not_verified

## R8 Customer flow in browser - passed
- passed: `test_search_reserve_confirm` 
- evidence: UI created reservation RF73C1082C471439 for a flight; backend returns it

## R9 Manager panel matches endpoint - passed
- passed: `test_manager_panel_equals_endpoint` 
- evidence: PEI-CLO 2023-03: panel=0.8359 endpoint=0.8359 truth=0.8359

## R10 No leftover EMR / bounded EMR hours - not_verified

## R11 Simple low-cost architecture - not_verified

## R12 Cost projection - not_verified
