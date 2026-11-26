# Big Data e Ingeniería de Datos (CC-IA-02) — Andres Felipe Cespedes Rondon

Repositorio con **todo el trabajo práctico del semestre** (agosto–noviembre de 2026), organizado por
actividad. Cada carpeta de `entregas/` tiene su documento, su código, sus scripts de AWS y la
evidencia de lo que se ejecutó. El historial de git registra la fecha de cada trabajo.

- **Índice completo de actividades, con fechas:** la tabla de abajo.
- **Detalle de cada entrega:** [`entregas/README.md`](entregas/README.md) y el `PLAN.md` de cada carpeta.
- **Contexto y bitácora del curso** (decisiones, costos y lecciones de cada sesión de AWS): [`CLAUDE.md`](CLAUDE.md).

Todo corrió en el **AWS Academy Learner Lab** (presupuesto de US$50). Se usaron US$21,4 en el semestre.

---

## Tercer corte (semanas 10–14)

| Semana | Actividad | Cierre en Moodle | Estado en Moodle | Evidencia y fecha | Dónde está |
|---|---|---|---|---|---|
| 10 | Module 10: Processing Data for ML | 24/10 | No entregado | **Knowledge check 100/100** en AWS Academy, el **17/10** (antes del cierre) | Canvas, curso 180877 |
| 11 | Module 11: Analyzing and Visualizing Data | 30/10 | No entregado | **Knowledge check 100/100** en AWS Academy, el **17/10** (antes del cierre) | Canvas, curso 180877 |
| 11 | AWS Kinesis workshop | 03/11 | Enviado (03/11) | 5 streams, Firehose y 2 Lambdas en AWS; CSV y logs de cada corrida (03/11) | [`entregas/semana-11-kinesis/`](entregas/semana-11-kinesis/) |
| 11 | AWS Kinesis: ejercicios adicionales | 05/11 | Enviado (03/11) | Informe con resultados medidos (03/11) | [`entregas/semana-11-kinesis/`](entregas/semana-11-kinesis/) |
| 12 | Module 12: Automating the Pipeline | 06/11 | Enviado | Knowledge check 100/100 (17/10) + evidencia | [`entregas/modulos-aws-academy/`](entregas/modulos-aws-academy/) |
| 13 | Module 13: Bridging to Certification | 13/11 | Enviado | Documento + evidencia | [`entregas/modulos-aws-academy/`](entregas/modulos-aws-academy/) |
| 13 | **Parcial 3** (eventos a Kinesis, vista en vivo y modelo estrella con SCD 2) | 26/11 | Enviado (24/11) | **Harness 70,0/70,0 en AWS** el 24/11 y otra vez el 26/11; documento de 21 páginas | [`entregas/parcial-3-eventos-estrella/`](entregas/parcial-3-eventos-estrella/) |
| 14 | **Capstone Project** (AWS Academy Data Engineering) | 28/11 | Enviado (25/11) | **25/25** en el corrector de AWS Academy (25/11) | [`entregas/capstone-aws-academy/`](entregas/capstone-aws-academy/) |
| 14 | **Course assessment** (AWS Academy) | — | — | **100/100** (25/11) | Canvas, curso 180877 |
| 10–14 | Sessions 19 a 28 y Checkpoints de las semanas 11 y 14 | 19/10 a 19/11 | No entregado | Moodle no tiene enunciado; el trabajo de esas semanas está en las filas de arriba | — |

## Segundo corte (semanas 6–9)

| Semana | Actividad | Cierre en Moodle | Estado en Moodle | Evidencia y fecha | Dónde está |
|---|---|---|---|---|---|
| 6 | AWS Athena: German Credit | — | Enviado (03/11) | Consultas e informe (03/11) | [`entregas/athena-german-credit/`](entregas/athena-german-credit/) |
| 7 | AWS Athena partitioned data exercise | 25/09 | No entregado | Moodle no tiene enunciado; el particionado con Athena está aplicado y medido en el Parcial 1 (08/09) y el Parcial 2 (18/10) | [`entregas/parcial-1-aerolinea/`](entregas/parcial-1-aerolinea/) |
| 7–9 | Modules 7 y 9 (Glue; EMR y Hudi) | — | — | Knowledge checks 100/100 (09/10) | Canvas, curso 180877 |
| 8 | Module 8: Storing and Organizing Data | 02/10 | No entregado | **Knowledge check 100/100** el **01/10** (antes del cierre) | Canvas, curso 180877 |
| 8 | Taller Taxis NYC (EMR + PySpark, 102 M de viajes) | 08/10 | Enviado (13/10) | Notebook ejecutado en EMR + PDF de respuestas (10/10 y 13/10) | [`entregas/semana-08/taller-taxis-nyc-emr/`](entregas/semana-08/taller-taxis-nyc-emr/) |
| 9 | **Parcial 2** (panel analítico: EMR + Glue + Athena + frontend) | 20/10 | No entregado en Moodle | **Harness 70,0/70,0 en AWS** el 18/10 y el 22/10; documento de 18 páginas; presentado en clase el 22/10 | [`entregas/parcial-2-panel-analitico/`](entregas/parcial-2-panel-analitico/) |

## Primer corte (semanas 1–5)

| Semana | Actividad | Cierre en Moodle | Estado en Moodle | Evidencia y fecha | Dónde está |
|---|---|---|---|---|---|
| — | EC2 + Apache + FastAPI (práctica en clase) | — | — | Desplegado en AWS (06/08) | [`entregas/ec2-apache/`](entregas/ec2-apache/) |
| 1 | Session 1: las cinco V y los roles | 03/08 | No entregado | Documento (07/09) | [`entregas/semana-01/`](entregas/semana-01/) |
| 1 | Session 2 | 06/08 | Enviado (06/08) | — | — |
| 1–4 | Modules 1 a 4 (AWS Academy) | 07/08 a 28/08 | No entregado | Un documento por módulo, aplicado al proyecto (07/09) | [`entregas/modulos-aws-academy/`](entregas/modulos-aws-academy/) |
| 2 | Sessions 3 y 4: diagramación, ADR, setup y alternativas | 10/08 y 13/08 | No entregado | Documentos y diagramas (07/09–08/09) | [`entregas/semana-02/`](entregas/semana-02/) |
| 3 | Session 5 (ADR #1: particionado) y Session 6 (clases de S3, versionado y lifecycle) | 17/08 y 20/08 | No entregado | Documentos; la política de lifecycle está aplicada en AWS (07/09–08/09) | [`entregas/semana-03/`](entregas/semana-03/) |
| 4 | Session 7 (Glue Catalog y crawlers) y Checkpoint 1 (data lake) | 24/08 y 27/08 | No entregado | Ejecutado en AWS con evidencia (07/09–08/09) | [`entregas/semana-04/`](entregas/semana-04/) |
| 5 | **Parcial 1** (sistema de reservas: OLTP, OLAP y data lake en AWS) | — | Enviado | Documento de 52 páginas; desplegado y verificado en AWS (08/09 y 10/09) | [`entregas/parcial-1-aerolinea/`](entregas/parcial-1-aerolinea/) |

> Las fechas de la columna "Evidencia y fecha" salen del historial de git y de AWS Academy.
> Las de cierre y el estado son los de Moodle al 25/11/2026.
