"""Reto final de los ejercicios: un "grupo de consumidores" mínimo con leases en DynamoDB.

Es la idea de KCL reducida a lo esencial. La tabla `leases` tiene un ítem por shard:
    shard_id (clave) · propietario · expira_en (epoch) · checkpoint (último SequenceNumber procesado)

Cada consumidor, en un ciclo:
1. deja un latido (ítem `consumidor#<nombre>` con vencimiento): así los demás saben cuántos hay vivos;
2. renueva sus leases con una escritura CONDICIONAL (propietario = yo); si falla, perdió el shard;
3. calcula su cuota = ceil(shards abiertos / consumidores vivos): si tiene de más, libera (con
   checkpoint); si tiene de menos, toma shards libres o vencidos, también con escritura condicional:
   si dos compiten por el mismo, DynamoDB deja ganar a uno solo;
4. lee sus shards desde el checkpoint (AFTER_SEQUENCE_NUMBER) y guarda checkpoint cada N registros.
Si un consumidor muere, sus leases vencen y otro los toma desde el checkpoint: los registros entre el
último checkpoint y la caída se procesan dos veces (entrega "al menos una vez").

    python3 leases.py --crear-tabla
    python3 leases.py --stream ej-reshard --nombre A --segundos 120 --log procesados-A.csv
    python3 leases.py --estado
Los shards cerrados por un reshard se ignoran: esta versión sólo reparte los abiertos (KCL, además,
termina de leer el padre antes de entregar los hijos).
"""
import argparse
import csv
import math
import time

import boto3

from comun import REGION, iterador, kinesis, shards_abiertos

ap = argparse.ArgumentParser()
ap.add_argument("--stream", default="ej-reshard")
ap.add_argument("--tabla", default="kinesis-leases")
ap.add_argument("--nombre", default="A")
ap.add_argument("--segundos", type=int, default=120)
ap.add_argument("--vida", type=int, default=15, help="segundos de validez de un lease")
ap.add_argument("--renovar", type=float, default=4, help="cada cuántos segundos se renueva y rebalancea")
ap.add_argument("--checkpoint-cada", type=int, default=50)
ap.add_argument("--log", help="CSV de registros procesados")
ap.add_argument("--crear-tabla", action="store_true")
ap.add_argument("--estado", action="store_true", help="muestra la tabla de leases y sale")
args = ap.parse_args()

ddb = boto3.client("dynamodb", region_name=REGION)
YO = args.nombre
LATIDO = "consumidor#"  # prefijo de los ítems de latido; el resto de los ítems son shards


def crear_tabla():
    try:
        ddb.create_table(TableName=args.tabla, BillingMode="PAY_PER_REQUEST",
                         KeySchema=[{"AttributeName": "shard_id", "KeyType": "HASH"}],
                         AttributeDefinitions=[{"AttributeName": "shard_id", "AttributeType": "S"}])
    except ddb.exceptions.ResourceInUseException:
        pass
    ddb.get_waiter("table_exists").wait(TableName=args.tabla)
    print(f"[ok] tabla {args.tabla} lista")


def leer_tabla():
    items = ddb.scan(TableName=args.tabla, ConsistentRead=True)["Items"]
    return {i["shard_id"]["S"]: {"propietario": i.get("propietario", {}).get("S"),
                                 "expira_en": float(i.get("expira_en", {}).get("N", 0)),
                                 "checkpoint": i.get("checkpoint", {}).get("S")} for i in items}


def condicional(**kw):
    """Escritura condicional: True si se aplicó, False si otro consumidor ganó."""
    try:
        ddb.update_item(TableName=args.tabla, **kw)
        return True
    except ddb.exceptions.ConditionalCheckFailedException:
        return False


def tomar(shard_id, ahora):
    return condicional(
        Key={"shard_id": {"S": shard_id}},
        UpdateExpression="SET propietario = :yo, expira_en = :exp",
        ConditionExpression="attribute_not_exists(shard_id) OR expira_en < :ahora OR propietario = :yo",
        ExpressionAttributeValues={":yo": {"S": YO}, ":exp": {"N": str(ahora + args.vida)},
                                   ":ahora": {"N": str(ahora)}})


def renovar(shard_id, ahora):
    return condicional(
        Key={"shard_id": {"S": shard_id}}, UpdateExpression="SET expira_en = :exp",
        ConditionExpression="propietario = :yo",
        ExpressionAttributeValues={":yo": {"S": YO}, ":exp": {"N": str(ahora + args.vida)}})


def guardar_checkpoint(shard_id, secuencia):
    return condicional(
        Key={"shard_id": {"S": shard_id}}, UpdateExpression="SET checkpoint = :cp",
        ConditionExpression="propietario = :yo",
        ExpressionAttributeValues={":yo": {"S": YO}, ":cp": {"S": secuencia}})


def liberar(shard_id):
    """Devuelve un shard al grupo: vence ya, conserva el checkpoint para quien lo tome."""
    return condicional(
        Key={"shard_id": {"S": shard_id}}, UpdateExpression="SET expira_en = :cero",
        ConditionExpression="propietario = :yo",
        ExpressionAttributeValues={":yo": {"S": YO}, ":cero": {"N": "0"}})


def latir(ahora):
    ddb.put_item(TableName=args.tabla, Item={"shard_id": {"S": LATIDO + YO},
                                             "expira_en": {"N": str(ahora + args.vida)}})


def mostrar_estado():
    ahora = time.time()
    tabla = leer_tabla()
    vivos = sorted(k[len(LATIDO):] for k, l in tabla.items() if k.startswith(LATIDO) and l["expira_en"] > ahora)
    print(f"consumidores vivos: {', '.join(vivos) or '-'}")
    print(f"{'shard':22} {'propietario':11} {'vence en':>8}  checkpoint")
    for s, l in sorted(tabla.items()):
        if s.startswith(LATIDO):
            continue
        vence = l["expira_en"] - ahora
        print(f"{s:22} {l['propietario'] or '-':11} {vence:7.0f}s  ...{(l['checkpoint'] or '-')[-8:]}"
              f"{'  (VENCIDO o LIBRE)' if vence < 0 else ''}")


def evento(texto):
    print(f"[{time.strftime('%H:%M:%S')}] {YO}: {texto}", flush=True)


def consumir():
    # buffering=1: cada fila llega al disco al escribirse, aunque el proceso muera con kill -9
    log = csv.writer(open(args.log, "w", newline="", buffering=1)) if args.log else None
    if log:
        log.writerow(["t", "consumidor", "shard", "secuencia", "clave"])
    mios = {}                          # shard_id -> iterador
    pendientes, ultimo = {}, {}        # registros desde el último checkpoint / última secuencia leída
    fin, ultimo_ciclo = time.monotonic() + args.segundos, 0.0
    while time.monotonic() < fin:
        ahora = time.time()
        if ahora - ultimo_ciclo >= args.renovar:
            ultimo_ciclo = ahora
            latir(ahora)
            for s in list(mios):
                if not renovar(s, ahora):
                    evento(f"perdió {s}")
                    del mios[s]
            abiertos = [s["ShardId"] for s in shards_abiertos(args.stream)]
            tabla = leer_tabla()
            vivos = {k[len(LATIDO):] for k, l in tabla.items()
                     if k.startswith(LATIDO) and l["expira_en"] > ahora} | {YO}
            cuota = math.ceil(len(abiertos) / len(vivos))
            for s in sorted(mios)[cuota:]:  # de más: se devuelven con checkpoint
                if pendientes.get(s):
                    guardar_checkpoint(s, ultimo[s])
                    pendientes[s] = 0
                liberar(s)
                del mios[s]
                evento(f"liberó {s} (cuota {cuota} con {len(vivos)} vivos)")
            for s in abiertos:
                if len(mios) >= cuota:
                    break
                l = tabla.get(s)
                libre = l is None or l["expira_en"] < ahora or l["propietario"] == YO
                if s not in mios and libre and tomar(s, ahora):
                    cp = l["checkpoint"] if l else None
                    mios[s] = iterador(args.stream, s, "TRIM_HORIZON", despues_de=cp)
                    pendientes[s] = 0
                    evento(f"tomó {s} (cuota {cuota}, desde {'checkpoint ...' + cp[-8:] if cp else 'el principio'})")
        for s, it in list(mios.items()):
            r = kinesis.get_records(ShardIterator=it, Limit=200)
            for rec in r["Records"]:
                if log:
                    log.writerow([round(time.time(), 2), YO, s, rec["SequenceNumber"], rec["PartitionKey"]])
                ultimo[s] = rec["SequenceNumber"]
                pendientes[s] += 1
            mios[s] = r["NextShardIterator"]
            if pendientes[s] >= args.checkpoint_cada and guardar_checkpoint(s, ultimo[s]):
                pendientes[s] = 0
        time.sleep(0.3)  # < 5 GetRecords/s por shard
    for s in mios:  # salida ordenada: checkpoint final (un kill -9 no llega acá)
        if pendientes.get(s):
            guardar_checkpoint(s, ultimo[s])
    evento(f"terminó con {sorted(mios)}")


if args.crear_tabla:
    crear_tabla()
elif args.estado:
    mostrar_estado()
else:
    consumir()
