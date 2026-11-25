#!/usr/bin/env bash
# =============================================================================
#  Parcial 3 · 30: demo de punta a punta para la sustentación (no crea ni borra recursos)
# =============================================================================
#  Muestra los dos caminos con tráfico REAL de la API, en vivo, en ~3 minutos:
#    1. crea un vuelo de demo y hace 8 búsquedas, 2 reservas y 1 cancelación;
#    2. camino rápido: /analytics/live refleja los eventos en segundos;
#    3. camino analítico: espera el buffer de Firehose (~70 s), pide el refresh y muestra los
#       eventos de HOY en la estrella (Athena).
#  ¿Interfiere con el harness del profesor? No:
#    - los eventos de la demo tienen fecha de hoy y no empiezan con "rp-";
#    - R5-R10 sólo miran "rp-";
#    - R10 sólo cuenta 2025-01.
#  Es seguro correrlo antes o después de 80-archivar-landing.sh.
#
#  Uso (CloudShell):  bash ~/p3/infra/30-demo.sh [RUTA]      (por defecto BGA-BOG)
# =============================================================================
set -uo pipefail
source "$(dirname "$0")/00-comun.sh"
RUTA="${1:-BGA-BOG}"; O="${RUTA%-*}"; D="${RUTA#*-}"
IP=$(ip_ec2); B="http://$IP:8000"
[ -n "$IP" ] && [ "$IP" != "None" ] || { echo "!! la EC2 no está running"; exit 1; }
FECHA=$(date -u -d '+30 days' +%Y-%m-%d)
VUELO="DEMO-$(date -u +%H%M%S)"
j () { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

paso "API en $B"
curl -fs "$B/health"; echo
echo "vista en vivo ANTES: $(curl -fs "$B/analytics/live?window=5")"

paso "vuelo $VUELO ($RUTA, $FECHA) + 8 búsquedas + 2 reservas + 1 cancelación"
curl -fs -X POST "$B/admin/flights" -H 'Content-Type: application/json' \
    -d "{\"flight_id\":\"$VUELO\",\"route\":\"$RUTA\",\"flight_date\":\"$FECHA\",\"capacity\":10,\"price_cents\":350000}" >/dev/null
for i in 1 2 3 4 5 6 7 8; do
    curl -fs -o /dev/null -H "X-Session-Id: demo-$VUELO-$i" "$B/flights/search?origin=$O&destination=$D&date=$FECHA"
done
R1=$(curl -fs -X POST "$B/reservations" -H 'Content-Type: application/json' \
    -d "{\"flight_id\":\"$VUELO\",\"passenger_name\":\"Demo Uno\",\"fare_class\":\"ECONOMY\"}" | j "d['reservation_id']")
R2=$(curl -fs -X POST "$B/reservations" -H 'Content-Type: application/json' \
    -d "{\"flight_id\":\"$VUELO\",\"passenger_name\":\"Demo Dos\",\"fare_class\":\"BUSINESS\"}" | j "d['reservation_id']")
echo "reservas: $R1 $R2"
echo "cancelar $R1: $(curl -fs -X POST "$B/reservations/$R1/cancel" | j "d['status']")"
echo "cancelar $R1 otra vez (409 esperado): $(curl -s -o /dev/null -w '%{http_code}' -X POST "$B/reservations/$R1/cancel")"

paso "CAMINO RÁPIDO: vista en vivo (lee el stream, cuenta por event_ts)"
for s in 2 4 6; do sleep 2; echo "  +${s}s: $(curl -fs "$B/analytics/live?window=5")"; done
echo "  pipeline: $(curl -fs "$B/admin/pipeline")"

paso "CAMINO ANALÍTICO: esperando el buffer de Firehose (~70 s)"
sleep 75
echo "landing: $(aws s3 ls "$RAW_URI" --recursive | wc -l) objetos"
curl -fs -X POST "$B/admin/refresh-star"; echo
for _ in $(seq 1 30); do
    S=$(curl -fs "$B/admin/refresh-status"); echo "$S" | grep -q '"RUNNING"' || break; sleep 3
done
echo "refresh: $S"

paso "la estrella en Athena: los eventos de HOY ($RUTA)"
HOY=$(date -u +%Y%m%d)
cat > /tmp/demo.sql <<SQL
SELECT f.event_type, f.bookings, f.cancellations, f.revenue_cents, r.route, r.route_category, c.fare_class, d.weekday_name
FROM fact_booking_event f
JOIN dim_route r ON f.route_key = r.route_key
JOIN dim_fare_class c ON f.fare_class_key = c.fare_class_key
JOIN dim_date d ON f.date_key = d.date_key
WHERE f.date_key = $HOY AND f.flight_id = '$VUELO'
SQL
QID=$(aws athena start-query-execution --work-group "$WG" --query-execution-context Database="$DB" \
    --query-string file:///tmp/demo.sql --query QueryExecutionId --output text)
for _ in $(seq 1 30); do
    E=$(aws athena get-query-execution --query-execution-id "$QID" --query QueryExecution.Status.State --output text)
    [ "$E" = "SUCCEEDED" ] || [ "$E" = "FAILED" ] && break; sleep 1
done
aws athena get-query-results --query-execution-id "$QID" --output text \
    --query 'ResultSet.Rows[].Data[].VarCharValue' | xargs -n 8 | column -t
echo
echo "(neto de la demo: +350000 +350000 -350000 = 350000 centavos; 2 bookings, 1 cancellation)"
