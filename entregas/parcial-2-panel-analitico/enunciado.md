SECOND MIDTERM

Airline Reservation System: Managerial Analytics Panel

Big Data and Data Engineering

## 1. Purpose

The first midterm asked you to design the airline reservation system and build its backend. In this midterm the system must work end to end and be measured: you add a frontend, a batch-processing path with AWS EMR, and an analytical query layer with AWS Glue Data Catalog and Amazon Athena, so that the airline's managers can see occupancy by route on a panel.

Two things change with respect to the first midterm. First, the requirements are verifiable: each one has an acceptance criterion that an automated test suite (the harness) checks against your running system. A requirement is either met or not; there is no credit for describing it. Second, the cheapest architecture that meets the requirements is the best one: a more expensive or more complex architecture earns no extra points and can lose them (R10–R12). The Learner Lab budget is US$50 per student account, so cost control is part of the exercise: stop RDS and EC2 when you are not working, test your PySpark job on a small sample before running the full dataset, and always terminate EMR.

## 2. Business scenario (continuation)

The airline now has two years of reservation history and wants a managerial panel. Management asks: "which routes fill their planes, and how did a given route perform in a given month?" The history is too large and too dirty to query directly from the transactional database:

- About 2 million reservation rows and the flights they belong to, exported as raw CSV files (section 4.1).
- The data contains inconsistent route spellings, inconsistent status values, duplicated rows, rows in unknown statuses, and invalid prices. The cleaning rules are fixed (C1–C5) so that the correct answers are unambiguous.
- Customers must keep being able to search and book while managers analyze history. Analytics must never slow down bookings.
Everything that is not fixed by this document (database engine, hosting model, framework, how often the batch job runs, how the panel is built) is your decision. You must keep the solution as simple and as cheap as the requirements allow and justify each choice (section 5).

## 3. Use of artificial intelligence assistants

AI assistants are allowed under the same rule as the first midterm: you must be able to explain and defend every decision. The prompt log appendix is mandatory. Note that here an assistant cannot "pass" for you: the harness runs against your deployed system, and the oral defense (section 8) asks you to explain and modify what you built.

## 4. Requirements and how each one is verified

The harness is a test suite you receive and may run as often as you like against your own system. The instructor runs the same suite, with the same thresholds but different, undisclosed probe values (the route and month pairs checked in R7 and R9), at the oral defense. Your team receives a seed; it determines your dataset and the expected answers.

### 4.1 Data and cleaning rules

Generate your raw files with the seed assigned to your team and store them in S3:

python -m airline_data.generate --seed <YOUR_SEED> --rows 2000000 --out raw/

Your EMR job (PySpark) must produce the curated data by applying these rules exactly:

| Rule | Definition |
|---|---|
| C1 | route: remove all whitespace and convert to upper case ( bog - mde  becomes BOG-MDE). |
| C2 | status: strip whitespace and convert to upper case. |
| C3 | Keep only reservations whose status is CONFIRMED or CANCELLED. |
| C4 | Drop reservations whose price_cents is missing or less than or equal to 0. |
| C5 | Drop duplicate reservation_id values, keeping the first occurrence. |

Occupancy of a route in a month is confirmed reservations divided by the total seat capacity of that route's flights in that month. Cancelled reservations do not count as sold seats.

### 4.2 Requirement table

| ID | Requirement (acceptance criterion) | How the harness verifies it | Pts |
|---|---|---|---|
| R1 | GET /flights/search answers with p95 latency of at most 1.0 s under 20 concurrent clients. | Sends 100 requests with 20 concurrent clients, measures p95, checks every response is 200 with a non-empty list. | 4 |
| R2 | No overselling. If N clients simultaneously book the last seat of a flight, exactly one receives 201 and all others 409. With K seats left (K assigned to your team), exactly K receive 201. Never a 5xx. | 50 simultaneous requests released by a barrier, repeated for several rounds, for 1 seat and for K seats; then checks the flight shows no seats left. | 10 |
| R3 | GET /reservations/{id} returns the reservation (200) or 404 if unknown. | Creates a reservation, reads it back, requests an unknown id. | 3 |
| R4 | An EMR job (cluster step or EMR Serverless) applies C1–C5 to the raw data and writes Parquet to S3, partitioned by month. | Finds a COMPLETED EMR run; checks Parquet files exist under 24 month= prefixes and were written during an EMR run; compares curated row count and confirmed revenue of three months with the expected values. | 8 |
| R5 | Both tables of the data contract exist in the Glue Data Catalog with the exact column names, Parquet format, and month partitions registered (or partition projection enabled). | Reads the table definitions from the Glue API. | 6 |
| R6 | Athena returns the correct top-10 routes by occupancy, and queries that filter by month do not scan the whole dataset. | Runs its own SQL on your metrics table and compares routes and values (tolerance 0.1 %); runs a one-month query and requires scanned bytes of at most 2 times the average partition size. | 8 |
| R7 | GET /analytics/occupancy?route=&month= returns the correct value, read from Athena, within 10 s. | Queries 5 (route, month) pairs chosen from your seed, compares occupancy, seats sold and capacity, and checks Athena's query history shows queries made during the calls. | 8 |
| R8 | In the web frontend a user can search for a flight, reserve it and see a confirmation containing the reservation id. | Drives a real browser (Playwright) through the flow using the selectors of Appendix A, then reads the reservation from the backend. | 6 |
| R9 | The manager panel shows the same occupancy value as the endpoint. | Loads the panel in the browser for a probe route and month; compares the displayed percentage with the endpoint and with the expected value (tolerance 0.001). | 4 |
| R10 | No EMR resources are left running, and EMR usage is bounded. | Checks there are no active clusters or started EMR Serverless applications, and that normalized instance hours are at most 150 (a 3-node m4.large cluster running half an hour uses 6). | 5 |
| R11 | The architecture is simple and low cost: only small instance classes (EMR: m4.large only), no Multi-AZ, no NAT Gateway, at most 8 distinct billable AWS services. | Lists RDS, EC2, EMR, NAT, load balancers and other billable resources through the AWS APIs. | 4 |
| R12 | Your monthly cost projection (cost_projection.yaml) is at most 1.5 times the instructor's reference solution and never above US$50, and is consistent with what you actually deployed. | Sums your line items; estimates the cost of the live resources; requires them to agree within 25 %. | 4 |

The requirements add up to 70 points, which is 70 % of the grade (section 7).

Instance classes allowed in R11: RDS db.t3/db.t4g micro and small; EC2 t3/t4g micro, small and (t3) medium; EMR m4.large only (the type available in the Learner Lab). Your whole project must fit in the Learner Lab budget of US$50, shared with everything else you run in the lab: the harness fails any projection above it. Prices change; the harness thresholds file is the authority.

### 4.3 What the harness cannot verify

Some things only a person can judge. They are assessed by the instructor's review of the document and by the oral defense:

- Whether your justifications are correct and linked to a requirement and to the Well-Architected pillars.
- Whether you really wrote the PySpark job and understand it (the harness only checks that its output is right and that EMR produced it).
- Whether the architecture diagram matches what is deployed.

## 5. Decisions you must make and justify

For each decision write a short paragraph that cites a requirement (R1–R12 or your own from the first midterm) and one or more Well-Architected pillars.

- Hosting model. Where do the backend, frontend and transactional database run? Why that and not a more managed (or less managed) option? What is the cheapest option that still meets R1 and R2?
- Why EMR here. The course requires EMR in this project. Explain what the batch job does that Athena alone could not do, and which alternatives you considered (AWS Glue job, Athena CTAS). Which EMR option did you choose (cluster or Serverless), with which instance types, and how do you guarantee it is shut down (R10)?
- Data layout. Why Parquet? Why partition by month? What would happen to the bytes scanned in R6 without it?
- How the panel gets its numbers. Why query Athena from the endpoint? What are the consequences for latency, cost per query and freshness? Would a cache be justified?
- Separation of workloads. How do you make sure analytical work never slows bookings (R1, R2)?
- Service justification table (same format as the first midterm): service, alternative considered, requirement supported, Well-Architected pillar(s).
- Cost projection (cost_projection.yaml plus a short narrative): assumptions, line items, and what happens to the cost if data volume or query volume is multiplied by 10, connected to the cost optimization and sustainability pillars.

## 6. Running the harness

cp config.example.yaml config.yaml     # set seed, backend/frontend URLs, Athena database and tables

pytest                                 # writes report.json and report.md

- Use your normal AWS credentials (environment or ~/.aws). Never commit credentials.
- The Learner Lab can change public IP addresses when it restarts: update the URLs in config.yaml before each run. The instructor's run uses the URLs in your submitted configuration and the system must be up during the agreed grading window.
- If the Learner Lab role cannot read some information (for example listing a service), the report marks that part not verified instead of passed. Mention such cases in your document so they can be checked manually.
- Include your final report.md in the submission. If a requirement fails, explain in the document why and what you would change.

## 7. Deliverables and evaluation

| Deliverable | Content |
|---|---|
| Partial submission | Section 5 draft: architecture diagram, service justification table, and first cost projection (before building). |
| Final submission | Updated document (sections 5 and 6), repository with backend, frontend and PySpark job, config.yaml (without credentials), cost_projection.yaml, final report.md, and prompt log appendix. |

| Component | Weight | Source |
|---|---|---|
| Automated requirements R1–R12 | 70 % | Harness (points in section 4.2) |
| Document: justifications, Well-Architected, cost narrative, traceability to requirements | 15 % | Instructor review |
| Oral defense | 15 % | Instructor |

## 8. Oral defense

All team members must be able to explain any part of the system, The instructor may ask you to change something live (for example, a different cleaning rule or a different aggregation) and to say which parts of the system, the data and the tests would be affected.

The oral defense is eliminatory for the corresponding section: if the team cannot coherently support a decision or a component, the points for that section are voided, including points earned in the harness, regardless of the quality of the code or the report.

## Appendix A. Contracts

### A.1 API

| Endpoint | Behavior |
|---|---|
| POST /admin/flights | Body {flight_id, route, flight_date, capacity, price_cents}. 201; 409 if the id exists. Used by the harness to create test flights. |
| GET /flights/search?origin=&destination=&date= | 200 with a list of {flight_id, route, flight_date, seats_available, price_cents}. Flights with no seats may be omitted. |
| POST /reservations | Body {flight_id, passenger_name, fare_class}. 201 {reservation_id, flight_id, status: CONFIRMED, passenger_name}; 409 if no seats; 404 if the flight is unknown. |
| GET /reservations/{id} | 200 with the same shape; 404 if unknown. |
| GET /analytics/occupancy?route=&month= | 200 {route, month, occupancy (0..1), seats_sold, seats_capacity} computed from Athena; 404 if there is no data. |
| GET /health | 200. |

### A.2 Tables (Glue Data Catalog / Athena)

reservations_curated: Parquet, columns in this order reservation_id, flight_id, route, fare_class, price_cents (bigint), status; partition column month (string, YYYY-MM, month of the flight date); 24 partitions.

route_month_metrics: Parquet, columns route, month, seats_capacity, seats_sold, occupancy (double), revenue_cents, bookings, cancellations (all counts bigint). seats_sold and bookings count CONFIRMED reservations only.

### A.3 Frontend selectors

Layout and style are free. Use these data-testid attributes. Customer page (/): search-origin, search-destination, search-date, search-submit, flight-row (each containing reserve-button), passenger-name, confirm-submit, confirmation-id (text is exactly the reservation id). Manager page (/manager): manager-route, manager-month, manager-load, occupancy-value (a percentage with at least one decimal, such as 78.4%).

### A.4 cost_projection.yaml

assumptions: "users, requests per day, data size"

line_items:

- {service: "RDS", detail: "db.t3.micro, 20 GB, single AZ", monthly_usd: 14.0}

- {service: "EC2", detail: "t3.small backend + frontend", monthly_usd: 15.2}

- {service: "S3", detail: "...", monthly_usd: 1.0}

- {service: "Athena", detail: "...", monthly_usd: 0.5}

- {service: "EMR", detail: "1 run per month, 3 x m5.xlarge, 0.5 h", monthly_usd: 1.0}

Do not write a total: the harness computes it from the line items.
