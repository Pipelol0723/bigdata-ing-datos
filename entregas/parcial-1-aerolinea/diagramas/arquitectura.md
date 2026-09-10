# Diagramas de arquitectura

> Entregable de 5.7: *"diagrama de arquitectura actualizado que muestre ambas bases,
> el proceso ETL y su relación con el Glue Data Catalog"*.

---

## 1. Arquitectura general

> **Vista de diseño (06/09).** La arquitectura tal como quedó desplegada en AWS —con la EC2 de la
> aplicación, el ETL en Python y el job de Glue que puebla `raw/` y `processed/`— está en
> [`arquitectura-aws-desplegada.png`](arquitectura-aws-desplegada.png) y en la sección 5.7.
> Dos diferencias con este diagrama, declaradas como desviaciones en 5.7: el ETL OLTP → OLAP
> corre en la EC2 y no en Glue, y las dos bases quedan en el catálogo **a través de sus copias
> en S3** (3 crawlers, uno por zona), no con crawlers JDBC directos sobre las bases.

```mermaid
flowchart TB
    subgraph clientes["Clientes"]
        pas["👤 Pasajero<br/><i>SPA · DEC-09</i>"]
        age["🏢 Agente de agencia<br/><i>portal propio · DEC-11</i>"]
        adm["⚙️ Administrador<br/><i>backoffice</i>"]
    end

    subgraph backend["Backend — monolito modular (DEC-05)"]
        apub["API pública"]
        ab2b["API B2B<br/><i>DEC-04</i>"]
        subgraph mods["Módulos"]
            mbus["busqueda"]
            minv["inventario<br/><b>DEC-03</b>"]
            mres["reservas"]
            mpag["pagos"]
        end
    end

    subgraph aws["AWS — us-east-1, VPC por defecto"]
        oltp[("RDS PostgreSQL<br/><b>OLTP</b> · 3NF<br/>db.t3.micro")]
        olap[("RDS PostgreSQL<br/><b>OLAP</b> · estrella<br/>db.t3.micro")]
        glue["AWS Glue ETL<br/>Spark · 2×G.1X<br/><i>diario</i>"]
        cat[["Glue Data Catalog"]]
        craw["Crawlers ×2<br/><i>on demand</i>"]
        s3ep(["VPC Endpoint S3<br/><i>Gateway · gratis</i>"])
    end

    pasa["💳 Pasarela de pagos<br/><i>externa · SUP-04</i>"]

    pas --> apub
    adm --> apub
    age --> ab2b
    apub --> mods
    ab2b --> mods
    mbus --> oltp
    minv --> oltp
    mres --> oltp
    mpag --> pasa
    pasa -.->|"webhook<br/>idempotente"| mpag

    oltp -->|"extrae + transforma"| glue
    glue -->|"carga"| olap
    glue -.-> s3ep

    craw -.->|"infiere esquema"| oltp
    craw -.->|"infiere esquema"| olap
    craw --> cat

    classDef db fill:#2d5a8c,stroke:#1a3a5c,color:#fff
    classDef svc fill:#c8792b,stroke:#8a5010,color:#fff
    classDef ext fill:#6b6b6b,stroke:#404040,color:#fff
    class oltp,olap db
    class glue,cat,craw,s3ep svc
    class pasa ext
```

**Lo que muestra este diagrama y hay que poder defender:**

- **Una sola base transaccional** para los dos canales: el inventario es único, así que un
  pasajero web y una agencia compiten por el mismo asiento sin coordinación adicional.
- **La analítica nunca toca el OLTP** (`DEC-08`). La flecha va del OLTP al ETL y del ETL al
  OLAP; no hay ninguna flecha de reportes hacia el OLTP.
- **La pasarela está fuera del recuadro de AWS**: el sistema no ve datos de tarjeta
  (`SUP-04`, `NFR-SEG-01`).
- **El VPC Endpoint es lo que evita el NAT Gateway** y su costo por hora.

---

## 2. Flujo de una reserva — dónde actúa cada decisión

```mermaid
sequenceDiagram
    autonumber
    participant C as Cliente
    participant A as API
    participant D as PostgreSQL OLTP
    participant P as Pasarela

    C->>A: POST /reservas
    A->>D: BEGIN
    Note over A,D: tramos ordenados por id_instancia<br/>(evita deadlock en multi-tramo)

    loop por cada tramo
        A->>D: UPDATE ... SET comprometidos+1<br/>WHERE comprometidos+1 <= vendible
        alt rowcount = 1
            D-->>A: comprometido
        else rowcount = 0
            D-->>A: sin capacidad
            A->>D: ROLLBACK
            A-->>C: 409 · rechazo explícito (NFR-CONC-01)
        end
    end

    A->>D: INSERT reserva 'retenida' + expira_en
    A->>D: INSERT itinerario, tramos, historial
    A->>D: COMMIT
    A-->>C: 201 · retenida 30 min (DEC-02)

    C->>P: paga fuera del sistema
    P-->>A: webhook (idempotente, DEC-06)
    A->>D: estado = 'confirmada'

    Note over A,D: si el hold ya venció:<br/>no confirma, dispara reembolso
```

---

## 3. Modelo dimensional del OLAP — constelación

```mermaid
erDiagram
    dim_fecha  ||--o{ fact_tramo_vendido : "fecha de vuelo"
    dim_fecha  ||--o{ fact_tramo_vendido : "fecha de reserva"
    dim_ruta   ||--o{ fact_tramo_vendido : ""
    dim_vuelo  ||--o{ fact_tramo_vendido : ""
    dim_tarifa ||--o{ fact_tramo_vendido : ""
    dim_canal  ||--o{ fact_tramo_vendido : ""
    dim_estado_reserva ||--o{ fact_tramo_vendido : ""

    dim_fecha ||--o{ fact_ocupacion_vuelo : ""
    dim_ruta  ||--o{ fact_ocupacion_vuelo : ""
    dim_vuelo ||--o{ fact_ocupacion_vuelo : ""
```

**Dos hechos, no uno.** Las preguntas de `FR-19` tienen granos distintos: ingresos y
cancelaciones se miden por **tramo vendido**; la ocupación, por **instancia de vuelo**. Un
único hecho a grano de tramo no conocería los vuelos que no vendieron nada — y ésos son
justamente los que hacen bajar el promedio de ocupación.

Las dimensiones compartidas (`dim_fecha`, `dim_ruta`, `dim_vuelo`) hacen que esto sea una
**constelación**, no dos estrellas independientes: se puede cruzar ocupación con ingresos
por la misma ruta y la misma fecha.

---

## 4. Modelo entidad-relación del OLTP

El diagrama Crow's Foot completo está en
[`../documento/03-modelo-er.md`](../documento/03-modelo-er.md#diagrama-entidad-relación),
junto al diccionario de datos de las 14 entidades.

---

> Los diagramas están en Mermaid: se renderizan solos en GitHub y viven en texto plano, así
> que versionan y se revisan con `git diff` como cualquier otro archivo del repo. Para
> exportarlos a imagen: [mermaid.live](https://mermaid.live).
