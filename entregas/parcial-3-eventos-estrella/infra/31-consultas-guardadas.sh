#!/usr/bin/env bash
# =============================================================================
#  Parcial 3 · 31: guarda las consultas de la demo como "Saved queries" del workgroup parcial3
# =============================================================================
#  En la consola de Athena: Query editor → workgroup "parcial3" → pestaña "Saved queries" → un clic
#  y se corre. Guardar una consulta no cobra nada (sólo se cobra al ejecutarla). Si ya existe una
#  con el mismo nombre, no la duplica.
#  Uso (CloudShell):  bash ~/p3/infra/31-consultas-guardadas.sh
# =============================================================================
set -uo pipefail
source "$(dirname "$0")/00-comun.sh"

EXISTENTES=$(for id in $(aws athena list-named-queries --work-group "$WG" --query 'NamedQueryIds' --output text); do
    aws athena get-named-query --named-query-id "$id" --query 'NamedQuery.Name' --output text; done)

guardar () {   # $1 = nombre, $2 = descripción, stdin = SQL
    local sql; sql=$(cat)
    if printf '%s\n' "$EXISTENTES" | grep -qxF "$1"; then echo "  ya existe: $1"; return; fi
    aws athena create-named-query --work-group "$WG" --database "$DB" --name "$1" \
        --description "$2" --query-string "$sql" --query NamedQueryId --output text >/dev/null && echo "  guardada: $1"
}

guardar "P3-1 SCD2 dim_route" "Versiones de cada ruta (R9)" <<'SQL'
SELECT route, route_category, valid_from, valid_to, is_current, version
FROM dim_route ORDER BY route, valid_from;
SQL
guardar "P3-2 Q5 ingreso por categoria vigente" "As-of join contra la SCD 2 (Q5)" <<'SQL'
SELECT r.route_category, d.year, d.month, SUM(f.revenue_cents) / 100 AS ingreso_neto
FROM fact_booking_event f
JOIN dim_route r ON f.route_key = r.route_key
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY 1, 2, 3 ORDER BY 2, 3, 1;
SQL
guardar "P3-3 Q6 conversion por ruta" "Dos hechos con la dimension conformada dim_route (Q6)" <<'SQL'
WITH b AS (SELECT r.route, COUNT(*) AS busquedas FROM fact_search f
           JOIN dim_route r ON f.route_key = r.route_key GROUP BY 1),
     v AS (SELECT r.route, SUM(f.bookings) AS reservas FROM fact_booking_event f
           JOIN dim_route r ON f.route_key = r.route_key GROUP BY 1)
SELECT b.route, b.busquedas, COALESCE(v.reservas, 0) AS reservas,
       ROUND(100.0 * COALESCE(v.reservas, 0) / b.busquedas, 2) AS conversion_pct
FROM b LEFT JOIN v ON b.route = v.route ORDER BY conversion_pct DESC;
SQL
guardar "P3-4 Q1 ingreso por mes y clase" "Ingreso neto por mes y clase tarifaria (Q1)" <<'SQL'
SELECT d.year, d.month, c.fare_class, SUM(f.bookings) AS reservas, SUM(f.cancellations) AS cancelaciones,
       SUM(f.revenue_cents) / 100 AS ingreso_neto
FROM fact_booking_event f
JOIN dim_date d ON f.date_key = d.date_key
JOIN dim_fare_class c ON f.fare_class_key = c.fare_class_key
GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
SQL
guardar "P3-5 Q7 Q8 festivos y puentes" "Reservas en festivos y dias de puente (Q7, Q8)" <<'SQL'
SELECT d.is_holiday, d.is_long_weekend, SUM(f.bookings) AS reservas, COUNT(DISTINCT d.date_key) AS dias
FROM fact_booking_event f JOIN dim_date d ON f.date_key = d.date_key
GROUP BY 1, 2 ORDER BY 1, 2;
SQL
guardar "P3-6 dim_date puentes enero 2025" "Calendario enriquecido: festivos y puentes" <<'SQL'
SELECT full_date, weekday_name, holiday_name, is_holiday, is_long_weekend
FROM dim_date WHERE year = 2025 AND month = 1 AND (is_holiday OR is_long_weekend) ORDER BY full_date;
SQL
guardar "P3-7 R10 poda por mes" "Comparar 'Datos escaneados': un mes vs todos (R10)" <<'SQL'
SELECT month, COUNT(*) AS busquedas, SUM(results_count) AS resultados
FROM fact_search WHERE month = '2025-01' GROUP BY 1;
SQL
guardar "P3-8 dedup y grano" "Una fila por event_id en cada hecho (R6, R8)" <<'SQL'
SELECT 'fact_search' AS tabla, COUNT(*) AS filas, COUNT(DISTINCT event_id) AS eventos FROM fact_search
UNION ALL
SELECT 'fact_booking_event', COUNT(*), COUNT(DISTINCT event_id) FROM fact_booking_event;
SQL
echo "Listo: Athena → workgroup $WG → Saved queries"
