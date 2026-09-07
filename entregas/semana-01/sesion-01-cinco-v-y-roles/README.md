# Session 1 — Introducción al Big Data: las 5 V, casos de uso y roles

**Curso:** Big Data e Ingeniería de Datos (PCIA 5010) · Semana 1 · Sesión 1
**Resultados de aprendizaje que cubre:** *"Explicar en qué consiste las 5 V en el contexto de
Big Data"* y *"Explicar casos donde es necesario utilizar un enfoque de Big Data"*

---

## Caso de estudio

Todos los entregables de este curso usan **el mismo caso**: el sistema de reservas de una
aerolínea construido para el Parcial 1 (`entregas/parcial-1-aerolinea/`). Es un sistema real y
medido —17 tablas OLTP, una API con control de concurrencia, un ETL a esquema estrella y tres
vistas de negocio— así que las cifras de este documento **no son ejemplos: son mediciones**.

La alternativa era ilustrar cada concepto con un caso distinto tomado de la literatura. Se
descartó porque un ejemplo prestado no se puede defender ni auditar; uno propio, sí.

---

## 1. Las 5 V, medidas sobre el sistema

### Volumen — *cuánto*

| Métrica | Valor medido |
|---|---|
| Vuelos programados | 9 |
| Instancias de vuelo generadas (30 días) | 227 |
| Reservas simuladas | ~8.800 |
| Filas de hechos cargadas al modelo analítico | **8.821** |
| Filas de dimensiones | 141 |

**Este sistema no es Big Data, y decirlo es parte de la respuesta.** 8.821 filas caben en la
memoria de un teléfono. La pregunta útil no es *"¿tengo muchos datos?"* sino *"¿a partir de
qué punto mi arquitectura deja de servir?"* — se responde en la §2.

### Velocidad — *qué tan rápido llega y con cuánta urgencia hay que decidir*

La velocidad relevante acá **no es la de ingesta, es la de la decisión**. Dos clientes que
piden el último asiento del mismo vuelo en el mismo instante obligan a decidir en milisegundos,
y una respuesta tardía no es lenta: es incorrecta.

Medición (30 peticiones simultáneas sobre 1 asiento, `evidencia/concurrencia/`):

| Escenario | Resultado |
|---|---|
| Sin control de concurrencia | **4 reservas confirmadas sobre 1 asiento** |
| Con bloqueo optimista | **1 confirmada, 29 rechazos `409` explícitos** |

### Variedad — *qué formas tienen los datos*

| Tipo | Dónde vive | Naturaleza |
|---|---|---|
| Transaccional | PostgreSQL OLTP, 3NF | estructurado, normalizado |
| Analítico | esquema estrella, 2 tablas de hechos a **grano distinto** | estructurado, desnormalizado |
| Eventos de pago | webhooks del proveedor | semiestructurado (JSON), llega desordenado y repetido |
| Logs de aplicación | archivos | no estructurado |

El punto no es la lista: es que **la misma reserva vive en cuatro representaciones distintas y
ninguna es "la verdadera"**. El modelo analítico tiene dos tablas de hechos porque hay dos
granos legítimos —el tramo vendido y la ocupación del vuelo— y forzarlos a uno solo destruye
información.

### Veracidad — *si los datos dicen la verdad*

Es la V que este proyecto puede demostrar con evidencia dura, y con dos hallazgos:

**(a) Datos internamente consistentes y aun así falsos.** Sin bloqueo optimista, el sistema
confirmó 4 reservas sobre 1 asiento **mientras el contador de asientos comprometidos decía
"1"**. Ninguna consulta habría detectado el problema: el dato era coherente consigo mismo y
falso respecto del mundo. Un tablero construido sobre esa tabla habría mostrado ocupación
correcta y vendido cuatro veces el mismo asiento.

**(b) El invariante encontró un bug en el código que lo alimentaba.** La restricción
`CHECK (asientos_comprometidos_bus <= capacidad_vendible_bus)` rechazó datos de mi **propio
generador de demo**, que repartía 10 % de la demanda a clase business sin mirar que sólo hay 12
asientos. El error no estaba en los datos: estaba en el programa que los producía.

> **La lección:** la calidad de datos no se audita al final con un informe. Se declara como
> restricción en el punto de escritura y falla ruidosamente. Es más barato y no depende de que
> alguien se acuerde de mirar.

### Valor — *si sirve para decidir algo*

Una V que sólo se puede evaluar al final. Las tres preguntas de negocio que el modelo responde:

| Vista | Qué decisión habilita |
|---|---|
| `v_ocupacion_por_ruta` | qué rutas justifican más frecuencias y cuáles sobran |
| `v_ingresos_por_tarifa` | si la estructura tarifaria está capturando la disposición a pagar |
| `v_patrones_cancelacion` | cuánta sobreventa tolera cada ruta sin dejar pasajeros en tierra |

Las tres se responden con las mismas 8.821 filas. **Volumen y valor son independientes**: se
puede tener muchísimo de lo primero y nada de lo segundo.

---

## 2. ¿Cuándo hace falta de verdad un enfoque de Big Data?

La forma honesta de responderlo es calcular **dónde se rompe la arquitectura actual**, no citar
casos ajenos.

> ⚠️ **Supuestos declarados.** Los factores de crecimiento son estimaciones mías para razonar
> sobre órdenes de magnitud, no datos de una aerolínea real.

| Escenario | Cálculo | Filas de hechos / año | ¿Aguanta PostgreSQL? |
|---|---|---|---|
| Sistema actual | 8.821 filas / 30 días | ~107 mil | ✅ de sobra |
| Aerolínea mediana (×100 vuelos) | 8.821 × 100 × 12 | ~10,6 millones | ✅ con índices y particionado |
| + eventos de búsqueda (≈100 búsquedas por reserva) | ~10,6 M × 100 | **~1.060 millones** | ❌ **acá se rompe** |

**El salto no lo produce el negocio: lo produce cambiar qué se considera un dato.** Mientras el
dato es *"se vendió un asiento"*, una base relacional alcanza durante años. Cuando el dato pasa
a ser *"alguien buscó un vuelo y no compró"* —que es justamente lo que hace falta para fijar
precios— el volumen se multiplica por cien y ninguna de las tres decisiones anteriores sigue
siendo válida.

Y ahí las 5 V dejan de ser una definición y pasan a ser criterios de diseño:

| Si domina… | Lo que exige |
|---|---|
| **Volumen** | almacenamiento separado del cómputo, formato columnar, particionado (S3 + Parquet + Athena) |
| **Velocidad** | procesamiento en streaming, no lotes nocturnos (Kinesis) |
| **Variedad** | esquema al leer en vez de al escribir (data lake + catálogo, no un DW rígido) |
| **Veracidad** | validación en la ingesta y linaje, porque a esa escala nadie revisa a mano |
| **Valor** | recortar: a mil millones de filas, guardar lo que no se va a consultar es sólo costo |

**Un enfoque de Big Data se justifica cuando al menos una V rompe la arquitectura simple — no
cuando los datos "son muchos".** Para este sistema, hoy, la respuesta correcta es PostgreSQL.

---

## 3. Ingeniero, científico y arquitecto de datos

Los tres roles se distinguen mejor por **qué pregunta contestan** y **qué falla cuando el rol
falta**:

| | Arquitecto de datos | Ingeniero de datos | Científico de datos |
|---|---|---|---|
| **Pregunta** | ¿qué construimos y por qué esto y no lo otro? | ¿cómo lo construyo para que aguante? | ¿qué dicen los datos que no sabíamos? |
| **Entregable** | diagramas, ADRs, restricciones | pipelines, esquemas, pruebas | modelos, hipótesis, experimentos |
| **Horizonte** | años | semanas | días |
| **Si falta** | se construye rápido lo que después no se puede cambiar | el modelo del científico nunca llega a producción | se procesan a la perfección datos que no responden nada |

### Dónde estuvo cada rol en este proyecto

| Rol | Qué hice concretamente |
|---|---|
| **Arquitecto** | elegir bloqueo optimista sobre pesimista; separar OLTP de OLAP; modelar la sobreventa como **política parametrizable** en vez de invariante rígido, para que una regla comercial nueva entre como configuración |
| **Ingeniero** | el esquema de 17 tablas, la API con pool de conexiones, el ETL a estrella, la prueba de concurrencia y las restricciones que atajaron el bug del generador |
| **Científico** | las tres vistas de negocio: formular qué valía la pena preguntarle a los datos |

**El curso apunta al primero.** El propio syllabus lo dice: *"el cuello de botella del ingeniero
de datos ya no es escribir el ETL sino decidir qué arquitectura construir, justificarla y
validar que el código generado la implemente correctamente"*. Escribir el ETL me llevó una
tarde; decidir el grano de las tablas de hechos, bastante más.

---

## 4. Decisiones de este entregable

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| Usar el sistema del Parcial 1 como caso único | un caso de la literatura por cada concepto | un ejemplo prestado no se puede defender ni medir; éste tiene cifras verificadas |
| Argumentar que el sistema **no** es Big Data | presentarlo como si lo fuera | el resultado de aprendizaje pide explicar *cuándo hace falta* el enfoque; eso obliga a saber cuándo **no** |
| Cuantificar el umbral de ruptura | describir las 5 V en abstracto | un umbral se puede discutir y refutar; una definición sólo se puede repetir |

---

## 5. Qué generó la IA y qué corregí

> El syllabus condiciona el uso de IA a *"que el estudiante pueda explicar, depurar y modificar
> manualmente cualquier línea de código generado"*. Este bloque va en todos mis entregables.

| # | Qué propuso el asistente | Qué corregí | Por qué |
|---|---|---|---|
| 1 | Un ensayo genérico sobre las 5 V con ejemplos de redes sociales e IoT | Reemplazar por mediciones del sistema propio | Los ejemplos ajenos no se pueden defender en una sustentación |
| 2 | Presentar el proyecto como caso de Big Data | Sostener explícitamente que **no lo es** al volumen actual | Es más defendible y responde mejor al resultado de aprendizaje |
| 3 | Cifras de tráfico de aerolíneas reales | Sustituir por **factores de crecimiento declarados como supuestos** | No tengo fuente para esas cifras; un supuesto declarado es una decisión, uno oculto es un error |

**Fuente de los datos citados:** todas las cifras salen de la ejecución del Parcial 1 —
`evidencia/concurrencia/`, `evidencia/olap/` y la salida del ETL— y son reproducibles con la
guía de `documento/06-implementacion-backend.md`.
