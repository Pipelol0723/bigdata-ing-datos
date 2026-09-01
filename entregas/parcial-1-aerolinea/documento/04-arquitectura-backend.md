# 5.4 Arquitectura backend

> **Estado:** ⬜ decisiones el viernes 4/09 · redacción final el martes 8/09
> **Peso en la rúbrica:** 15% (compartido con 5.5)

**Por qué se redacta después de implementar:** las decisiones se toman el viernes porque son
input obligatorio de 5.6, pero la redacción final va después de programar. El enunciado
premia declarar los ajustes que aparecieron al implementar; escribir esta sección antes de
tocar código obliga a reescribirla o a mentir.

## Qué exige la rúbrica para "Sobresaliente"

> *"Cada decisión conecta explícitamente con un NFR o FR específico, especialmente el
> manejo de concurrencia."*

## Tabla de decisiones

| ID | Decisión | Alternativa descartada | Requisito que la sustenta | Justificación |
|---|---|---|---|---|
| `DEC-01` | | | `NFR-…` / `FR-…` | |

## Preguntas guía a resolver

- [ ] ¿Monolito o servicios separados (búsqueda, reservas, pagos)? ¿Qué NFR sostiene esa
      elección, en particular el de concurrencia sobre el inventario de asientos?
- [ ] ¿Cómo se garantiza que un vuelo no se sobrevenda con múltiples pedidos simultáneos?
      ¿Lock pesimista, lock optimista con reintentos, o una cola que serializa por vuelo?
- [ ] ¿Cómo se integra el flujo de pago? ¿Se delega por completo a un proveedor externo, o
      el sistema maneja parte de la lógica?
- [ ] ¿Cómo se exponen los servicios a las agencias asociadas? ¿La misma API que el sitio
      del pasajero final, o una API B2B separada?
- [ ] ¿Cómo se relaciona esta arquitectura transaccional con el pipeline de Big Data
      del curso? *(el puente hacia 5.7)*

## Ajustes que aparecieron durante la implementación

*(se completa después de 5.6 — un ajuste no es un error, es información valiosa)*

| Qué cambió | Por qué | Documento actualizado |
|---|---|---|

## Impacto de la restricción específica (§3)

⏳ Pendiente de asignación.
