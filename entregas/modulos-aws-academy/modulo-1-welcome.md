# Module 1 — Welcome to AWS Academy Data Engineering

**Actividad de Moodle:** *AWS Academy Data Engineering — Module 1: Welcome to AWS Academy Data Engineering*
**Semana 1** · cerró el 7 de agosto de 2026
**Caso de estudio:** sistema de reservas de una aerolínea (Parcial 1)

> ⚠️ **Qué es este documento y qué no.** El módulo se completa en la plataforma de **AWS Academy**,
> no acá; el entregable formal es la evidencia de haberlo terminado. Este documento es la
> **síntesis de los conceptos del módulo aplicados al proyecto**, que es lo que después hay que
> poder defender. No reemplaza completar el módulo.
>
> **Estado del módulo en AWS Academy:** ⬜ pendiente.

---

## 1. De qué trata el módulo

Es la apertura del curso: qué hace un ingeniero de datos, dónde encaja dentro de una organización
y cómo se ve un pipeline de datos de punta a punta. Fija el vocabulario que se usa el resto del
programa —ingesta, almacenamiento, procesamiento, análisis, consumo— y presenta el entorno de
laboratorio sobre el que se trabaja.

## 2. El rol, visto desde el trabajo real de este semestre

La definición de manual dice que el ingeniero de datos "construye y mantiene pipelines". Después
de construir uno, la definición que me sirve más es otra: **el ingeniero de datos es el
responsable de que el dato siga siendo cierto después de moverlo.**

Lo aprendí midiendo. En el sistema de reservas, sin control de concurrencia, 30 peticiones
simultáneas sobre 1 asiento produjeron **4 reservas confirmadas** mientras el contador de asientos
comprometidos decía **"1"**. El dato era internamente coherente y falso respecto del mundo.
Ninguna consulta lo habría detectado.

Mover datos es la parte fácil. Que sigan significando lo mismo del otro lado es el trabajo.

## 3. Los tres roles, y qué falla cuando falta cada uno

| | Arquitecto de datos | Ingeniero de datos | Científico de datos |
|---|---|---|---|
| **Pregunta que contesta** | ¿qué construimos y por qué esto y no lo otro? | ¿cómo lo construyo para que aguante? | ¿qué dicen los datos que no sabíamos? |
| **Entregable** | diagramas, ADRs, restricciones | pipelines, esquemas, pruebas | modelos, hipótesis, experimentos |
| **Horizonte** | años | semanas | días |
| **Si falta** | se construye rápido lo que después no se puede cambiar | el modelo del científico nunca llega a producción | se procesan a la perfección datos que no responden nada |

**Este curso apunta al primero.** El propio syllabus lo dice: *"el cuello de botella del ingeniero
de datos ya no es escribir el ETL sino decidir qué arquitectura construir, justificarla y validar
que el código generado la implemente correctamente"*.

Se nota en los tiempos: escribir el ETL del proyecto llevó una tarde. Decidir el grano de las dos
tablas de hechos llevó bastante más, y es lo único de las dos cosas que no se puede rehacer barato.

## 4. El pipeline del proyecto, con el vocabulario del módulo

| Etapa | Qué hay en el proyecto | Medido |
|---|---|---|
| **Ingesta** | job de Glue que extrae 17 tablas del OLTP por JDBC | SUCCEEDED en 149 s |
| **Almacenamiento** | data lake en S3 con zonas `raw/`, `processed/`, `curated/` | 60 objetos, 3,8 MB |
| **Procesamiento** | ETL a esquema estrella, recarga completa | 141 dimensiones + 9.121 hechos en 1,64 s |
| **Catálogo** | Glue Data Catalog, tres databases | 42 tablas |
| **Consumo** | Athena sobre Parquet particionado | una consulta escaneó 2.335 bytes |

## 5. Evidencia a adjuntar

Captura de la plataforma de AWS Academy con el módulo al 100 % y el resultado del quiz, guardada
en esta carpeta como `modulo-1-evidencia.png`.

## 6. Qué generó la IA y qué corregí

| # | Qué propuso el asistente | Qué corregí | Por qué |
|---|---|---|---|
| 1 | Resumir el contenido del módulo | Escribir la **síntesis aplicada al proyecto**, y declarar que el módulo se completa en AWS Academy | No cursé el módulo todavía: resumir su contenido sería inventarlo. Lo que sí puedo sostener es la conexión con lo que construí |
| 2 | Definir al ingeniero de datos como "quien construye pipelines" | Reemplazar por *"quien responde por que el dato siga siendo cierto después de moverlo"* | La primera es correcta y no explica nada. La segunda salió de un resultado medido: 4 reservas sobre 1 asiento con el contador diciendo 1 |
