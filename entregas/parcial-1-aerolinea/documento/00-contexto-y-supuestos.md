# 0. Contexto y supuestos

> **Estado:** ⬜ pendiente — planificado para el miércoles 2/09

## Por qué esta sección existe

El enunciado deja detalles sin especificar a propósito (cantidad de rutas, si hay programa
de viajero frecuente, si se permiten cambios de itinerario, qué pasa con el equipaje) y
advierte:

> *"un supuesto no declarado es una decisión de arquitectura escondida"*

Todo lo que no esté acá y aun así condicione el diseño, es una decisión invisible que no se
puede defender.

## Supuestos declarados

| ID | Supuesto | Por qué se asume esto | Qué secciones condiciona |
|---|---|---|---|
| `SUP-01` | | | |

## Preguntas abiertas del enunciado a resolver acá

- [ ] ¿Cuántas rutas y vuelos diarios se asumen? (define el orden de magnitud de los NFR)
- [ ] ¿Existe programa de viajero frecuente?
- [ ] ¿Se permiten cambios de itinerario, o sólo cancelación?
- [ ] ¿El sistema gestiona equipaje?
- [ ] ¿Qué monedas e idiomas se soportan?
- [ ] ¿Qué se entiende por "picos de tráfico en temporada alta", en números?

## Defensa: qué se rompe si esto cambia (§7)

El día de la sustentación el profesor plantea un cambio, mejora o problema no cubierto en el
documento, y hay que responder **en el momento** qué parte del diseño se ve afectada. Esta
tabla es la respuesta preparada para esta sección.

| Si cambia… | Qué decisiones o entidades se tocan | Costo del cambio | Alternativa ya considerada |
|---|---|---|---|

> Sobre la restricción específica de equipo (§3), pendiente de confirmar: ver el README.
