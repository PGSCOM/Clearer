# Clearer — contexto para Claude Code

App iOS nativa (Swift/SwiftUI) para liberar espacio en la fototeca detectando fotos que sobran
(capturas, borrosas, duplicados, ráfagas...) según criterios que el usuario activa en un
onboarding. Se publicará en la App Store. El plan completo, con el razonamiento detrás de cada
decisión, vive en `~/.claude/plans/quiero-que-hagas-una-shiny-sketch.md` de Pablo — este fichero
resume lo que no hay que reinterpretar.

**Nombre**: el proyecto se llamó "FotIA Cleaner" hasta la Fase 4 (23/08/2026) — el plan había
señalado "Cleaner" como riesgo de posicionamiento (categoría plagada de apps de suscripción
abusiva que Apple vigila de cerca). Se renombró a **Clearer** — sin colisión directa encontrada en
la App Store, mismo registro sonoro que "Cleaner" pero significa claridad, no limpieza. El target,
bundle ID (`com.pablogarcia.clearer`), repo de GitHub y todo el código ya reflejan el nombre nuevo;
si encuentras "FotIA Cleaner"/"fotiacleaner" en algún sitio es un resto sin renombrar, no una
referencia intencional.

## El no-negociable del proyecto

**Nunca se descarga una foto a resolución máxima desde iCloud de forma automática.** Es el motivo
de ser de la app; romperlo por accidente la invalida entera. Desde Fase 5 hay UNA excepción
deliberada y confinada: el usuario puede pedir explícitamente el original de una foto concreta
(botón "Descargar original" en la revisión) para juzgar mejor una foto en baja resolución. Nunca
pasa como parte del análisis, del scroll de la rejilla, del prefetch de la revisión, ni de ningún
barrido — solo de un toque explícito sobre una foto, una a la vez. Se garantiza así:

- **`Sources/Photos/PhotoLibrary.swift` es el ÚNICO fichero que toca `PHImageManager`.**
  `isNetworkAccessAllowed` vale `false` en todo el fichero **salvo dentro de
  `originalImage(for:onProgress:)`**, el único método que existe para esa descarga explícita. Todo
  lo demás pide miniaturas a este actor, nunca a PhotoKit directamente. Las miniaturas piden
  `deliveryMode = .fastFormat` a propósito, no solo por velocidad: es el único modo con el que
  PhotoKit garantiza una única llamada al completion handler — con `.opportunistic` la segunda
  pasada "mejor calidad" podría necesitar red (que tenemos desactivada) y no hay garantía
  documentada de que llegue una llamada final en ese caso, así que se arriesgaría a colgar la
  `continuation` para siempre. `originalImage` usa `.highQualityFormat` por el mismo motivo exacto.
- Si PhotoKit marca un asset como solo-en-iCloud, la miniatura se salta y se cuenta — no se
  descarga. Solo el botón explícito de descarga del original la trae.
- CI (`.github/workflows/ci.yml`) tiene dos `grep` que **fallan el build**: uno si aparece
  `PHImageManager`/`requestImage` fuera de ese fichero, y otro si `isNetworkAccessAllowed = true`
  aparece más de una vez o fuera de `PhotoLibrary.swift`. Si tocas algo de Photos y un guard salta,
  el fix es mover el código a `PhotoLibrary.swift` o mantener la única excepción, no relajar el grep.
- El simulador no tiene iCloud: **ningún test automático puede demostrar el invariante.** La
  comprobación final es siempre en un iPhone real (el de Pablo, un iPhone 14), mirando el
  consumo de red en Ajustes.

## Decisiones ya tomadas (no reabrir sin que Pablo lo pida)

- **Sin servidor, sin nube, sin claves de API.** Todo corre on-device (Vision del sistema +
  Core ML local si algún día hace falta). Es a la vez requisito técnico y argumento de venta.
- **Etiquetado semántico fuera de la v1, a propósito.** Fotos ya hace búsqueda en lenguaje
  natural muy buena desde iOS 18.1, pero solo en iPhone 15 Pro+ (Apple Intelligence). Un
  etiquetado con categorías genéricas nuestras sería peor que lo que el sistema ya hace. Si se
  retoma en v2, es *solo* con vocabulario propio del usuario (MobileCLIP) — nunca categorías
  genéricas — porque eso sí es algo que iOS no ofrece en ningún iPhone.
- **Las "etiquetas" que sí existan se materializan como álbumes de Fotos**
  (`PHAssetCollectionChangeRequest`), nunca como IPTC/EXIF en el fichero: escribir metadatos
  exigiría bajar el original de iCloud, contradice el no-negociable de arriba, y Fotos ni
  siquiera muestra esos campos. iOS tampoco expone API pública para el caption/nota de una foto.
- **Sin Mac.** Pablo desarrolla en Windows. El proyecto Xcode (`Clearer.xcodeproj`) **no se
  versiona** — lo genera XcodeGen desde `project.yml` en cada build. Para tocar el proyecto
  (targets, settings, schemes) se edita `project.yml`, nunca un `.xcodeproj` a mano.
- **La compilación y los tests corren en GitHub Actions** (runner macOS), no localmente. El
  workflow deja como artefacto de cada run: capturas de pantalla de la UI, el `.xcresult` y un
  `.ipa` sin firmar. Es la única forma de "ver" la UI sin tener Mac.
- **Firma**: ver `SIGNING.md`. Ahora mismo sin firmar (Vía B ahí documentada: Sideloadly/AltStore
  con Apple ID gratis). El Apple Developer Program de pago (Vía A, TestFlight/App Store) se
  activa cuando Pablo lo dé de alta.
- **iOS 18.0 mínimo**, iPhone only (`TARGETED_DEVICE_FAMILY: "1"`) para la v1.
- **No hay detector de desenfoque aparte.** `CalculateImageAestheticsScoresRequest.overallScore`
  ya factoriza blur/exposición/composición internamente (confirmado por Apple, no expuesto como
  propiedad separada), así que "foto mal tomada" es solo un umbral sobre ese mismo score que ya
  calculamos para `isUtility`. Implementar varianza Laplaciana a mano (como decía el plan
  original) se descartó a propósito: hubiera sido pixel-math sin forma de probarlo sin Xcode
  local, duplicando una señal que Vision ya da gratis.
- **Los feature prints (para agrupar casi-duplicados) viven solo en memoria, no en SwiftData.**
  Persistirlos exigiría archivar `VNFeaturePrintObservation` vía `NSSecureCoding` — plausible
  pero no confirmado con suficiente confianza para apostar a ciegas. Lo que SÍ se cachea en
  SwiftData (`AssetAnalysis`) es el resultado de aesthetics (`overallScore`/`isUtility`), que es
  la pasada de Vision realmente cara. Recalcular feature prints una vez por sesión es el precio
  aceptado; subir el umbral de duplicados no cuesta nada porque las distancias se recalculan
  sobre prints ya en memoria, no se vuelve a llamar a Vision.
- **"Vídeos pesados" se quedó en "vídeos largos" (por duración, no por tamaño de fichero).** El
  tamaño real solo se puede leer sin descargar vía un KVC no documentado
  (`resource.value(forKey: "fileSize")`) que Apple explícitamente no garantiza y que es zona gris
  para App Review. `asset.duration` es pública, gratis, y buen proxy.
- **`PhotoLibrary.fetchAllAssets()`** (antes `fetchAllPhotos`) trae fotos Y vídeos — los
  detectores de vídeo largo y Live Photo necesitan vídeos en el fetch. La rejilla de Fase 1 ya
  funciona igual para ambos: `PHImageManager` devuelve un fotograma de portada para vídeos sin
  cambios de código.
- **La cobertura de CI de Fase 2 es solo lógica pura por defecto** (`Detectors`, `Grouping`, con
  tests reales). La pantalla de análisis + revisión SÍ tiene un test end-to-end desde Fase 5
  (`UITests/ReviewFlowUITests.swift`), pero es **opt-in**: solo corre si se lanza el workflow a
  mano con `review_ui_test: true` (`workflow_dispatch`), nunca en un `push`/`pull_request` normal.
  Necesita conceder permiso de fotos sin interacción (`simctl privacy grant`) y sembrar fixtures
  (`Tests/Fixtures/`) en un simulador recién borrado — eso rompería el test de onboarding de Fase 1
  si corriera en el MISMO simulador, así que el paso por defecto sigue saltándose
  `ReviewFlowUITests` con `-skip-testing`. La pipeline de Vision
  (`CalculateImageAestheticsScoresRequest` + `VNGenerateImageFeaturePrintRequest`) y la descarga real
  desde iCloud solo se pueden confirmar en el iPhone de Pablo, igual que el invariante de iCloud.
- **El borrado usa `PHPhotoLibrary.shared().performChanges` con `withTimeout` (`Sources/Support/Timeout.swift`).**
  Hay un bug confirmado (foro de Apple) donde el completion handler de `performChanges` a veces no
  llega en algunos builds de iOS 26 al borrar. El timeout (20s) evita que la UI se quede colgada
  esperando para siempre; si salta, el mensaje es deliberadamente ambiguo ("puede que ya se haya
  completado") porque de verdad no lo sabemos — cancelar la Task no cancela la operación real de
  PhotoKit, que sigue corriendo en segundo plano.
- **"Espacio liberado" es una estimación, no un dato exacto** (`SpaceEstimator`), calculada solo
  con propiedades públicas de `PHAsset` (`pixelWidth`/`pixelHeight`/`duration`) — mismo motivo que
  el de "vídeos largos" en Fase 2: no existe API pública para el tamaño real de fichero sin
  descargar. Se etiqueta como estimación en la UI (prefijo "~"), nunca como dato exacto.
- **Los grupos de casi-duplicados/ráfagas NO tienen una pantalla de selección propia.** Cada foto
  "de sobra" de un grupo (todas menos la que `Detectors.excessIDs` marca como mejor) entra en la
  MISMA cola de revisión individual que el resto de criterios, etiquetada con el motivo. Se
  descartó a propósito una vista de comparación lado a lado (grid multi-selección) por ser mucho
  más superficie de UI para verificar a ciegas sin aportar nada que la revisión individual no dé
  ya. Puede añadirse en Fase 4 si en el uso real se echa en falta.
- **La "papelera" de la app es un `Set<String>` en memoria** (`AnalysisCoordinator.pendingDeletionIDs`),
  no persistido en SwiftData — vive mientras el `AnalysisCoordinator` viva (la sesión de la
  pestaña Fotos). Es una capa de seguridad ANTES del borrado real; una vez confirmado, el borrado
  de PhotoKit tiene su propia confirmación nativa del sistema y su propia papelera de 30 días.
- **(Fase 5) La revisión está pensada para ~10.000 fotos, no para una sesión corta.** Tres piezas
  lo sostienen: `ReviewImageStore` mantiene una ventana fija de miniaturas cargadas (unas pocas por
  delante + la última revisada, para deshacer) en vez de cargar toda la cola; `ReviewView` guarda
  qué se ha revisado en `ReviewProgressRecord` (SwiftData, un solo `Set<String>` de IDs, no un
  índice — un índice apuntaría a la foto equivocada en cuanto cambian los criterios) para poder
  cerrar la app y seguir donde lo dejaste; y `AnalysisResultsView` calcula una sola vez
  (`assetSnapshot`) las señales de cada `PHAsset` al terminar el análisis, así que activar/desactivar
  criterios o mover el umbral de duplicados no vuelve a tocar PhotoKit por cada foto. Deshacer
  (`history` en `ReviewView`) es una pila en memoria, no persistida — solo cubre la sesión actual.
- **(Fase 5) Zoom real vía `UIScrollView` envuelto (`ZoomableImageView`), nunca gestos a mano.**
  Vive tanto en la tarjeta de revisión (un pellizco por encima de ~1.15 abre el visor a pantalla
  completa) como en `PhotoViewer` (zoom/pan/doble-toque libres). El centrado sigue el patrón clásico
  de Apple (PhotoScroller): el `frame` de la `UIImageView` es el tamaño real en píxeles de la
  imagen y es `zoomScale` quien la redimensiona en pantalla — no una aproximación con `contentInset`.

## Verificación

`xcodegen generate` + `xcodebuild test` en CI, más los dos guards de PhotoKit (ningún
`PHImageManager` fuera de `PhotoLibrary.swift`, y `isNetworkAccessAllowed = true` exactamente una
vez) — todo lo automatizable por defecto ya está en `ci.yml`. El paso end-to-end de la revisión
(`ReviewFlowUITests`) es opt-in, ver más arriba. Lo que CI no puede cubrir de ningún modo (la
descarga real desde iCloud) se verifica a mano en el iPhone de Pablo antes de dar una fase por
cerrada.

Antes de cualquier entrega de UI: repaso completo de la ley anti-slop de
`~/.claude/CLAUDE.md` — está prometido ahí, no es opcional.
