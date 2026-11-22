# CompraClara

Lista de la compra inteligente por secciones del supermercado. Producto de IT Canarias.

**Versión 0.1 (MVP interno, solo Android, todo local en el móvil):**

- Listas múltiples (crear, renombrar, archivar, reutilizar).
- Catálogo de artículos con marca, formato, sección y códigos de barras.
- Supermercados con plantilla de 18 secciones, orden de recorrido editable y ubicación por artículo.
- Modo compra por secciones: elegir sección, marcar como cogido, «no hay», pasar a la siguiente.
- Escáner de código de barras (catálogo propio y Open Food Facts).
- Precio manual por artículo e historial; estimación y comparativa de la lista entre tiendas.
- Funciona sin conexión.

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

1. **Versión 1 (Android):** ticket con OCR, etiqueta de estantería, recomendador de supermercado,
   precios colaborativos, presupuesto, servidor y cuentas.
2. **Versión 2:** compartir listas y compra simultánea en tiempo real.
3. **Versión 3:** iPhone.
