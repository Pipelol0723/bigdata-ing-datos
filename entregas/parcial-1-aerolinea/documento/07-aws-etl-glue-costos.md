# 5.7 Implementación en AWS: ETL, catálogo de datos y costos

> **Estado:** ⬜ pendiente — AWS día 1 domingo 6/09 · día 2 lunes 7/09 · costos martes 8/09
> **Peso en la rúbrica:** 20% — **la sección que más pesa**

## Decisión de infraestructura tomada

**Dos instancias RDS PostgreSQL nuevas, sin reutilizar ningún recurso de prácticas
anteriores.** Todo se crea desde cero para este parcial.

| Recurso | Rol | Estado |
|---|---|---|
| RDS PostgreSQL (OLTP) | Base transaccional del modelo de 5.3 | ⬜ por crear |
| RDS PostgreSQL (OLAP) | Base analítica, recibe copia vía ETL | ⬜ por crear |
| Conexiones JDBC de Glue | Una por base | ⬜ |
| Crawlers | Registran ambas bases en el Data Catalog | ⬜ |
| Job de ETL | Mueve y transforma OLTP → OLAP | ⬜ |

## Requisitos de implementación

- [ ] La base transaccional que soporta el modelo ER de 5.3
- [ ] Una segunda base PostgreSQL analítica (OLAP) que recibe al menos una tabla o vista
      derivada vía un proceso ETL
- [ ] **Ambas** registradas en el AWS Glue Data Catalog, visibles y consultables como
      metadatos desde Glue

## Preguntas guía a resolver

- [ ] ¿Qué tabla o combinación de tablas tiene sentido copiar para responder las preguntas
      de negocio del escenario (ocupación por ruta, ingresos por tarifa, patrones de
      cancelación)? ¿Se copia tal cual, o se transforma/agrega en el camino?
- [ ] ¿El esquema analítico debe ser idéntico al transaccional, o corresponde un modelo
      distinto? ¿Cómo se relaciona con la discusión de normalización de 5.3?
- [ ] ¿Qué servicio de AWS implementa el ETL? ¿Qué opciones hay en el Learner Lab y por qué
      una sobre otra?
- [ ] ¿Cómo se conectan ambas bases al Data Catalog (conexión JDBC, crawler, rol IAM,
      acceso de red)?
- [ ] ¿El ETL corre una sola vez, periódicamente, o disparado por eventos? ¿Qué implica cada
      opción en frescura de datos versus costo?

## Tabla de justificación de servicios

Cada servicio debe conectarse a (1) un FR/NFR específico y (2) uno o más de los seis
pilares del AWS Well-Architected Framework.

| Servicio AWS | Alternativa considerada | Requisito que lo sustenta | Pilar(es) Well-Architected |
|---|---|---|---|

Pilares: Excelencia Operativa · Seguridad · Fiabilidad · Eficiencia del Rendimiento ·
Optimización de Costos · Sostenibilidad.

## Proyección de costos

| Concepto | Supuesto (clase/tamaño/frecuencia) | Costo mensual estimado |
|---|---|---|
| Instancia RDS transaccional | | |
| Instancia RDS analítica | | |
| Proceso ETL | | |
| Crawlers y catálogo Glue | | |
| **Total** | | |

### Escenario de crecimiento ×10

Cómo cambia el costo si el volumen de datos o la frecuencia de actualización se multiplican
por 10, conectado explícitamente con los pilares de **Optimización de Costos** y
**Sostenibilidad**.

| Concepto | Costo actual | Costo ×10 | ¿Escala lineal? |
|---|---|---|---|

## Trampas conocidas del entorno

Documentadas de prácticas anteriores del curso (ver `CLAUDE.md`), aplican igual acá:

1. La URL JDBC va con **dos puntos**: `jdbc:postgresql://…`, y **con el puerto** `:5432`.
2. El Security Group de Glue necesita una **regla auto-referenciada** (todo el tráfico con
   origen el propio grupo). Sin eso la conexión falla sin explicar por qué.
3. **Sin VPC Endpoint de S3 el crawler da timeout**: los workers corren dentro de la VPC sin
   IP pública. El endpoint tipo Gateway es **gratis**; el NAT Gateway resuelve lo mismo a
   $0.045/h — no usarlo.
4. `Service is unable to assume provided role` = se eligió un rol que no es **LabRole**.
5. El crawler cobra por ejecución (~$0.10–0.15). Dejarlo **On demand**, nunca con schedule.

## Baja de recursos

⚠️ Las dos instancias RDS suman ~$4.60/mes de storage **aunque estén detenidas**, y AWS las
reinicia solas a los 7 días de detenidas. Después de la defensa se borran: el esquema, los
datos semilla y el script de bootstrap quedan en el repo y recrear todo son 5 minutos.

Script de baja: `../infra/`

## Defensa: qué se rompe si esto cambia (§7)

El día de la sustentación el profesor plantea un cambio, mejora o problema no cubierto en el
documento, y hay que responder **en el momento** qué parte del diseño se ve afectada. Esta
tabla es la respuesta preparada para esta sección.

| Si cambia… | Qué decisiones o entidades se tocan | Costo del cambio | Alternativa ya considerada |
|---|---|---|---|

> Sobre la restricción específica de equipo (§3), pendiente de confirmar: ver el README.
