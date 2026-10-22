# Anexo A — Registro de prompts

El enunciado permite asistentes de IA con la regla del primer parcial: cada decisión tiene que poder
explicarse y defenderse, y el registro de prompts es obligatorio. Lo que se registra no es el prompt
perfecto sino **la iteración**: qué se pidió, qué devolvió la herramienta y qué hubo que corregirle o
decidir.

**Asistente utilizado:** Claude (Claude Code, modelo Opus), con acceso al repositorio, a una terminal
local y al navegador (Claude in Chrome) para operar la consola de AWS y CloudShell.

---

### 17/10 — Lectura del enunciado y del harness, y plan

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección / refinamiento aplicado |
|---|---|---|---|---|
| 1 | Entender qué se evalúa | Se adjuntaron el enunciado y el `.zip` del harness: *"revisa estos 2 documentos … planea su desarrollo"* | Leyó los 30 archivos del harness, no sólo el enunciado, y sacó **13 trampas** que el enunciado no dice. Entre ellas: R10 suma las horas de EMR de 45 días (incluidas las del taller anterior), el Parquet tiene que escribirlo un *step* de EMR, la tabla de métricas no puede particionarse y R12 compara con lo que esté encendido | **Leer el código de los tests fue lo que valió.** Cada trampa se convirtió en una restricción de diseño antes de escribir código: `reservation_id` como texto, métricas sin particionar, el job siempre como *step*, el panel con 2 decimales |
| 2 | Medir antes de diseñar | (dentro del mismo pedido) | Generó el dataset con la semilla de ejemplo en la laptop, sin AWS: 85 MB de CSV, 2,1 M de filas, 10 rutas, 24 meses. Y encontró que **el contrato y el oráculo no coinciden en `bookings`** | La medición mostró que el dataset es chico, de ahí la idea de un clúster mínimo. La inconsistencia de `bookings` quedó como pregunta para el profesor, sin resolverla por mi cuenta |
| 3 | Decidir la arquitectura | El asistente presentó 6 decisiones (D1–D6) con alternativas, costo y recomendación | Hosting, tamaño de la EC2, forma de correr EMR, registro de tablas, frontend y origen de los números del panel | **Las decisiones las tomé yo con las alternativas a la vista:** una EC2 con Docker en vez de RDS, EMR transitorio, DDL con partition projection en vez de crawler, y HTML servido por FastAPI. El tamaño de la EC2 (D2) quedó **a medir, no a suponer**. La recomendación de EMR de un nodo resultó equivocada (#11) |

### 18/10 — Desarrollo en la laptop ($0)

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección / refinamiento aplicado |
|---|---|---|---|---|
| 4 | Arrancar sin depender de una cuenta | *"usa la misma semilla … individual … inicia el desarrollo; si nos quedamos sin créditos tengo otra cuenta, pero se perdería todo lo hecho"* | Scripts de infraestructura que derivan el ID de la cuenta (`aerolinea-p2-<cuenta>`) y todo el desarrollo en local primero | **Reproducibilidad como requisito propio:** si el presupuesto se agota, el sistema entero se recrea en otra cuenta con los mismos comandos. Lo único que se pierde es lo que vive en AWS |
| 5 | Docker no arrancaba | *"docker falló: … dockerInference … The file cannot be accessed"* | Siguió el error más allá del mensaje: el socket trabado era el síntoma, y la causa real que la **virtualización estaba desactivada**, así que WSL2 no podía arrancar | El asistente **no tocó la configuración del sistema**: me explicó cómo hacerlo. La desactivación era mía, de cuando usaba VirtualBox y VMware; borré las VMs y reactivé el hipervisor. Mientras tanto, siguió sin Docker, con un PostgreSQL nativo descartable |
| 6 | Probar el job sin gastar | Correr el PySpark en la laptop y compararlo con el oráculo del profesor | Dos trampas de Windows: el hostname con guion bajo que Spark rechaza, y la escritura que exige `winutils.exe` | Se separó el job en `procesar()` y `escribir()`, para que **el mismo código de transformación** se valide contra el oráculo y sólo la escritura difiera. Resultado: **2.017.079 filas idénticas fila por fila** antes de tocar AWS |
| 7 | El harness contra el backend local | Correr R1–R3 y R8 contra `localhost` | R1 falló: p95 = 2,05 s con p50 = 7 ms | **La distribución delató la causa**: no era lentitud de la app sino `localhost` resolviendo primero a IPv6, con 2 s de espera por conexión nueva. Con `127.0.0.1` bajó a 18 ms. Mirar sólo el número que falla habría llevado a "optimizar" algo que no estaba roto |
| 8 | Dónde probar Docker | *"revisa si puedes hacerlo desde mi homelab"* y después *"dejemos el docker local para después, tengo 3 cuentas de AWS, corre todo lo que necesites ahí"* | Revisó el homelab sin cambiarle nada: tiene WSL y Hyper-V desactivados a propósito y no tiene Docker | **Decisión propia: Docker se prueba directo en la EC2**, que es Linux. Probarlo en local no agregaba nada a lo que la EC2 iba a demostrar |

### 18/10 — Despliegue en AWS

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección / refinamiento aplicado |
|---|---|---|---|---|
| 9 | Operar AWS desde el navegador | *"hazlo todo tú usando Chrome"* | Intentó abrir el Learner Lab desde el curso equivocado y no logró iniciar sesión en la consola | **Le corregí el enlace** (curso 179973). Con el lab abierto ahí, la sesión de la consola se compartió con sus pestañas y siguió por CloudShell |
| 10 | Los crudos en S3 | (dentro del mismo pedido) | Generó los CSV **dentro de CloudShell** en vez de subirlos desde la laptop, y comparó el MD5 con los locales | Así las credenciales del lab no salieron de AWS. Los MD5 diferían, y en lugar de darlo por bueno encontró la causa: los `\r\n` de Windows. Sin ellos, **idénticos byte a byte** |
| 11 | EMR trabado | El job en el clúster de un nodo no avanzaba | Leyó el log del step: *"waiting for resources to be assigned for AM"*; YARN no ubica el application master de Spark en el nodo primario. Paró y **preguntó**: terminar el clúster y cómo corregir | **Era una decisión mía (D3) y un recurso a terminar**: el asistente no hizo ninguna de las dos cosas solo. Elegí terminarlo y pasar a 1 primario + 1 core. El step nuevo terminó en ~2 min. El clúster trabado tardó ~25 min en apagarse, y el script se corrigió para no contarlo como vivo |
| 12 | Una sola corrida con los 70 puntos | Correr el harness completo contra lo desplegado | Primero 60/70 en CloudShell, porque R8 y R9 necesitan un navegador. Instaló Chromium y sus bibliotecas en CloudShell y repitió: **70/70** | El `report.md` de la entrega sale de una sola corrida, no de pegar dos. Para traerlo a la laptop lo pasó en base64, porque la terminal corta las líneas largas, y lo reconstruyó byte a byte |
| 13 | Cerrar la sesión | *"déjala abierta y termina el lab"* | End Lab desde el panel; la EC2 queda para la corrección | **Decisión propia:** la app tiene que estar arriba cuando corrija el profesor. Quedó anotado que el lab la reinicia con otra IP |

### 22/10 — Documentación

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección / refinamiento aplicado |
|---|---|---|---|---|
| 14 | Saber qué falta | *"¿todo está listo para la presentación?"* | No dijo que sí: la app nunca se había probado tras un reinicio, la IP iba a cambiar y faltaba el documento | Una respuesta honesta sobre lo no verificado vale más que un "todo listo" |
| 15 | Las dudas para el profesor | *"realiza la documentación completa … y sobre las preguntas del profesor dime más en detalle"* | Calculó R12 en el tiempo: declarando el costo completo (US$12,65, con EBS e IPv4), **R12 fallaría desde el 24/11**, porque el harness no pone precio a esos dos ítems y las horas de EMR salen de su ventana de 45 días | **Decidí declarar en el yaml sólo lo que el harness mide (US$8,36) y explicar los US$4,29 restantes en el documento**, en vez de esconderlos o arriesgar el requisito. En `bookings`, seguir el contrato escrito con la otra lectura a un parámetro. Las dos quedan como preguntas al profesor |

### 22/10 — Preparación de la presentación

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección / refinamiento aplicado |
|---|---|---|---|---|
| 16 | Levantar todo para la clase | *"inicia todo y abre todas las ventanas necesarias"* | Abrió el lab, confirmó que **la app volvió sola** tras el reinicio (lo único sin probar), actualizó la IP y abrió las consolas. Al mirar la página del cliente vio que el recuadro de confirmación y el campo de pasajero **se mostraban antes de buscar**: el `display: flex` de `section` le ganaba al atributo `hidden` | Una línea de CSS (`[hidden] { display: none !important; }`), aplicada en la EC2 **por SSM** sin reiniciar nada (la app lee el HTML en cada pedido). Antes de aplicarla verificó en el código del harness que el recorrido de R8 no cambiaba, y después volvió a pasar R8 |
| 17 | Los vuelos para la demo | *"dime cuáles son las ciudades y fechas que hay para los viajes"* | La API no lista vuelos, así que los consultó en PostgreSQL por SSM. En el camino cargó vuelos de demo con un precio en centavos de peso (la página mostraba US$ 320.000) | Corrigió esos registros a US$ 320 y 450. Lección: un dato de prueba también se revisa en pantalla |
| 18 | Correr el harness desde AWS | *"¿y puedo hacer las pruebas desde AWS?"* | Encontró que CloudShell tenía la proyección **vieja** (US$12,65): R12 habría medido algo distinto de lo entregado. La reemplazó (MD5 verificado) y escribió `infra/05-correr-harness.sh`. **70,0 / 70,0** con el yaml entregado | Un solo comando para la defensa, que busca la IP sola |
| 19 | Un resumen para la sustentación | *"crea un documento resumen … más corto y simple"* | 4 páginas (`entrega/Parcial2-Resumen-Sustentacion.pdf`). Al verificar cada afirmación contra el repo encontró que §5.1 decía que la falta de backups "se compensa con un `pg_dump` a S3", **que no existe** | §5.1 corregida: es una propuesta, no algo implementado. Una afirmación que no se puede mostrar es un riesgo en una defensa en vivo |
