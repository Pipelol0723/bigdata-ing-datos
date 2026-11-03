#!/usr/bin/env bash
# =============================================================================
#  10-taller.sh — el taller de Kinesis completo, en CloudShell (us-east-1)
# =============================================================================
#  Laboratorios 1 a 5 de la guía y el reto final (3 shards + segunda Lambda), con la salida
#  guardada en ~/k/resultados/taller/ para armar el informe.
#
#  ⚠️ CREA RECURSOS QUE COBRAN MIENTRAS EXISTAN: los streams (por shard-hora), el Firehose y el
#  bucket. NO los borra: la limpieza es 90-limpieza.sh, que se corre con confirmación del alumno.
#
#  Uso:  nohup bash ~/k/infra/10-taller.sh > ~/k/resultados/taller.log 2>&1 &
# =============================================================================
set -uo pipefail
export AWS_PAGER=""
CUENTA=$(aws sts get-caller-identity --query Account --output text)
ROL=arn:aws:iam::$CUENTA:role/LabRole
BUCKET=taller-kinesis-ac-$CUENTA
STREAM=taller-kinesis-sensores
STREAM3=taller-kinesis-3shards
OUT=~/k/resultados/taller
mkdir -p "$OUT"
cd ~/k/codigo
paso() { echo; echo "=================== $* ($(date -u +%H:%M:%S) UTC)"; }
ahora_ms() { echo $(( $(date +%s) * 1000 )); }
ahora_iso() { date -u +%Y-%m-%dT%H:%M:%S+00:00; }
esperar_trigger() {  # espera a que un event source mapping quede Enabled
    for _ in $(seq 1 40); do
        s=$(aws lambda get-event-source-mapping --uuid "$1" --query State --output text)
        [ "$s" = "Enabled" ] && break
        sleep 5
    done
    echo "trigger $1: $s"
}

paso "L0 preparación"
aws sts get-caller-identity --query '{cuenta:Account,rol:Arn}'
python3 -c "import boto3; print('boto3', boto3.__version__)"

paso "L1 crear el stream (provisionado, 1 shard)"
python3 -c "from comun import crear_stream; crear_stream('$STREAM', 1)"
aws kinesis describe-stream-summary --stream-name $STREAM \
    --query 'StreamDescriptionSummary.{estado:StreamStatus,shards_abiertos:OpenShardCount,retencion_horas:RetentionPeriodHours,modo:StreamModeDetails.StreamMode}'
ARN_STREAM=$(aws kinesis describe-stream-summary --stream-name $STREAM --query StreamDescriptionSummary.StreamARN --output text)

paso "L2 productor de la guía: 200 eventos, después otros 200"
python3 productor.py $STREAM 200 | tail -2
T_SEGUNDA=$(ahora_iso)
sleep 2
python3 productor.py $STREAM 200 | tail -1
echo "-- IncomingRecords por minuto (CloudWatch, la métrica tarda ~1 min)"
sleep 75
aws cloudwatch get-metric-statistics --namespace AWS/Kinesis --metric-name IncomingRecords \
    --dimensions Name=StreamName,Value=$STREAM --start-time "$(date -u -d '-10 min' +%FT%TZ)" \
    --end-time "$(date -u +%FT%TZ)" --period 60 --statistics Sum \
    --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]' --output text

paso "L3 tipos de iterador (400 registros en el stream; la segunda tanda empezó a las $T_SEGUNDA)"
python3 consumidor.py --stream $STREAM --tipo TRIM_HORIZON --segundos 12 --nombre trim_horizon
python3 consumidor.py --stream $STREAM --tipo AT_TIMESTAMP --ts "$T_SEGUNDA" --segundos 12 --nombre at_timestamp
echo "-- LATEST: se abre el iterador y DESPUÉS se producen 100 registros"
python3 consumidor.py --stream $STREAM --tipo LATEST --segundos 25 --nombre latest &
sleep 3
python3 productor.py $STREAM 100 > /dev/null
wait

paso "L3 dos consumidores a la vez sobre el mismo shard"
python3 consumidor.py --stream $STREAM --tipo TRIM_HORIZON --segundos 15 --nombre consumidor_1 &
python3 consumidor.py --stream $STREAM --tipo TRIM_HORIZON --segundos 15 --nombre consumidor_2 &
wait

paso "L4 Lambda procesar-sensores (LabRole) con trigger del stream"
rm -f /tmp/procesar.zip && python3 -m zipfile -c /tmp/procesar.zip lambda_procesar.py
aws lambda create-function --function-name procesar-sensores --runtime python3.12 --role "$ROL" \
    --handler lambda_procesar.lambda_handler --zip-file fileb:///tmp/procesar.zip --timeout 30 \
    --query '{funcion:FunctionName,rol:Role}' || echo "(ya existía)"
aws lambda wait function-active-v2 --function-name procesar-sensores
UUID=$(aws lambda list-event-source-mappings --function-name procesar-sensores --query 'EventSourceMappings[0].UUID' --output text)
if [ "$UUID" = "None" ] || [ -z "$UUID" ]; then
    UUID=$(aws lambda create-event-source-mapping --function-name procesar-sensores --event-source-arn "$ARN_STREAM" \
        --batch-size 100 --maximum-batching-window-in-seconds 5 --starting-position LATEST --query UUID --output text)
fi
esperar_trigger "$UUID"
sleep 30  # con LATEST, el trigger toma posición cuando ya está activo
DESDE=$(ahora_ms)
python3 productor.py $STREAM 200 > /dev/null
sleep 40
python3 logs_lambda.py --funcion procesar-sensores --desde-ms "$DESDE" --etiqueta "batch=100,ventana=5s"

paso "L4 batch size 5 y ventana 0"
aws lambda update-event-source-mapping --uuid "$UUID" --batch-size 5 --maximum-batching-window-in-seconds 0 \
    --query '{batch:BatchSize,ventana:MaximumBatchingWindowInSeconds}'
sleep 10
esperar_trigger "$UUID"
sleep 20
DESDE=$(ahora_ms)
python3 productor.py $STREAM 200 > /dev/null
sleep 40
python3 logs_lambda.py --funcion procesar-sensores --desde-ms "$DESDE" --etiqueta "batch=5,ventana=0s"

paso "L5 bucket y Firehose (fuente: el stream; destino: S3 particionado por fecha)"
aws s3 mb "s3://$BUCKET" 2>&1 | tail -1
cat > /tmp/firehose-s3.json <<EOF
{"RoleARN": "$ROL", "BucketARN": "arn:aws:s3:::$BUCKET",
 "Prefix": "sensores/anio=!{timestamp:yyyy}/mes=!{timestamp:MM}/dia=!{timestamp:dd}/",
 "ErrorOutputPrefix": "errores-firehose/!{firehose:error-output-type}/",
 "BufferingHints": {"SizeInMBs": 1, "IntervalInSeconds": 60}}
EOF
PLAN=firehose
if aws firehose create-delivery-stream --delivery-stream-name taller-kinesis-a-s3 \
        --delivery-stream-type KinesisStreamAsSource \
        --kinesis-stream-source-configuration "KinesisStreamARN=$ARN_STREAM,RoleARN=$ROL" \
        --extended-s3-destination-configuration file:///tmp/firehose-s3.json; then
    for _ in $(seq 1 40); do
        e=$(aws firehose describe-delivery-stream --delivery-stream-name taller-kinesis-a-s3 \
            --query DeliveryStreamDescription.DeliveryStreamStatus --output text)
        [ "$e" = "ACTIVE" ] && break
        [ "$e" = "CREATING_FAILED" ] && break
        sleep 10
    done
    echo "Firehose: $e"
    [ "$e" = "ACTIVE" ] || PLAN=b
else
    PLAN=b
fi
if [ "$PLAN" = "b" ]; then
    echo "-- Firehose no disponible con LabRole: PLAN B (Lambda que escribe en S3)"
    rm -f /tmp/planb.zip && python3 -m zipfile -c /tmp/planb.zip lambda_plan_b_s3.py
    aws lambda create-function --function-name taller-kinesis-plan-b --runtime python3.12 --role "$ROL" \
        --handler lambda_plan_b_s3.lambda_handler --zip-file fileb:///tmp/planb.zip --timeout 30 \
        --environment "Variables={BUCKET=$BUCKET}" --query FunctionName
    aws lambda wait function-active-v2 --function-name taller-kinesis-plan-b
    U=$(aws lambda create-event-source-mapping --function-name taller-kinesis-plan-b --event-source-arn "$ARN_STREAM" \
        --batch-size 100 --maximum-batching-window-in-seconds 10 --starting-position LATEST --query UUID --output text)
    esperar_trigger "$U"
    sleep 30
fi
echo "plan usado: $PLAN"
python3 productor.py $STREAM 200 > /dev/null
python3 productor.py $STREAM 200 > /dev/null
echo "-- esperando el buffer de 60 s"
sleep 100
aws s3 ls "s3://$BUCKET/sensores/" --recursive
echo "-- líneas entregadas: $(aws s3 cp "s3://$BUCKET/sensores/" /tmp/sensores --recursive --quiet && cat $(find /tmp/sensores -type f) | wc -l)"
aws firehose describe-delivery-stream --delivery-stream-name taller-kinesis-a-s3 \
    --query 'DeliveryStreamDescription.Destinations[0].ExtendedS3DestinationDescription.{prefijo:Prefix,buffer:BufferingHints}' 2>/dev/null

paso "L5 extensión: Athena sobre lo que llegó a S3"
python3 athena.py --salida "s3://$BUCKET/athena-results/" --sql "CREATE DATABASE IF NOT EXISTS taller_kinesis"
python3 athena.py --db taller_kinesis --salida "s3://$BUCKET/athena-results/" --csv-dir "$OUT" --sql "
-- tabla externa sobre el JSON que dejó la entrega
CREATE EXTERNAL TABLE IF NOT EXISTS sensores (
  contenedor_id string, temperatura double, humedad double, \`timestamp\` string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://$BUCKET/sensores/';
-- temperatura promedio por contenedor
SELECT contenedor_id, round(avg(temperatura), 2) AS temp_prom, count(*) AS n,
       sum(CASE WHEN temperatura > 8 THEN 1 ELSE 0 END) AS alertas
FROM sensores GROUP BY contenedor_id ORDER BY temp_prom DESC"

paso "RETO 1: 3 shards y tres partition keys distintas"
python3 -c "from comun import crear_stream; crear_stream('$STREAM3', 3)"
for CLAVE in contenedor constante aleatoria; do
    T=$(ahora_iso)
    sleep 1
    python3 productor.py $STREAM3 300 $CLAVE > /dev/null
    sleep 2
    python3 contador_por_shard.py --stream $STREAM3 --desde-ts "$T" --etiqueta "$CLAVE" --csv "$OUT/reto_shards.csv"
done

paso "RETO 2: segunda Lambda que cuenta alertas por contenedor y escribe el resumen en S3"
aws lambda update-event-source-mapping --uuid "$UUID" --batch-size 100 --maximum-batching-window-in-seconds 5 > /dev/null
rm -f /tmp/contar.zip && python3 -m zipfile -c /tmp/contar.zip lambda_contar_alertas.py
aws lambda create-function --function-name contar-alertas --runtime python3.12 --role "$ROL" \
    --handler lambda_contar_alertas.lambda_handler --zip-file fileb:///tmp/contar.zip --timeout 30 \
    --environment "Variables={BUCKET=$BUCKET}" --query FunctionName || echo "(ya existía)"
aws lambda wait function-active-v2 --function-name contar-alertas
U2=$(aws lambda create-event-source-mapping --function-name contar-alertas --event-source-arn "$ARN_STREAM" \
    --batch-size 100 --maximum-batching-window-in-seconds 5 --starting-position LATEST --query UUID --output text)
esperar_trigger "$U2"
esperar_trigger "$UUID"
sleep 30
DESDE=$(ahora_ms)
python3 productor.py $STREAM 200 > /dev/null
sleep 45
python3 logs_lambda.py --funcion procesar-sensores --desde-ms "$DESDE" --etiqueta "procesar-sensores (misma tanda)"
aws s3 ls "s3://$BUCKET/resumen-alertas/" --recursive
python3 - "$BUCKET" <<'EOF'
import boto3, json, sys
s3 = boto3.client("s3")
b = sys.argv[1]
objs = s3.list_objects_v2(Bucket=b, Prefix="resumen-alertas/").get("Contents", [])
total, registros, por = 0, 0, {}
for o in objs:
    r = json.loads(s3.get_object(Bucket=b, Key=o["Key"])["Body"].read())
    total += r["total_alertas"]; registros += r["registros"]
    for k, v in r["alertas_por_contenedor"].items():
        por[k] = por.get(k, 0) + v
print(f"RESUMEN contar-alertas: lotes={len(objs)} registros={registros} alertas={total}")
print("alertas por contenedor:", dict(sorted(por.items())))
if objs:
    print("ejemplo:", s3.get_object(Bucket=b, Key=objs[0]["Key"])["Body"].read().decode()[:400])
EOF

paso "Inventario de lo creado (para la limpieza)"
aws kinesis list-streams --query StreamNames
aws lambda list-functions --query "Functions[?contains(FunctionName,'sensores')||contains(FunctionName,'alertas')||contains(FunctionName,'plan-b')].FunctionName"
aws firehose list-delivery-streams --query DeliveryStreamNames
echo "FIN-TALLER"
