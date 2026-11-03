#!/usr/bin/env bash
# =============================================================================
#  20-ejercicios.sh — ejercicios adicionales de Kinesis (1 a 6 y el reto de leases), en CloudShell
# =============================================================================
#  Cada ejercicio deja su salida en ~/k/resultados/ejercicios/ (CSV y logs) para las tablas y los
#  gráficos del informe.
#
#  ⚠️ CREA STREAMS QUE COBRAN MIENTRAS EXISTAN: ej-compite (1 shard), ej-reparto (3),
#  ej-reshard (2 → 4), los consumidores enhanced fan-out y la tabla de DynamoDB. NO los borra:
#  la limpieza es 90-limpieza.sh, con confirmación del alumno.
#
#  Uso:  nohup bash ~/k/infra/20-ejercicios.sh > ~/k/resultados/ejercicios.log 2>&1 &
# =============================================================================
set -uo pipefail
export AWS_PAGER=""
OUT=~/k/resultados/ejercicios
mkdir -p "$OUT"
cd ~/k/codigo
paso() { echo; echo "=================== $* ($(date -u +%H:%M:%S) UTC)"; }
ahora_iso() { date -u +%Y-%m-%dT%H:%M:%S+00:00; }
crear() { python3 -c "from comun import crear_stream; crear_stream('$1', $2)"; }

paso "Ej1 productor parametrizable: 1500 registros/s contra 1 shard (límite: 1000/s)"
crear ej-compite 1
python3 productor_param.py --stream ej-compite --tasa 1500 --duracion 20 --claves 8 \
    --csv "$OUT/ej1_productor.csv" | tee "$OUT/ej1_productor.log" | tail -22

paso "Ej2 consumidores que compiten por un shard (productor: 200/s, 8 claves, 300 s)"
python3 productor_param.py --stream ej-compite --tasa 200 --duracion 300 --claves 8 > "$OUT/ej2_productor.log" &
PROD=$!
sleep 5
corrida() {  # corrida <etiqueta> <cantidad de consumidores> <pausa>
    local pids=()
    for c in $(seq 1 "$2"); do
        python3 consumidor_shard.py --stream ej-compite --indice-shard 0 --pausa "$3" --desde LATEST \
            --segundos 60 --nombre "$1-c$c" --etiqueta "$1" --resumen "$OUT/ej2_resumen.csv" \
            --csv "$OUT/ej2_$1_c$c.csv" > "$OUT/ej2_$1_c$c.log" &
        pids+=($!)
    done
    wait "${pids[@]}"
    grep -h RESUMEN "$OUT"/ej2_"$1"_c*.log
}
echo "-- corrida A: 1 consumidor, pausa 1.0";  corrida A 1 1.0
echo "-- corrida B: 3 consumidores, pausa 1.0"; corrida B 3 1.0
echo "-- corrida C: 3 consumidores, pausa 0.4"; corrida C 3 0.4
kill $PROD 2>/dev/null; wait $PROD 2>/dev/null
echo "-- métrica ReadProvisionedThroughputExceeded del stream (CloudWatch, por minuto)"
sleep 60
aws cloudwatch get-metric-statistics --namespace AWS/Kinesis --metric-name ReadProvisionedThroughputExceeded \
    --dimensions Name=StreamName,Value=ej-compite --start-time "$(date -u -d '-8 min' +%FT%TZ)" \
    --end-time "$(date -u +%FT%TZ)" --period 60 --statistics Sum \
    --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]' --output text

paso "Ej3 un shard por consumidor (ej-reparto: 3 shards; productor 300/s, 30 claves)"
crear ej-reparto 3
python3 productor_param.py --stream ej-reparto --tasa 300 --duracion 90 --claves 30 > "$OUT/ej3_productor.log" &
PROD=$!
sleep 5
pids=()
for i in 0 1 2; do
    python3 consumidor_shard.py --stream ej-reparto --indice-shard $i --pausa 0.4 --desde LATEST --segundos 60 \
        --nombre "D-shard$i" --etiqueta D --resumen "$OUT/ej3_resumen.csv" --csv "$OUT/ej3_shard$i.csv" \
        > "$OUT/ej3_shard$i.log" &
    pids+=($!)
done
wait "${pids[@]}"
grep -h RESUMEN "$OUT"/ej3_shard*.log
wait $PROD

paso "Ej4 shard caliente (ej-reparto, 30 claves): sesgo 0 contra sesgo 0.8"
for SESGO in 0 0.8; do
    T=$(ahora_iso)
    sleep 1
    python3 productor_param.py --stream ej-reparto --tasa 300 --duracion 30 --claves 30 --sesgo $SESGO \
        > "$OUT/ej4_productor_$SESGO.log"
    sleep 2
    python3 contador_por_shard.py --stream ej-reparto --desde-ts "$T" --etiqueta "sesgo=$SESGO" --csv "$OUT/ej4_shards.csv"
done

paso "Ej5 reshard en caliente (ej-reshard: 2 → 4 shards con datos entrando)"
crear ej-reshard 2
python3 productor_param.py --stream ej-reshard --tasa 50 --duracion 240 --claves 8 \
    --resumen "$OUT/ej5_totales.json" > "$OUT/ej5_productor.log" &
PROD=$!
sleep 100
python3 - <<'EOF'
from comun import kinesis, esperar_activo
r = kinesis.update_shard_count(StreamName="ej-reshard", TargetShardCount=4, ScalingType="UNIFORM_SCALING")
print("update_shard_count:", r["CurrentShardCount"], "->", r["TargetShardCount"])
esperar_activo("ej-reshard")
print("ACTIVE otra vez")
EOF
wait $PROD
tail -1 "$OUT/ej5_productor.log"
python3 consumidor_reshard.py --stream ej-reshard --esperados "$OUT/ej5_totales.json" --csv "$OUT/ej5_shards.csv"

paso "Ej6 (opcional) enhanced fan-out: 2 consumidores dedicados sobre ej-compite (productor 200/s)"
python3 productor_param.py --stream ej-compite --tasa 200 --duracion 100 --claves 8 > "$OUT/ej6_productor.log" &
PROD=$!
sleep 3
python3 efo.py --stream ej-compite --consumidores 2 --segundos 60 --resumen "$OUT/ej2_resumen.csv" \
    2>&1 | tee "$OUT/ej6_efo.log" | tail -6
wait $PROD

paso "RETO leases en DynamoDB: 4 shards abiertos de ej-reshard, 2 consumidores"
python3 leases.py --crear-tabla
python3 productor_param.py --stream ej-reshard --tasa 40 --duracion 210 --claves 16 > "$OUT/leases_productor.log" &
PROD=$!
python3 leases.py --stream ej-reshard --nombre A --segundos 170 --log "$OUT/leases_A.csv" > "$OUT/leases_A.log" 2>&1 &
PA=$!
sleep 2
python3 leases.py --stream ej-reshard --nombre B --segundos 170 --log "$OUT/leases_B.csv" > "$OUT/leases_B.log" 2>&1 &
PB=$!
sleep 35
echo "-- estado 1 (2 consumidores vivos)";        python3 leases.py --estado | tee "$OUT/leases_estado1.txt"
kill -9 $PB; echo "-- kill -9 de B a las $(date -u +%H:%M:%S)"
sleep 30
echo "-- estado 2 (B muerto hace 30 s)";          python3 leases.py --estado | tee "$OUT/leases_estado2.txt"
kill -9 $PA; echo "-- kill -9 de A a las $(date -u +%H:%M:%S); se reinicia con el mismo nombre"
sleep 3
python3 leases.py --stream ej-reshard --nombre A --segundos 45 --log "$OUT/leases_A2.csv" > "$OUT/leases_A2.log" 2>&1
echo "-- estado 3 (A reiniciado y terminado)";     python3 leases.py --estado | tee "$OUT/leases_estado3.txt"
wait $PROD
echo "-- eventos de cada consumidor"
cat "$OUT/leases_A.log" "$OUT/leases_B.log" "$OUT/leases_A2.log"
python3 - "$OUT" <<'EOF'
import csv, sys, collections
out = sys.argv[1]
filas = []
for n in ("A", "B", "A2"):
    try:
        filas += [dict(r, archivo=n) for r in csv.DictReader(open(f"{out}/leases_{n}.csv"))]
    except FileNotFoundError:
        pass
veces = collections.Counter(r["secuencia"] for r in filas)
dup = sum(v - 1 for v in veces.values() if v > 1)
print(f"RESUMEN leases: procesados={len(filas)} únicos={len(veces)} duplicados={dup}")
for n in ("A", "B", "A2"):
    fx = [r for r in filas if r["archivo"] == n]
    print(f"  {n}: {len(fx)} registros en {len({r['shard'] for r in fx})} shards")
EOF

paso "Inventario de lo creado (para la limpieza)"
aws kinesis list-streams --query StreamNames
aws dynamodb list-tables --query "TableNames[?contains(@,'leases')]"
echo "FIN-EJERCICIOS"
