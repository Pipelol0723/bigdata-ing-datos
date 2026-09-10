# 5.6 Primera implementación del backend

> **Estado:** ✅ implementado y probado — 06/09
> **Peso en la rúbrica:** 10%
> **Entorno de desarrollo:** PostgreSQL 16 en Docker · FastAPI en venv local

## Alcance mínimo exigido

- [x] Base de datos funcional, con el motor y el nivel de normalización de 5.3 → **PostgreSQL 16, 3NF, 17 tablas**
- [x] API FastAPI con:
  - [x] Buscar vuelos disponibles → `GET /vuelos`
  - [x] Crear una reserva → `POST /reservas`
  - [x] Consultar una reserva existente → `GET /reservas/{codigo}`
- [x] La creación refleja la decisión de concurrencia de 5.4 (`DEC-03`), **verificada bajo carga concurrente real**

Endpoints adicionales, no exigidos pero necesarios para cerrar el ciclo:
`POST /reservas/{codigo}/pago` (webhook idempotente, `DEC-06`) y
`POST /operacion/expirar-holds` (barrido de `DEC-07`).

---

## 🔬 La prueba de concurrencia

**Plan: mostrar primero el bug, después la cura.** Reproducir la falla vale más que sólo
demostrar que funciona — prueba que el mecanismo es necesario, no decorativo.

### Montaje

El escenario es el textual del enunciado: *"dos pasajeros intentan reservar el último asiento
al mismo tiempo"*, amplificado a **30 solicitudes simultáneas sobre 1 asiento**.

Tres detalles del montaje sin los cuales la prueba no probaría nada:

1. **Pool de conexiones, no una conexión compartida.** Con una sola conexión las peticiones se
   serializan en el cliente y la carrera nunca ocurre: el cuello de botella sería el driver,
   no el inventario.
2. **Barrera de sincronización.** Los 30 hilos se bloquean y salen *todos a la vez*. Sin eso
   las peticiones se escalonan y el conflicto no se manifiesta.
3. **Para la corrida A se retira temporalmente el `CHECK` de la tabla.** Si no, la restricción
   declarativa atajaría la sobreventa y no se vería la diferencia entre los dos mecanismos.
   Se restaura inmediatamente después.

### Resultados

| Corrida | Mecanismo | 201 | 409 | Comprometidos | Reservas vivas | Veredicto |
|---|---|---|---|---|---|---|
| **A** | Sin control (`MODO_INSEGURO=1`) | **4** | 26 | 1 | **4** | ❌ **SOBREVENTA** |
| **B** | Bloqueo optimista (`DEC-03`) | **1** | 29 | 1 | 1 | ✅ **CORRECTO** |

Evidencia cruda en `evidencia/concurrencia/resultado-sin-lock.json` y `resultado-con-lock.json`.

### Lo que muestra la corrida A, y es más grave que "vender de más"

**Cuatro pasajeros con reserva viva sobre un vuelo de un asiento** — pero el contador dice
`asientos_comprometidos = 1`.

Los cuatro hilos leyeron `comprometidos = 0`, los cuatro concluyeron que había lugar, y los
cuatro escribieron `1`. Tres escrituras se perdieron. Es el *lost update* clásico.

Y lo peor no es el número: **es que el sistema no sabe que está mal**. El inventario informa
un asiento vendido mientras hay cuatro personas con derecho a volar. Ningún reporte, ninguna
alarma y ningún reintento lo detectarían: la base es internamente consistente y está
completamente equivocada.

### Por qué la corrida B da exactamente 1

```sql
UPDATE reservas.instancia_vuelo
   SET asientos_comprometidos_eco = asientos_comprometidos_eco + 1,
       version = version + 1
 WHERE id_instancia = %s
   AND asientos_comprometidos_eco + 1 <= capacidad_vendible_eco;
```

La comprobación de capacidad viaja **dentro** de la sentencia. El motor la evalúa con la fila
bloqueada durante la escritura, así que no existe ventana entre comprobar y escribir. La
segunda transacción ve el valor ya actualizado por la primera.

`rowcount == 1` → comprometido. `rowcount == 0` → **rechazo explícito con `409`**, que es lo
que `NFR-CONC-01` exige: las perdedoras reciben un mensaje accionable, no un error genérico.

---

## Preguntas guía — respondidas

### ¿El código refleja lo documentado en 5.4, o hubo ajustes?

**Tres ajustes**, ninguno de los cuales contradice el diseño; los tres lo precisan.

| Ajuste | Por qué apareció | Documento actualizado |
|---|---|---|
| **Pool de conexiones en vez de conexión única** | La primera versión compartía una conexión. Habría hecho pasar la prueba de concurrencia **por el motivo equivocado**: sin paralelismo real no hay carrera que ganar | 5.4 — se explicita que el pool es parte del mecanismo, no un detalle de infraestructura |
| **`id_canal = 0` para la venta directa** en el OLAP | `id_agencia` es `NULL` en el OLTP, correcto en 3NF. Pero un `NULL` en la clave foránea de un hecho obliga a `LEFT JOIN` en todos los reportes | 5.7 — es una transformación del ETL, no un cambio del OLTP |
| **Expiración de holds en dos capas** | Un barrido periódico deja una ventana donde un hold vencido sigue contando como ocupado. Se agregó filtrado perezoso en la búsqueda | 5.4 — quedó como `DEC-07` |

### ¿Cómo se probó `NFR-CONC-01` y qué evidencia lo respalda?

Script `api/prueba_concurrencia.py`, ejecutable y repetible:

```bash
python prueba_concurrencia.py --peticiones 30 --etiqueta con-lock
```

El script no confía en los códigos HTTP: **después de la carga vuelve a la base** y compara
tres números que deben coincidir — respuestas `201`, `asientos_comprometidos` y reservas
vivas. La corrida A falla exactamente en esa comparación (4 ≠ 1), que es cómo se detecta una
inconsistencia que los códigos HTTP por sí solos no revelarían.

### ¿Qué hubo que ajustar del modelo de 5.3?

**Nada estructural.** Las 17 tablas se crearon sin cambios. Dos precisiones menores aparecieron:

- **`CHECK` de sobreventa por clase, no global.** El generador de datos de prueba asignaba un
  10 % a business sin mirar que sólo hay 12 asientos de esa clase, y la restricción lo atajó.
  **El invariante encontró un bug real en el código que lo alimentaba** — que es justamente
  para lo que sirve tenerlo declarado en la tabla.
- **Colisión de PNR.** Seis caracteres dan 16,7 millones de combinaciones, pero con miles de
  reservas la paradoja del cumpleaños vuelve probable el choque. Se resolvió con reintento
  hasta encontrar uno libre, que es lo que hacen los sistemas de reservas reales.

---

## Guía de ejecución

**Requisitos:** Docker y Python 3.11+.

```bash
# 1. Levantar las dos bases (OLTP en 15432, OLAP en 15433)
cd entregas/parcial-1-aerolinea
docker compose up -d

# 2. Cargar esquema, catálogo y actividad de demostración
docker exec -i parcial-oltp psql -U parcial -d aerolinea < db/oltp/01-esquema.sql
docker exec -i parcial-oltp psql -U parcial -d aerolinea < db/oltp/02-datos-demo.sql
docker exec -i parcial-oltp psql -U parcial -d aerolinea < db/oltp/03-actividad-demo.sql

# 3. Instalar dependencias y levantar la API
pip install -r api/requirements.txt
cd api && uvicorn main:app --port 8010
```

Documentación interactiva en `http://127.0.0.1:8010/docs`.

**Prueba de concurrencia (corrida B, con el mecanismo):**

```bash
python api/prueba_concurrencia.py --peticiones 30 --etiqueta con-lock
```

**Corrida A (sin el mecanismo)** — reproduce la sobreventa:

```bash
docker exec -i parcial-oltp psql -U parcial -d aerolinea \
  -c "ALTER TABLE reservas.instancia_vuelo DROP CONSTRAINT no_sobreventa_eco;"
MODO_INSEGURO=1 uvicorn main:app --port 8010     # en otra terminal
python api/prueba_concurrencia.py --peticiones 30 --etiqueta sin-lock
```

**Restaurar — el orden importa.** La corrida A deja la instancia con 4 comprometidos sobre 1
vendible, así que agregar el `CHECK` directamente **falla**: PostgreSQL valida las filas
existentes y encuentra la violación. Primero hay que dejar la instancia en un estado válido, y la
propia corrida B lo hace (`preparar_instancia` la resetea antes de disparar):

```bash
uvicorn main:app --port 8010                     # reiniciar la API SIN MODO_INSEGURO
python api/prueba_concurrencia.py --peticiones 30 --etiqueta con-lock   # resetea y deja 1 de 1
docker exec -i parcial-oltp psql -U parcial -d aerolinea \
  -c "ALTER TABLE reservas.instancia_vuelo ADD CONSTRAINT no_sobreventa_eco
      CHECK (asientos_comprometidos_eco <= capacidad_vendible_eco);"
```

> Corregido el 10/09: la versión anterior restauraba el `CHECK` inmediatamente después de la
> corrida A, lo que habría fallado. Detectado al releer el código para la guía de AWS.

---

## Nota sobre las dos capas de protección

El invariante está protegido **dos veces**, y es deliberado:

| Capa | Qué hace | Cuándo actúa |
|---|---|---|
| `UPDATE` condicional (`DEC-03`) | **Previene**: la venta de más nunca ocurre | En cada reserva |
| `CHECK` de la tabla | **Garantiza**: aunque el código tenga un bug, la fila no entra | Siempre |

Si en la defensa preguntan *"¿y si el código falla?"*, la respuesta está en la tabla. Y la
corrida A lo demuestra al revés: hubo que **retirar** el `CHECK` para poder reproducir la
falla. La red de seguridad funcionaba incluso con el mecanismo aplicativo roto.

## Defensa: qué se rompe si esto cambia (§7)

| Si cambia… | Qué se toca | Costo | Alternativa ya considerada |
|---|---|---|---|
| **Overbooking del 5 %** | Nada del código. El `UPDATE` compara contra `capacidad_vendible`, que sale de `POLITICA_CAPACIDAD` | **Nulo** | Comparar contra capacidad física (`FR-17`) |
| **Los reintentos se disparan en un vuelo muy disputado** | Ese vuelo pasa a cola serializada; el resto sigue optimista. La frontera del módulo `inventario` permite las dos estrategias a la vez | Medio, acotado | La cola quedó documentada en 5.4, no descartada |
| **Reserva multi-tramo con tramos en instancias distintas** | **Ya funciona**: el bucle recorre los tramos ordenados por `id_instancia` dentro de una sola transacción. Todo o nada | **Nulo** | Es la ventaja de `DEC-05` (monolito): una transacción local, no una saga |
| **La API debe soportar 10× el tráfico** | El pool sube de tamaño y se agregan réplicas de lectura para `GET /vuelos`. La escritura no es el cuello (`NFR-ESC-01`) | Medio | Ver análisis de cuello de botella en 5.2 |
| **Hay que cambiar de PostgreSQL a otro motor** | El `UPDATE` condicional es SQL estándar y funciona en cualquier motor con transacciones. Lo específico es `psycopg`, aislado en `repositorio.py` | Bajo | — |
