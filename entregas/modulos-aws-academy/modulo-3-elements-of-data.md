# Module 3 — The Elements of Data

**Actividad de Moodle:** *AWS Academy Data Engineering — Module 3: The Elements of Data*
**Semana 3** · cerró el 21 de agosto de 2026
**Caso de estudio:** sistema de reservas de una aerolínea (Parcial 1)

> ⚠️ El módulo se completa en la plataforma de **AWS Academy**; el entregable formal es la
> evidencia de haberlo terminado. Este documento es la **síntesis aplicada al proyecto**.
> **Estado del módulo:** ⬜ pendiente.

---

## 1. De qué trata el módulo

Los elementos que describen un dato antes de procesarlo: las **5 V**, los tipos (estructurado,
semiestructurado, no estructurado), los formatos de archivo y de dónde viene cada dato. Es la base
para elegir dónde guardarlo y cómo consultarlo.

## 2. Las 5 V, medidas sobre el sistema propio

| V | En el sistema de reservas |
|---|---|
| **Volumen** | 9.121 filas de hechos por 30 días de operación simulada |
| **Velocidad** | la relevante no es la de ingesta sino la de decisión: dos clientes pidiendo el último asiento obligan a resolver en milisegundos |
| **Variedad** | la misma reserva vive en cuatro representaciones y ninguna es "la verdadera" |
| **Veracidad** | el invariante de no-sobreventa **encontró un bug en el generador que lo alimentaba** |
| **Valor** | tres vistas de negocio, cada una atada a una decisión concreta |

**A este volumen el sistema no es Big Data, y decirlo es parte de la respuesta.** 9.121 filas caben
en la memoria de un teléfono. La pregunta útil no es *"¿tengo muchos datos?"* sino *"¿a partir de
qué punto mi arquitectura deja de servir?"*.

El cálculo, con supuestos declarados: si el negocio creciera ×100 en vuelos, serían ~10,6 millones
de filas al año y PostgreSQL aguantaría. **El salto lo produce cambiar qué se considera un dato:**
cuando además se guarde *"alguien buscó un vuelo y no compró"* —lo que hace falta para fijar
precios— el volumen se multiplica por cien otra vez y ninguna decisión previa sigue siendo válida.

## 3. Variedad: cuatro formas del mismo hecho

| Representación | Dónde vive | Naturaleza |
|---|---|---|
| Transaccional | PostgreSQL OLTP, 3NF, 17 tablas | estructurado, normalizado |
| Analítica | esquema estrella, 2 hechos a **grano distinto** | estructurado, desnormalizado |
| Eventos de pago | webhooks del proveedor | semiestructurado (JSON), llega **desordenado y repetido** |
| Logs de aplicación | archivos | no estructurado |

El tercero tuvo consecuencia de diseño: como el webhook llega desordenado y repetido, el endpoint
de pago **tuvo que ser idempotente**. Un elemento del dato —su forma de llegada— determinó una
propiedad del código.

## 4. Veracidad: el hallazgo que vale por el módulo entero

La restricción `CHECK (asientos_comprometidos_bus <= capacidad_vendible_bus)` **rechazó datos de mi
propio generador de demo**, que repartía 10 % de la demanda a business sin mirar que sólo hay 12
asientos.

El error no estaba en los datos: estaba en el programa que los producía.

> **La lección:** la calidad de datos no se audita al final con un informe. Se declara como
> restricción en el punto de escritura y falla ruidosamente. Es más barato y no depende de que
> alguien se acuerde de mirar.

## 5. Formatos, medidos

Las mismas 17 tablas, escritas por el job de Glue en las dos zonas del data lake:

| Zona | Formato | Bytes |
|---|---|---|
| `raw/oltp/` | CSV | **2.915.371** |
| `processed/oltp/` | Parquet + Snappy | **941.399** |

3,1 veces menos en disco. Pero lo que decide es el **costo de consulta** — la misma pregunta con
Athena contra cada zona:

| `SELECT estado, count(*) FROM reserva GROUP BY estado` | Bytes escaneados |
|---|---|
| CSV | **586.285** |
| Parquet | **2.335** |

**251 veces menos, misma respuesta.** Y `SELECT count(*)` sobre Parquet escanea **0 bytes**: el
conteo de filas está en el pie del archivo.

El detalle que lo cierra: el CSV escaneó **exactamente los mismos 586.285 bytes en las dos
consultas**. Da igual qué se le pregunte — siempre lee todo. A $5 por TB, el formato no es una
preferencia de almacenamiento: **es lo que decide si preguntar cuesta o no cuesta.**

Por eso `raw/` es CSV (fidelidad a la fuente, se lee casi nunca) y todo lo demás es Parquet.

## 6. Evidencia a adjuntar

Captura del módulo al 100 % con el resultado del quiz, como `modulo-3-evidencia.png`.

## 7. Qué generó la IA y qué corregí

| # | Qué propuso el asistente | Qué corregí | Por qué |
|---|---|---|---|
| 1 | Explicar las 5 V con ejemplos de redes sociales e IoT | Reemplazar por mediciones del sistema propio | Un ejemplo prestado no se puede defender ni verificar |
| 2 | Presentar el proyecto como caso de Big Data | Sostener que **no lo es** al volumen actual, y calcular el umbral | Es más defendible, y el resultado de aprendizaje pide explicar *cuándo hace falta* el enfoque — lo que obliga a saber cuándo no |
| 3 | Justificar Parquet citando "hasta 10× de compresión" | Medirlo: 3,1× en disco, **251× en escaneo** | La cifra de manual era además la menos importante: el ahorro está en la consulta, no en el disco |
