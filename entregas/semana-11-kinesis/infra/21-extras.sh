#!/usr/bin/env bash
# =============================================================================
#  21-extras.sh — corridas extra de los ejercicios 1 y 2 para cruzar los límites del shard
# =============================================================================
#  En la primera pasada, el productor a 1500 registros/s y la corrida C (3 consumidores, pausa
#  0,4) no provocaron errores: la latencia de cada llamada dejó la tasa real por debajo de lo
#  previsto. Acá se sube la presión para ver los límites en acción, sobre el mismo ej-compite.
#
#  Uso:  nohup bash ~/k/infra/21-extras.sh > ~/k/resultados/extras.log 2>&1 &
# =============================================================================
set -uo pipefail
export AWS_PAGER=""
OUT=~/k/resultados/ejercicios
cd ~/k/codigo
paso() { echo; echo "=================== $* ($(date -u +%H:%M:%S) UTC)"; }
INICIO=$(date -u +%FT%TZ)

paso "Ej1b productor a 5000 registros/s contra 1 shard (límite de escritura: 1000/s)"
python3 productor_param.py --stream ej-compite --tasa 5000 --duracion 20 --claves 8 \
    --csv "$OUT/ej1b_productor.csv" | tee "$OUT/ej1b_productor.log" | tail -22

paso "Ej2 corridas extra: 3 consumidores con pausa 0,1 (C2) y sin pausa (C3), productor 200/s"
python3 productor_param.py --stream ej-compite --tasa 200 --duracion 150 --claves 8 > "$OUT/ej2x_productor.log" &
PROD=$!
sleep 5
for spec in "C2 0.1" "C3 0"; do
    set -- $spec
    pids=()
    for c in 1 2 3; do
        python3 consumidor_shard.py --stream ej-compite --indice-shard 0 --pausa "$2" --desde LATEST \
            --segundos 60 --nombre "$1-c$c" --etiqueta "$1" --resumen "$OUT/ej2_resumen.csv" \
            --csv "$OUT/ej2_$1_c$c.csv" > "$OUT/ej2_$1_c$c.log" &
        pids+=($!)
    done
    wait "${pids[@]}"
    grep -h RESUMEN "$OUT"/ej2_"$1"_c*.log
done
kill $PROD 2>/dev/null; wait $PROD 2>/dev/null

paso "CloudWatch: límites excedidos en ej-compite (lectura y escritura, por minuto)"
sleep 90
for M in WriteProvisionedThroughputExceeded ReadProvisionedThroughputExceeded; do
    echo "-- $M"
    aws cloudwatch get-metric-statistics --namespace AWS/Kinesis --metric-name $M \
        --dimensions Name=StreamName,Value=ej-compite --start-time "$INICIO" \
        --end-time "$(date -u +%FT%TZ)" --period 60 --statistics Sum \
        --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]' --output text
done
echo "FIN-EXTRAS"
