# Mensaje para el profesor (versión final, 03/11/2026)

> **Lo manda el alumno.** Adjuntos (están en esta carpeta):
> - `Parcial2-Panel-Analitico-Aerolinea.pdf`: el documento final (18 páginas)
> - `Parcial2-repositorio.zip`: la carpeta completa del repositorio, que es privado (733 KB, 97 archivos)

---

**Asunto:** Parcial 2 — entrega final y consultas

Profesor, buenas. Le escribo por tres temas:

1. **Entrega del Parcial 2.** La tarea de Moodle cerró el 20/10 a las 00:00 y no alcancé a subir la
   entrega ahí. Le adjunto el documento final (secciones 5 y 6, matriz de trazabilidad, registro de
   prompts e impacto de cambios) y el repositorio completo: backend, frontend, job de PySpark,
   `config.yaml` sin credenciales, `cost_projection.yaml` y el `report.md` del harness. El sistema
   está desplegado en el Learner Lab y el harness dio **70/70** el 18/10 y otra vez el 22/10.
   ¿Podría reabrir la tarea para que la entrega conste también en Moodle? ¿Y cuál es la fecha y la
   ventana de corrección? El Learner Lab le cambia la IP a la EC2 en cada sesión, y necesito tenerla
   prendida en ese momento.

2. **Dos dudas del contrato.**
   - `bookings` en `route_month_metrics`: el contrato dice "sólo CONFIRMED", pero `oracle.py` lo
     calcula como confirmadas + canceladas. Implementé el contrato y dejé la otra lectura como un
     parámetro del job. ¿Cuál es la correcta?
   - R12: `reference_monthly_usd` está en 60 con la nota "set after building the reference
     solution". ¿Cuál es el valor final? Y la estimación del harness no le pone precio al disco EBS
     ni a la IPv4 pública: ¿la proyección debe incluirlos? Hoy declaro US$8,36 (lo que el harness
     mide) y explico en el documento los US$4,29 restantes.

3. **Módulos de AWS Academy y tareas de Athena.**
   - Los knowledge checks de los módulos 8, 10 y 11 los completé en Canvas antes de cada cierre
     (100/100 el 01/10, el 17/10 y el 17/10), pero no subí la evidencia a Moodle y esas tareas ya
     cerraron. ¿Los puede tomar desde Canvas?
   - Las tareas de Athena (German Credit y partitioned data exercise) no tienen el enunciado en
     Moodle. German Credit sigue abierta y la entregué con el dataset original de la UCI y preguntas
     de negocio propias; si la guía pedía otras preguntas, ¿me la podría compartir? Y la de
     partitioned data cerró el 25/09: ¿hay forma de entregarla?

Gracias,
Andres Felipe Cespedes Rondon
