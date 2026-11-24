# Harness report - andres-cespedes (simulacion local)

Automated score: **20.0 / 70.0**

| Req | Title | Status | Points |
|---|---|---|---|
| R1 | Every API action emits one valid event | not_verified | 0.0/7 |
| R2 | No event loss under burst, API stays fast | not_verified | 0.0/6 |
| R3 | Live view fed by the stream (event time) | not_verified | 0.0/7 |
| R4 | Events reach the S3 landing zone | not_verified | 0.0/4 |
| R5 | Star schema tables per contract | passed | 7.0/7 |
| R6 | Star integrity (keys, orphans, duplicates) | passed | 5.0/5 |
| R7 | Business queries return the right numbers | failed | 0.0/11 |
| R8 | Dirty events handled, refresh in time | failed | 2.0/6 |
| R9 | Slowly changing dimension (type 2) | failed | 4.0/8 |
| R10 | Partition pruning and scan limit | failed | 2.0/4 |
| R11 | Minimal Kinesis stream | not_verified | 0.0/3 |
| R12 | Cost projection | not_verified | 0.0/2 |

## R1 Every API action emits one valid event - not_verified

## R2 No event loss under burst, API stays fast - not_verified

## R3 Live view fed by the stream (event time) - not_verified

## R4 Events reach the S3 landing zone - not_verified

## R5 Star schema tables per contract - passed
- passed: `test_tables_have_required_columns` 
- passed: `test_tables_are_parquet` 
- passed: `test_fact_search_partitioned_by_month` 
- passed: `test_dim_date_is_enriched_correctly` 

## R6 Star integrity (keys, orphans, duplicates) - passed
- passed: `test_dimension_keys_unique` 
- passed: `test_no_orphan_foreign_keys` 
- passed: `test_fact_grain_one_row_per_event` 

## R7 Business queries return the right numbers - failed
- failed: `test_q1_revenue_by_month_and_fare_class` 6 groups with wrong revenue, e.g. (2025, 1, 'BUSINESS'): 335920916 vs 226386477
- failed: `test_q2_cancellations_per_route` cancellations/bookings per route differ, e.g. ADZ-SMR
- failed: `test_q3_bookings_per_weekday_name` {'Wednesday': 399, 'Monday': 343, 'Friday': 354, 'Saturday': 345, 'Tuesday': 376, 'Thursday': 422, 'Sunday': 361} vs {'Friday': 331, 'Monday': 378, 'Saturday': 381, 'Sunday': 359, 'Thursday': 408, 'Tuesday': 372, 'Wednesday': 371}
- failed: `test_q7_holidays_vs_other_days` (searches, bookings) holiday/non-holiday: {False: (16179, 2496), True: (821, 104)} vs {False: (16387, 2525), True: (613, 75)}
- failed: `test_q8_long_weekends` {False: 2438, True: 162} vs {False: 2430, True: 170}
- failed: `test_q4_top10_routes_by_revenue` routes ['BOG-SMR', 'BGA-BOG', 'CLO-CTG', 'BAQ-PSO', 'PEI-CLO', 'SMR-ADZ', 'CLO-BAQ', 'BAQ-CUC', 'BGA-CLO', 'ADZ-SMR'] vs ['BOG-SMR', 'BAQ-PSO', 'BGA-BOG', 'CLO-BAQ', 'BGA-CLO', 'CLO-CTG', 'BAQ-CUC', 'PEI-CLO', 'SMR-ADZ', 'ADZ-SMR']
- failed: `test_q6_conversion_inputs_per_route` searches/bookings per route differ, e.g. ADZ-SMR

## R8 Dirty events handled, refresh in time - failed
- passed: `test_refresh_finishes_in_time` 
- failed: `test_duplicates_removed` fact_booking_event: 3176 rows / 3176 distinct replay events, expected 2912 (duplicates must be removed, nothing lost)
- failed: `test_late_events_use_event_date` 90 dates with wrong counts, e.g. 20250112: 318 vs 183 (date_key must come from event_ts)
- evidence: refresh state SUCCEEDED in 1s

## R9 Slowly changing dimension (type 2) - failed
- passed: `test_route_dimension_is_type2` 
- failed: `test_q5_revenue_uses_category_valid_at_event_date` 6 groups differ, e.g. ('REGIONAL', 2025, 1): 483063886 vs 326826491 (as-of join needed)

## R10 Partition pruning and scan limit - failed
- failed: `test_one_month_query_scans_less` month 2025-01 has 9700 searches, expected 5905
- passed: `test_workgroup_has_scan_limit` 

## R11 Minimal Kinesis stream - not_verified

## R12 Cost projection - not_verified
