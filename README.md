# CompraClara

Lista de la compra inteligente por secciones del supermercado. Producto de IT Canarias.

**Versión 0.2 (solo Android):**

- Listas, packs, duplicar, presupuesto por lista y mensual, historial de compras y repetir compra.
- Añadir buscando, escribiendo varios de corrido («2 kg papas, huevos»), por voz, pegando una lista,
  escaneando el código (Open Food Facts) y habituales («te toca…»).
- Supermercados con 18 secciones, recorrido que se aprende con el uso y ubicación de cada tienda.
- Modo tienda por secciones: cogido, cantidad parcial, «no hay», otra sección, precio, foto de etiqueta,
  detección de la tienda por GPS y terminar compra con repaso del ticket (modo caja).
- Ticket y etiqueta de estantería leídos en el móvil (ML Kit), con revisión y alias aprendidos.
- Ahorro: comparar tiendas dentro de un radio de km, «más barato en…», dividir la compra,
  precio por kg/l, caducidad de ofertas, bajadas de precio y resumen semanal/mensual.
- Alergias y dietas, Nutri-Score, tarjetas de fidelidad, cupones y garantías.
- Copia de seguridad (archivo y nube), exportación CSV, datos de ejemplo y primer uso guiado.
- Cuenta y precios compartidos con el servidor (`server/`).

La especificación completa está en el Proyecto «App Lista De La Compra» (Claude).

## Compilación

El proyecto Android se genera en CI con `flutter create` y se ajusta con `tool/patch_android.sh`
(nombre, permisos de cámara e internet). Cada `push` a `main` compila el APK y lo deja como
artefacto del flujo «Compilar Android». Una etiqueta `vX.Y.Z` lo publica en Releases.

En local:

```bash
flutter create --platforms=android --org com.itcanarias --project-name compraclara .
bash tool/patch_android.sh
flutter pub get
flutter run
```

## Hoja de ruta

1. **Versión 1 (Android):** hecha en 0.2; queda desplegar el servidor y fijar la clave de firma.
2. **Versión 2:** compartir listas y compra simultánea en tiempo real.
3. **Versión 3:** iPhone.
