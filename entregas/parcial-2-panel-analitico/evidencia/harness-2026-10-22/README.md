# Segunda corrida del harness en AWS — 22/10/2026 · **70,0 / 70,0**

Corrida completa desde **CloudShell** el día de la preparación de la presentación, con dos diferencias
respecto de la del 18/10 (`../harness-2026-10-18/`, que sigue siendo el reporte sin editar del Anexo C):

- La proyección de costos es **la entregada (US$8,36)**, no la de US$12,65 que se evaluó el 18/10.
- La EC2 tiene **otra IP** (`54.147.173.30`): el lab la reinició al abrir la sesión y la app volvió sola.

Se lanzó con `infra/05-correr-harness.sh` (busca la IP, reinstala en `/tmp` lo que CloudShell borra
entre sesiones y corre `pytest`). Los números de abajo se transcribieron de `report.md` en la
pantalla de CloudShell; el archivo quedó en `~/p2h/harness/` de CloudShell, no en el repo.

| Req | Resultado | Evidencia |
|---|---|---|
| Total | **70,0 / 70,0** | 23 passed in 39,63 s (otra corrida del alumno minutos después: 33,65 s, mismo puntaje) |
| R1 | passed 4/4 | 100 pedidos, 20 concurrentes: p50 = 0,013 s, **p95 = 0,069 s** |
| R2 | passed 10/10 | 1 de 50 por el último asiento y 3 de 50 con K = 3, 5 rondas cada uno |
| R6 | passed 8/8 | un mes escaneó **280.837 B**; tope 1.827.162 B (partición promedio 913.581 B) |
| R10 | passed 5/5 | **48** horas normalizadas en 45 días (tope 150) |
| R11 | passed 4/4 | servicios: Athena, EC2, EMR, Glue, Lambda (de la cuenta del lab), S3 |
| R12 | passed 4/4 | declarado **8,36**; tope 50; estimado sobre lo vivo **9,03** (EC2 7,59 + EMR 1,44) |

Ese mismo día, desde la laptop y **sin credenciales de AWS**, `tests/test_backend.py` y
`tests/test_frontend.py` dieron 7/7 (27 puntos; los de AWS quedan `not_verified`), con p95 de R1 =
0,369 s por internet. Sirvió para confirmar que el arreglo de CSS de `app/static/index.html` no
cambió el recorrido de R8.
