# AWS Athena — German Credit: respuestas y conclusiones

**Big Data e Ingeniería de Datos (CC-IA-02)** · Universidad Sergio Arboleda · **Andres Felipe Cespedes Rondon** · 3 de noviembre de 2026

> **Sobre el enunciado.** La tarea de Moodle sólo dice *"Upload answers and conclusions"*; la guía se
> dio en clase y no quedó publicada. Se trabajó con el dataset original, *Statlog (German Credit Data)*
> de la UCI, y con las preguntas de negocio que ese dataset plantea: qué rasgos del solicitante se
> asocian al riesgo y qué política de aprobación minimiza el costo con la matriz de costos que trae
> la propia fuente. Si la guía pedía otras preguntas, el mismo pipeline las responde agregando una
> consulta.

## 1. El dataset

| Aspecto | Valor |
|---|---|
| Fuente | UCI Machine Learning Repository, *Statlog (German Credit Data)*, Prof. Hans Hofmann (Universidad de Hamburgo) |
| Filas | **1.000** solicitudes de crédito |
| Atributos | 20 (7 numéricos y 13 categóricos codificados: `A11`, `A43`…) + la clase |
| Clase | 1 = buen pagador (**700**) · 2 = mal pagador (**300**) |
| Matriz de costos | Aprobar a un mal pagador cuesta **5**; rechazar a uno bueno cuesta **1** |
| Archivo | `german.data`, texto separado por espacios, 79.793 bytes |

## 2. Cómo se armó en AWS

```
UCI ──curl──▶ S3 raw/german.data ──▶ tabla externa solicitudes_raw (texto, códigos)
                                        │  (Glue Data Catalog, creada con DDL de Athena)
                                        ▼
                                   vista solicitudes (códigos traducidos a texto)
                                        │  CTAS
                                        ▼
                         S3 parquet/ ──▶ tabla solicitudes_parquet (columnar, Snappy)
```

- **S3** guarda el archivo original (`raw/`), la copia en Parquet (`parquet/`) y los resultados de
  Athena. Bucket `german-credit-936980625651`.
- **Glue Data Catalog** guarda el esquema. Las tablas se crearon con DDL de Athena, sin crawler: el
  crawler cobra por corrida y no sabría nombrar ni traducir los códigos.
- **La vista** traduce cada código a texto legible (por ejemplo, `A11` → "< 0 DM"). No ocupa espacio
  ni cuesta: se resuelve en cada consulta.
- **CTAS** (`CREATE TABLE … AS SELECT`) escribe la vista como **Parquet**, para comparar lo que escanea
  Athena en cada formato.
- Todo el SQL se probó antes con **DuckDB** en la laptop sobre el mismo archivo ($0), y dio idéntico
  en Athena.

### Lo que cuesta cada formato (medido en Athena)

| Formato | Tamaño en S3 | Bytes escaneados por la misma consulta |
|---|---|---|
| Texto original | 79.793 B | **79.793 B** (lee siempre el archivo entero) |
| Parquet + Snappy | 14.543 B | **562 B** (sólo las 2 columnas que usa) |

Parquet es **5,5 veces más chico** y la consulta escanea **142 veces menos**. Con 1.000 filas no cambia
la factura, porque Athena cobra un mínimo de 10 MB por consulta (US$0,00005). Con millones de
solicitudes, es la diferencia entre pagar por el archivo entero o sólo por las columnas que se usan.

## 3. Respuestas

La **tasa de malos** es el porcentaje de solicitantes del grupo que resultaron malos pagadores. El
promedio general es **30 %**.

### Q01. ¿Qué tan balanceado está el dataset?

{{csv:resultados/01.csv}}

El 70 % son buenos pagadores. Un modelo que aprobara a todos acertaría el 70 % de las veces y aun así
sería el peor posible con la matriz de costos (ver Q13).

### Q02. ¿Importa el estado de la cuenta corriente?

{{csv:resultados/02.csv}}

**Es el factor más fuerte.** Con saldo negativo, casi la mitad no paga (49,3 %); sin cuenta corriente
en el banco, sólo el 11,7 %. Un saldo bajo en la cuenta es la señal de que la persona ya está ajustada.

### Q03. ¿Y el historial de crédito?

{{csv:resultados/03.csv}}

El resultado es **contraintuitivo**: los que no tienen créditos, o los pagaron todos, son los más
riesgosos (62,5 % y 57,1 %). Los de "cuenta crítica / créditos en otros bancos" son los menos (17,1 %).
La explicación probable es un sesgo de selección: a quien ya tiene varios créditos vigentes otros
bancos ya lo evaluaron y lo aprobaron. Es un ejemplo de por qué una correlación no se interpreta sin
contexto del negocio.

### Q04. ¿Para qué se pide el crédito?

{{csv:resultados/04.csv}}

Radio/TV y auto usado son los propósitos más seguros (22,1 % y 16,5 %). Educación (44 %), "otros"
(41,7 %) y auto nuevo (38 %) son los más riesgosos. Auto nuevo es además el segundo en volumen: es
donde una política más estricta tendría más impacto.

### Q05. ¿Influye el plazo?

{{csv:resultados/05.csv}}

**La tasa de malos crece de forma monótona con el plazo**: 21,2 % hasta un año y 51,7 % a más de tres
años. A más meses, más tiempo para que algo salga mal.

### Q06. ¿Y el monto?

{{csv:resultados/06.csv}}

La relación tiene forma de U: los créditos más chicos (cuartil 1) y, sobre todo, los más grandes
(cuartil 4: 42 %) son los más riesgosos. Los montos medios son los más seguros. Monto y plazo van
juntos: los créditos grandes suelen ser los de plazo largo.

### Q07. ¿Y la edad?

{{csv:resultados/07.csv}}

Los menores de 25 años tienen la tasa más alta (42,1 %), y baja con la edad hasta los 50.

### Q08. ¿Y los ahorros?

{{csv:resultados/08.csv}}

A más ahorros, menos riesgo: 36 % con menos de 100 DM y 12,5 % con 1.000 DM o más. Los de "sin ahorros
/ desconocido" (17,5 %) se parecen a los de ahorros altos: probablemente guardan su dinero en otra
entidad.

### Q09. ¿Y la antigüedad en el empleo?

{{csv:resultados/09.csv}}

Menos de un año en el empleo es el peor grupo (40,7 %), peor incluso que los desempleados (37,1 %). A
partir de los 4 años, el riesgo baja a ~22–25 %.

### Q10. ¿Vivienda y propiedad?

{{csv:resultados/10.csv}}

Los extremos son claros: vivienda propia con un inmueble, 19,5 %; sin propiedad conocida, hasta 50 %.
(Se muestran los grupos con al menos 20 solicitudes.)

### Q11. Perfil numérico de buenos y malos pagadores

{{csv:resultados/11.csv}}

Los malos pagadores piden **5,7 meses más de plazo** y **953 DM más** en promedio, son algo más jóvenes
y comprometen una porción algo mayor de su ingreso en la cuota.

### Q12. ¿Hay un perfil de alto riesgo fácil de detectar?

{{csv:resultados/12.csv}}

Combinar las dos señales más fuertes (saldo menor a 200 DM y plazo mayor a 24 meses) aísla a 144
solicitantes con un **59,7 %** de malos pagadores, el doble del promedio.

### Q13. ¿Qué política de aprobación conviene con la matriz de costos?

{{csv:resultados/13.csv}}

**El umbral sale de la matriz.** Si un grupo tiene una tasa de malos *p*, aprobarlo cuesta en promedio
**5·p** por solicitante y rechazarlo, **1·(1 − p)**. Conviene aprobar sólo si 5p < 1 − p, o sea, si
**p < 1/6 ≈ 16,7 %**.

- Aprobar a todos es lo peor (costo 1.500): con 30 % de malos, 5 × 0,30 > 0,70.
- Rechazar a todos (700) ya es mejor que aprobar a todos.
- La política C (rechazar si la cuenta tiene menos de 200 DM) baja a 603.
- La política D sale directo del umbral: según Q02, el único segmento por debajo de 16,7 % es "sin
  cuenta corriente". **Aprobar sólo ese segmento da el costo más bajo: 582.**

## 4. Conclusiones

1. **El estado de la cuenta corriente es el mejor predictor individual**: la tasa de malos va de 49 %
   (saldo negativo) a 12 % (sin cuenta). Le siguen el **plazo**, con una relación monótona de 21 % a
   52 %, y los **ahorros**.
2. **Juventud, poca antigüedad laboral, montos grandes y no tener propiedad** también suben el riesgo.
   Combinados (Q12), aíslan grupos con el doble de mora que el promedio.
3. **El historial de crédito engaña**: quien ya tiene créditos en otros bancos aparece como *menos*
   riesgoso. Una variable así no se usa sin entender por qué se comporta al revés de lo esperado.
4. **La matriz de costos cambia la pregunta.** No alcanza con acertar más: como aprobar a un mal
   pagador cuesta 5 veces más, sólo conviene aprobar segmentos con menos de 16,7 % de malos. Con reglas
   de una sola variable, el costo baja de 1.500 (aprobar a todos) a 582. Un modelo de scoring
   (regresión logística, árboles) combinaría las variables y bajaría más. Habría que validarlo fuera de
   la muestra, porque estas reglas se eligieron mirando los mismos 1.000 casos.
5. **Sobre la arquitectura**: tabla externa + vista + CTAS a Parquet es un patrón barato. Los datos
   quedan en S3, el esquema en el catálogo y no hay ningún servidor prendido. Parquet escaneó 142 veces
   menos que el texto para la misma pregunta.

## 5. Cómo se reproduce

| Paso | Archivo |
|---|---|
| Probar el SQL gratis, en la laptop | `local/probar_duckdb.py` |
| Bucket, datos, tablas y consultas en Athena (CloudShell) | `infra/correr.sh` |
| DDL: tabla externa, vista y CTAS | `sql/01_tablas.sql` |
| Las 13 consultas | `sql/02_consultas.sql` |

## Anexo A — DDL

{{codigo:sql/01_tablas.sql}}

## Anexo B — Consultas

{{codigo:sql/02_consultas.sql}}
