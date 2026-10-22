# Mensaje para el profesor (borrador, 22/10/2026)

> Asunto: Parcial 2 — dos dudas sobre el contrato y R12

Profesor, buenas. Tengo dos dudas sobre el parcial 2 que encontré al leer el código del harness:

1. **`bookings` en `route_month_metrics`.** El enunciado (A.2) y `contract/DATA.md` dicen que
   `seats_sold` y `bookings` cuentan sólo las reservas CONFIRMED, lo que hace a `bookings` igual a
   `seats_sold`. Pero `airline_data/oracle.py` calcula `bookings` como confirmadas + canceladas
   (`d.groupby(key).size()`). ¿Cuál de las dos definiciones es la correcta? Implementé la del
   contrato escrito, y la otra queda a un parámetro del job.

2. **Referencia de R12.** En `thresholds.yaml`, `reference_monthly_usd` vale 60 con la nota
   "set after building the reference solution". ¿Cuál es el valor que va a usar en la corrida
   final? Y una duda relacionada: la estimación sobre lo desplegado (`harness/cost.py`) no pone
   precio al disco EBS ni a la IPv4 pública. ¿La proyección debe incluir esos costos, o sólo los que
   modela `pricing.yaml`? Hoy declaro sólo los segundos y explico los otros en el documento.

También quería saber la **fecha y la ventana de corrección**, para tener el sistema arriba en ese
momento (el Learner Lab apaga la EC2 al cerrar la sesión y le cambia la IP).

Gracias,
Andres Felipe Cespedes Rondon
