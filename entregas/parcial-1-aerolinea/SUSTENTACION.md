# Sustentación — Parcial 1 · Sistema de reservas de una aerolínea

> Hoja de repaso. Todo lo que hay que decir, las cifras medidas y cómo responder un cambio en el
> momento. Detalle completo en `documento/` y en `GUIA-EJECUCION-AWS.md`.

---

## 1. El sistema en 30 segundos

> Un sistema de reservas cuyo problema central es **no vender dos veces el mismo asiento** cuando
> muchos compran a la vez. Lo resolví con **bloqueo optimista** —la verificación de capacidad va
> dentro del mismo `UPDATE`— más un `CHECK` en la base como segunda capa. Lo probé con 30 pedidos
> simultáneos sobre 1 asiento: **se confirma exactamente 1**. La analítica corre en una **base
> separada** en esquema estrella, alimentada por ETL, y el histórico va a un **data lake en S3**
> consultado con Athena. Todo corre en AWS, con las bases privadas dentro de una VPC.

## 2. Las cinco ideas que sostienen todo

1. **El invariante es la capacidad *vendible*, no la física.** `capacidad_vendible = f(física, política)`. Por eso un overbooking del 5 % es una fila de configuración, no un rediseño.
2. **Verificar y escribir en una sola operación.** Sin hueco entre leer y escribir no hay carrera que ganar.
3. **Dos capas de protección.** Si el código falla, la base rechaza. El `CHECK` encontró un bug en mi propio generador de datos.
4. **Transaccional y analítica, separadas.** Un reporte pesado nunca puede frenar la venta de pasajes.
5. **Cada decisión con su alternativa descartada.** Lo que se evalúa es si el diseño absorbe un cambio, y eso se decide al diseñar.

---

## 3. Por sección — la defensa es eliminatoria en cada una

| Sección | Qué decir | Decisión clave · alternativa descartada |
|---|---|---|
| **0 · Supuestos** | 9 supuestos declarados, con cifras: 20 rutas, 60 vuelos/día, 50 reservas/min, búsqueda:reserva 50:1, temporada alta ×5 | Un supuesto declarado es una decisión; uno oculto es un agujero. `SUP-09`: la restricción del equipo se recibe hoy |
| **5.1 · Requisitos funcionales** | 19 `FR-`. El que importa: **`FR-07` — nunca confirmar más asientos que la capacidad vendible**. `FR-17` separa la política de capacidad del avión | La capacidad **vendible** y no la física → overbooking como configuración |
| **5.2 · No funcionales** | 10 `NFR-` medibles y 7 riesgos. **`NFR-CONC-01`: cero sobreventas**, N pedidos sobre M asientos → exactamente M | **99,9 %** de disponibilidad, **no 99,99 %**: 43 min al mes alcanzan y el salto cuesta desproporcionado |
| **5.3 · Modelo ER** | `RESERVA → ITINERARIO → TRAMO → INSTANCIA_VUELO`. La instancia tiene `version` y los dos `CHECK` de sobreventa | **Itinerario como entidad** · `Reserva → Vuelo` directo: no permitiría escalas, codeshare ni cancelar un solo tramo |
| **5.4 · Backend** | 8 decisiones `DEC-01`–`08`. **Monolito modular**; **hold** de 30 min; **pago por webhook idempotente** | **`DEC-03` bloqueo optimista** · pesimista: serializa las ventas del mismo vuelo, que es justo lo que no se quiere |
| **5.5 · Frontend** | **SPA** para el embudo (`DEC-09`), **SSE** para avisar asiento tomado (`DEC-10`), portal separado para agencias (`DEC-11`) | **SSE** · *polling*: a 2.500 búsquedas/min multiplica la carga de lectura, que es el cuello de botella |
| **5.6 · Implementación** | FastAPI + PostgreSQL. Pool de conexiones. **Prueba con barrera**: los 30 hilos salen a la vez | Pool y no conexión única: con una sola conexión la prueba pasa **por el motivo equivocado** — no hay paralelismo real |
| **5.7 · AWS** | 2 RDS privadas, EC2 en la VPC, data lake de 3 zonas, catálogo de Glue, Athena. **Costo total: ~$2,70** | **Particionado mensual** por fecha de vuelo (ADR #1) · diario: archivos de 15 KB |
| **§4 · Prompt log** | 22 entradas: qué pedí, qué devolvió, **qué corregí**. Las decisiones de diseño las tomé yo, una en contra de la recomendación de la IA | La IA encontró la conexión única antes de probar; también desplegó una vez un script con bug — está registrado |

---

## 4. Cifras para tener a mano — todas medidas, ninguna estimada

| | Cifra |
|---|---|
| **Concurrencia con lock** (AWS y local) | **1 de 30** confirmada · 29 rechazos `409` explícitos |
| **Concurrencia sin lock** | local: **4 reservas sobre 1 asiento** · AWS: **2 vivas con el contador en 1** |
| ETL OLTP → OLAP | **141 dimensiones + 9.122 hechos en 2,4 s** |
| Mismas 17 tablas, CSV vs Parquet | **2.915.371 → 941.399 bytes** (3,1×) |
| **Athena, misma consulta** | **586.285 bytes en CSV vs 2.339 en Parquet** (**250×**) · `count(*)` en Parquet: **0 bytes** |
| Particionado mensual | los hechos cayeron en **2 particiones, no 60** · archivo mayor: 81 KB |
| Ticket business última hora vs económica anticipada | **4,9 veces** |
| Costo total en AWS | **~$2,70** — ~$1 de trabajo (08/09 ~$0,64 · 10/09 ~$0,35) + ~$1,70 por dejar las RDS encendidas hasta la defensa, por decisión propia |
| Proyección mensual de la plataforma de datos | **≈ $33/mes** · las dos RDS son el **93 %** · volumen ×10 → **×1,84**, no ×10 |
| Modelo | 17 tablas · 19 `FR` · 10 `NFR` · 7 `RSK` · 12 `DEC` · 9 `SUP` |

---

## 5. Cómo responder un cambio que no está previsto

**El formato de la defensa:** el profesor plantea un cambio o un problema y hay que proponer la
solución en el momento. Método en cinco pasos, siempre el mismo:

> **1.** ¿Qué requisito toca? (`FR`/`NFR`) · **2.** ¿Qué entidad? · **3.** ¿Qué decisión (`DEC`)?
> · **4.** ¿Es **política** (configuración) o **estructura** (esquema)? · **5.** ¿Cuánto cuesta y
> qué alternativa ya estaba considerada?

### Banco de respuestas

| Si plantea… | Respuesta | Costo |
|---|---|---|
| **Overbooking del 5 %** | Una fila en `POLITICA_CAPACIDAD`. El `UPDATE` compara contra la capacidad **vendible**, que ya sale de la política. No cambia ni una tabla | **Nulo** |
| **Codeshare** | `operado_por` en `TRAMO` ya existe. Se agrega la aerolínea al catálogo | Bajo |
| **Un tramo se cancela y el resto vuela** | `TRAMO` tiene identidad propia: se cancela solo | Bajo |
| **Derecho al olvido** | `anonimizado_en` ya está: se borran los datos personales y se conservan los hechos para la analítica | Bajo |
| **Viajero frecuente** | Entidades colgando de `PASAJERO` y una dimensión en `TARIFA`. No toca inventario ni concurrencia | Medio, aislado |
| **Cae la pasarela de pagos** | El hold sobrevive y vence solo (`DEC-02`, `DEC-07`). Las reservas se siguen creando `retenidas` | **Bajo** |
| **El webhook de pago llega repetido** | Ya está resuelto: el segundo pago devuelve `"idempotente": true` y no cobra — **probado en AWS** | Nulo |
| **Un vuelo muy disputado dispara los reintentos** | Ese vuelo pasa a cola serializada; el resto sigue optimista. El módulo `inventario` permite convivir con las dos | Medio, acotado |
| **Tráfico ×10** | Réplicas de lectura + caché de disponibilidad. `busqueda` es el primer módulo en extraerse: es de sólo lectura | Medio |
| **Volumen ×100** | `INSTANCIA_VUELO` se particiona por fecha. La contención no crece: sigue siendo por vuelo | Medio, operativo |
| **×100 en *búsquedas*** | Eso sí cambia la arquitectura: ~1.000 M filas/año. Es el disparador declarado para pasar de batch a streaming | Alto |
| **Analítica en tiempo real** | Cambia la frecuencia del ETL o se pasa a CDC. **El backend no cambia**: la frontera de `DEC-08` sigue | Medio, aislado |
| **Ocultar el precio a los analistas** | IAM no alcanza: permisos por tabla, no por columna. Vista materializada sin esa columna, o Lake Formation | Medio |
| **Operar en 3 monedas** | El frontend ya recibe monto + moneda y sólo formatea (`DEC-12`). El trabajo es de tasas con vigencia en el backend | Bajo en el front |
| **Aviso instantáneo de asiento tomado** | Ya está: es el SSE de `DEC-10` | Nulo |
| **Las agencias piden otro SLA** | La API B2B ya está separada (`DEC-04`): cuota e infraestructura propias | Bajo |

---

## 6. Demostración en vivo

En la terminal de la EC2 (**Consola EC2 → `api-parcial` → Conectar → EC2 Instance Connect**):

```bash
cd /opt/aerolinea && . .venv/bin/activate && set -a && . ~/aerolinea.env && set +a
curl -s localhost:8010/salud                  # → "modo_inventario":"seguro"
python api/prueba_concurrencia.py --url http://127.0.0.1:8010 --peticiones 30
sed -n '/def _comprometer_seguro/,/return cur.rowcount/p' api/repositorio.py
```

| # | Qué mostrar | Dónde | Tiempo |
|---|---|---|---|
| 1 | RDS → *Accesible públicamente: **No*** | consola RDS | 30 s |
| 2 | `curl /salud` → `seguro` | EC2 | 30 s |
| 3 | **Prueba de concurrencia: 1 de 30** | EC2 | 1 min |
| 4 | La función: la condición **dentro** del `UPDATE` | EC2 | 1 min |
| 5 | Las tres zonas del lago | consola S3 | 30 s |
| 6 | **Athena: CSV vs Parquet** — mirar *"Datos analizados"* | consola Athena | 1 min |

**Si algo se cae:** la sesión del lab venció → *Start Lab*. La API no responde →
`sudo systemctl restart aerolinea`. Y como respaldo, **toda la evidencia está en el repo**:
`evidencia/concurrencia/` y `evidencia/aws/sesion-2026-09-10.md`.

> **La corrida sin lock** no conviene hacerla en vivo: son tres pasos de ida y tres de vuelta, y
> hay que restaurar en orden. Mostrar el resultado guardado: **2 reservas vivas con el contador
> diciendo 1** — una actualización perdida. El sistema no sabe que vendió de más.

---

## 7. Preguntas trampa

| Pregunta | Respuesta |
|---|---|
| **¿Esto es Big Data?** | **No.** 9.000 filas caben en un teléfono. Construí la arquitectura que hace falta cuando lo sea, y calculé dónde está ese punto: ~1.000 M filas/año, y no se llega vendiendo más sino guardando las búsquedas que no terminan en compra |
| **¿Por qué no microservicios?** | Partir el inventario en servicios convierte un `UPDATE` atómico en una transacción distribuida — justo lo que hay que evitar. El monolito es modular: `busqueda` se extrae primero si hace falta |
| **¿No dijiste que las bases no escuchan en internet?** | El régimen es privado. Para la carga inicial abrí el 5432 a **una sola IP** y lo cerré en la misma sesión. Hoy ni eso: la carga se hace desde la EC2, dentro de la VPC |
| **¿Dónde corre el ETL?** | OLTP → OLAP, en la EC2: 9.000 filas en 2,4 s, un job de Glue tardaría más en arrancar. La extracción al data lake, en un **job de Glue**: nació cuando no había nada dentro de la VPC, y deja probado el camino para cuando el ETL del OLAP necesite Spark. **Es una desviación del diseño y está declarada en 5.7** |
| **¿Están las dos bases registradas en el Glue Data Catalog?** | Sí, **a través de sus copias en S3**: el OLTP en `aerolinea_raw` y `aerolinea_processed` (17 tablas cada una), el OLAP en `aerolinea_catalog` (8). Las conexiones JDBC a las dos existen y la del OLTP la usa el job. **No corrí un crawler JDBC directo**: una tabla catalogada por JDBC es sólo metadato y Athena no la puede leer; sobre S3 es consultable. Para cumplirlo al pie de la letra: dos crawlers sobre las conexiones, 5 minutos, ~$0,25. Está declarado en 5.7 |
| **¿Por qué la prueba no borra cualquier reserva?** | Porque el esquema **protege los registros financieros**: `pago` y `comision` no se borran en cascada. Un pago es auditoría. La prueba usa una instancia de vuelo propia |
| **¿Usaste IA?** | Sí, y el prompt log registra qué corregí. Las decisiones de diseño fueron mías — una, en contra de lo que recomendaba la IA |
| **¿Qué falló?** | Tres bugs que sólo aparecieron en AWS, todos corregidos y reprobados. Y la primera versión del data lake tenía tres zonas con datos en una sola: lo detecté releyendo la evidencia contra el diagrama |

---

## 8. Después de la defensa — hoy

Hay **tres recursos cobrando**: las dos RDS (~$0,86/día, **aunque estén detenidas**) y la EC2
(~$0,25/día; detenida **se reinicia sola** en la próxima sesión). En CloudShell:

```bash
aws rds delete-db-instance --db-instance-identifier parcial-oltp --skip-final-snapshot --delete-automated-backups --region us-east-1
aws rds delete-db-instance --db-instance-identifier parcial-olap --skip-final-snapshot --delete-automated-backups --region us-east-1
aws ec2 terminate-instances --instance-ids i-0154fecb40194d171 --region us-east-1
aws ssm delete-parameters --names /parcial/pg_password /parcial/ep_oltp /parcial/ep_olap /parcial/bucket --region us-east-1
```

**No borrar** el bucket, el catálogo ni el job de Glue: cuestan centavos y los necesita el
Checkpoint 2.
