# Anexo — Registro de prompts (§4)

> **Estado:** 🟡 en curso — se completa a medida que se avanza, no al final.

## Por qué este anexo existe

El enunciado permite el uso de asistentes de IA con una condición explícita:

> *"el documento final debe incluir, como anexo, un breve registro de los principales
> prompts utilizados durante el ejercicio y cómo fueron refinados o corregidos por el equipo"*

Lo que se evalúa no es el prompt perfecto, sino **la iteración**: qué se pidió, qué devolvió
la herramienta, y qué hubo que corregirle. Por eso este archivo se escribe en el momento, no
se reconstruye al final.

**Asistente utilizado:** Claude (Claude Code, modelo Opus).

---

## Registro

### 2026-09-01 — Análisis del enunciado y planificación

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección / refinamiento aplicado |
|---|---|---|---|---|
| 1 | Entender qué pesa en la nota | Se adjuntó el enunciado con la instrucción explícita: *"léela, dime lo importante y **planea sin hacer nada**, pregúntame todo lo que necesites"* | Análisis de la rúbrica, plan por fases y 4 preguntas de decisión | **La restricción "sin hacer nada" fue deliberada.** Sin ella el asistente arranca produciendo documento antes de entender el enunciado. Forzarlo a planificar y preguntar primero fue lo que hizo aparecer el análisis de pesos de la rúbrica. |
| 2 | Corregir jerga sin definir | *"¿qué es FR+NFR? explícame todo sin entrar en mucho detalle a menos que te lo pida"* | Explicación general del proyecto y de OLTP vs OLAP | El asistente había usado siglas sin traducir. Se le corrigió el registro: explicación de alto nivel primero, profundidad sólo bajo pedido. |
| 3 | Decisión de infraestructura | Ante la opción de reutilizar la RDS MySQL y las conexiones Glue de prácticas anteriores, se decidió **crear todo nuevo** | El asistente había recomendado reutilizar para ahorrar presupuesto | **Decisión propia, en contra de la sugerencia del asistente.** Reutilizar obligaba a explicar en la defensa por qué un componente venía prestado de otra práctica. La coherencia del trabajo pesa más que ~$2 de ahorro. |
| 4 | Manejar la restricción faltante (§3) | Se le planteó que la restricción específica todavía no fue asignada | Propuso modelar las reglas de negocio sensibles como **políticas parametrizables** en vez de invariantes rígidos | Se adoptó. El ejemplo concreto: `capacidad_vendible = f(capacidad_física, política_comercial)`, para que una restricción del tipo "se permite overbooking" entre como configuración y no como rediseño. |

### 2026-09-06 — Redacción del documento e implementación

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección / refinamiento aplicado |
|---|---|---|---|---|
| 5 | Situar el parcial en el curso | *"revisa todas las actividades del campus desde la semana 1, planea cómo hacerlas y documenta"* | Relevamiento completo del campus: 13 entregas vencidas, sólo 1 enviada | **Reordenó la prioridad.** El plan inicial trataba el parcial como una tarea más; al ver que vencía en 4 días y pesaba más que todo el backlog junto, se reescribió el plan poniéndolo como prioridad 0. |
| 6 | Evitar que la IA decida por mí | *"planea y dime cómo piensas implementar el 5.7 **antes de hacer cualquier cosa**"* | Plan por fases, 5 decisiones con alternativas y proyección de costos | **La restricción explícita fue clave otra vez.** Sin ella habría empezado a crear recursos en AWS. El plan mostró que convenía validar todo en local primero: depurar el ETL contra AWS habría costado varios dólares en instancias encendidas. |
| 7 | Decisiones estructurales del diseño | El asistente presentó 4 bifurcaciones (itinerario multi-tramo, momento del pago, control de sobreventa, canal de agencias) con trade-offs y recomendación | Cuatro pares decisión/alternativa | **Las decisiones las tomé yo, con la alternativa a la vista.** Es lo que después permite defender cada una: la columna "alternativa descartada" del documento no es decorativa, es el registro de esa elección. |
| 8 | Concurrencia — corrección de fondo | Al revisar el código de la API antes de probarlo, apareció que usaba **una sola conexión compartida** | El asistente lo detectó y lo corrigió por pool antes de ejecutar | **Es el error más peligroso del trabajo**: la prueba de concurrencia habría pasado igual, pero por el motivo equivocado — sin paralelismo real no hay carrera que ganar. Un test que pasa por la razón incorrecta es peor que uno que falla. |
| 9 | Demostrar la falla, no sólo la cura | *"que la evidencia muestre el antes y el después"* | Modo `MODO_INSEGURO` que reproduce el patrón ingenuo leer→decidir→escribir | Al ejecutarlo, **el `CHECK` de la tabla impedía ver la sobreventa**. Hubo que retirarlo temporalmente para reproducir la falla — lo que terminó demostrando algo mejor: la restricción declarativa protegía incluso con el mecanismo aplicativo roto. |
| 10 | Datos de prueba | Generador SQL de actividad transaccional | Falló dos veces | **Las dos fallas fueron informativas y quedaron documentadas:** (a) colisión de PNR por la paradoja del cumpleaños con 6 caracteres → se resolvió con reintento, que es lo que hacen los sistemas reales; (b) sobreventa en business porque el generador repartía 10 % a esa clase sin mirar que sólo hay 12 asientos. **El invariante encontró un bug en el código que lo alimentaba.** |

### 2026-09-08 — Despliegue en AWS

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección / refinamiento aplicado |
|---|---|---|---|---|
| 11 | Ejecutar la sesión de AWS | *"usá Claude in Chrome o tomá control de mi PC y realizá la sesión de AWS, iterá las veces que sea necesario y preguntame lo que necesites"* | Propuso dos vías de acceso: CLI local con credenciales pegadas (rápido) o CloudShell manejado desde el navegador | **Elegí CloudShell**, aunque es más lento: las credenciales del lab nunca tocan mi disco. Es la regla que yo mismo había escrito en el `CLAUDE.md` y el asistente la respetó al plantear la opción. |
| 12 | Cargar datos en bases privadas | El asistente detectó **antes de crear nada** que CloudShell corre fuera de la VPC y no podría alcanzar unas RDS privadas | Planteó tres salidas: CloudShell en modo VPC, ventana temporal por IP, o bootstrap por un job de Glue | **Elegí la ventana temporal**, limitada a **una sola IP** y cerrada en la misma sesión. La decisión y su contradicción aparente con el `NFR-SEG-02` quedan documentadas: el régimen es privado, el bootstrap necesitó una ventana. **Que el problema apareciera en el diseño y no a mitad de la carga fue consecuencia de pedir el plan antes de ejecutar** — el mismo patrón que ya había funcionado dos veces. |
| 13 | Verificar el análisis de costos de S3 | Aplicar la política de ciclo de vida revisada | AWS respondió `TransitionDefaultMinimumObjectSize: all_storage_classes_128K` | **El servicio confirmó el análisis.** Yo había argumentado que el mínimo facturable de 128 KB hace que Standard-IA salga más caro para archivos chicos; resulta que AWS directamente **no transiciona** objetos por debajo de ese umbral. Se reemplazó el argumento teórico por la evidencia del propio servicio, y se verificó midiendo: el objeto más grande del data lake pesa 81,4 KiB. |
| 14 | Consistencia de las cifras | Al comparar la corrida de AWS con la local aparecieron **9.121 hechos** contra los **8.821** documentados | El asistente lo señaló en vez de actualizar el número en silencio | **Se documentó la diferencia y su causa:** el generador de actividad demo es aleatorio, así que cada corrida produce un volumen distinto; las dimensiones (141) coinciden porque son deterministas. Cambiar la cifra sin explicar por qué habría dejado dos números incompatibles entre documentos. |
| 15 | Revisar lo desplegado | *"ahora hacé los trabajos del Moodle, hacelos en AWS"* | El asistente empezó señalando un hueco **en su propio trabajo del día anterior**: el data lake tenía tres zonas y sólo `curated/` con datos, mientras el diagrama del Checkpoint 1 afirmaba un flujo completo | **Se corrigió antes de agregar nada nuevo.** La evidencia contradecía al documento, y eso en una defensa eliminatoria se paga caro. Es el tipo de error que sólo aparece releyendo lo entregado contra lo afirmado. |
| 16 | Extraer de una base privada | Al plantear cómo poblar `raw/`, apareció que las RDS ya eran privadas y CloudShell corre fuera de la VPC | Dos opciones: reabrir la ventana por IP, o un job de Glue dentro de la VPC | **Elegí el job de Glue**, revirtiendo mi propio "no hace falta" del día anterior. El contexto había cambiado: ya no era un lujo sino la única vía que no reabría la ventana — y de paso les dio un consumidor a las dos conexiones JDBC, que hasta entonces existían sin que nada las usara. |
| 17 | Que las zonas signifiquen algo | Al escribir el job, decidir si `processed/` se construye desde la base o desde `raw/` | El asistente propuso releer `raw/` desde S3 | **Se adoptó, y es la decisión que vuelve real la zona cruda:** si `processed/` se regenerara volviendo a la fuente, `raw/` sería decorativa y el argumento de reversibilidad se caería en la primera pregunta. El tipado —devolverle al CSV el esquema de PostgreSQL— quedó como la transformación concreta que justifica la zona. |

### 2026-09-10 — Guía de ejecución en AWS

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección / refinamiento aplicado |
|---|---|---|---|---|
| 18 | Documentar cómo correr todo | *"creá un documento con el paso a paso para correr la app en AWS, qué hiciste y por qué, y cómo abrir cada cosa por separado"* | El asistente empezó por releer el código antes de escribir, y encontró **dos defectos** | **(a)** `prueba_concurrencia.py` tenía la conexión fija al Docker local mientras la API la leía del entorno: apuntada a RDS, la prueba habría preparado y verificado la instancia en **otra base**. **(b)** La restauración de la corrida sin lock estaba en el orden equivocado: re-agregar el `CHECK` con filas que lo violan falla. Ambos corregidos. Ninguno se había manifestado porque todo corría en local — **aparecieron al intentar escribir los pasos para AWS**. |
| 19 | Que todo corra en AWS | *"todo debe correrse en AWS, nada en mi local"* | La API nunca se había desplegado en AWS: sólo había corrido en local | Se diseñó una **EC2 dentro de la VPC** para la API, el ETL y `psql`, porque las RDS son privadas y CloudShell corre afuera. La contraseña pasa por **SSM Parameter Store** en vez del user-data, y el acceso es por **EC2 Instance Connect** sin abrir el 22 a internet. **Esta parte quedó marcada como no ejecutada todavía** en la guía, en vez de presentarla como verificada. |
| 20 | Probar la guía de punta a punta | *"probá todo en AWS"* | La guía completa ejecutada en AWS: EC2 por EC2 Instance Connect, la API, el ciclo de reserva y pago, la prueba de concurrencia en los dos modos, el ETL, el job de Glue y Athena | **La prueba encontró dos bugs más que en local nunca se habían visto.** (a) La prueba de concurrencia intentaba borrar reservas **pagadas** y chocaba con la FK de `pago`. La FK estaba bien: el esquema protege a propósito los registros financieros. Se corrigió la prueba, que ahora usa una instancia de vuelo propia. (b) El job de Glue duplicaba `processed/` en la segunda corrida. Los dos bugs dependían de condiciones que el entorno local no reproducía: datos aleatorios distintos y una sola extracción. |
| 21 | Un error del asistente durante la prueba | Desplegar la corrección del job de Glue | El asistente subió el archivo corregido a CloudShell y lo desplegó | **La subida había fallado en silencio** —CloudShell no sobrescribe archivos— y la verificación del asistente buscó un texto que aparecía **en las dos versiones**. Se desplegó el script con el bug. Esa corrida terminó sirviendo: midió el bug (**17.787 filas para 8.894 reservas**). La corrección real se verificó mirando la línea que cambió, no una que se repetía. **Una verificación que no puede fallar no verifica nada.** |
| 22 | La demo sin lock en AWS | Correr la corrida A contra RDS | 2 reservas confirmadas sobre 1 asiento, **con el contador diciendo 1** | En local habían sido 4. Con la latencia de red de RDS, la ventana de carrera cambia y colisionan menos pedidos. **El resultado que importa es el mismo, y es más claro:** es una actualización perdida, y el sistema no sabe que vendió de más. |

### 2026-09-10 — Documento final consolidado

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección / refinamiento aplicado |
|---|---|---|---|---|
| 23 | Armar el documento de entrega | *"¿existe algún documento respuesta al parcial? En caso de que no, créalo"* | Antes de consolidar, el asistente releyó cada sección contra el enunciado y contra lo desplegado, y encontró **cuatro inconsistencias**: la 5.7 afirmaba crawlers JDBC sobre las dos bases que nunca se corrieron; nombraba una subred de otra zona; no tenía el diagrama de arquitectura que exige su entregable; y la 5.6 remitía a una tabla de ajustes de la 5.4 que estaba vacía | Me planteó dos salidas para el catálogo: correr los dos crawlers JDBC (~$0,25, RDS encendidas) o **reescribir la 5.7 para que diga exactamente lo que se hizo**. **Elegí reescribirla**: las dos bases quedan catalogadas a través de sus copias en S3, y la diferencia con el enunciado se declara como desviación, con lo que costaría cerrarla. Una afirmación falsa en la sección que más pesa es peor que una desviación declarada. |

---

## Observaciones sobre el uso de la herramienta

### Dónde ayudó de verdad

- **Redactar con trazabilidad.** Mantener coherentes ~50 identificadores (`FR-`, `NFR-`,
  `DEC-`, `SUP-`, `RSK-`) referenciados entre siete documentos es trabajo mecánico y propenso
  al error humano. Acá la herramienta es claramente mejor que yo.
- **Verificar en vez de afirmar.** Cada afirmación técnica del documento se ejecutó antes de
  escribirla: el invariante se probó con SQL, la concurrencia con 30 peticiones simultáneas,
  el ETL con 8.794 filas reales. Las únicas cifras estimadas son las de costo, y se declaran
  como tales.
- **Anticipar el costo antes de gastarlo.** El plan de trabajar en local y subir a AWS una
  sola vez salió de pedir el plan antes de la ejecución.

### Dónde se equivocó

- **La conexión única** (entrada 8). Habría invalidado la prueba más importante del trabajo.
- **Tiende a producir antes de entender.** Las dos veces que el resultado fue mejor, fue
  porque el prompt incluía una prohibición explícita: *"sin hacer nada"*, *"antes de hacer
  cualquier cosa"*. Sin esa restricción arranca a escribir código o crear recursos.
- **Recomendó reutilizar infraestructura** de prácticas anteriores para ahorrar presupuesto,
  sin considerar el costo de tener que explicarlo en la defensa (entrada 3).

### Qué mantuve bajo control propio

Las **decisiones de diseño**, sin excepción. La herramienta presentó alternativas con sus
trade-offs; la elección fue mía en los cuatro casos estructurales, y en uno fue **en contra**
de su recomendación.

Es una distinción que importa por cómo se evalúa este trabajo: la defensa oral es
eliminatoria por sección. Una decisión que no tomé yo es una sección que no puedo sostener.
