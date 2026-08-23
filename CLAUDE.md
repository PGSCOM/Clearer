# FotIA Cleaner — contexto para Claude Code

App iOS nativa (Swift/SwiftUI) para liberar espacio en la fototeca detectando fotos que sobran
(capturas, borrosas, duplicados, ráfagas...) según criterios que el usuario activa en un
onboarding. Se publicará en la App Store. El plan completo, con el razonamiento detrás de cada
decisión, vive en `~/.claude/plans/quiero-que-hagas-una-shiny-sketch.md` de Pablo — este fichero
resume lo que no hay que reinterpretar.

## El no-negociable del proyecto

**Nunca se descarga una foto a resolución máxima desde iCloud.** Es el motivo de ser de la app;
romperlo la invalida entera. Se garantiza así:

- **`Sources/Photos/PhotoLibrary.swift` es el ÚNICO fichero que toca `PHImageManager`.**
  `isNetworkAccessAllowed = false` se fija ahí y en ningún otro sitio. Todo lo demás pide
  miniaturas a este actor, nunca a PhotoKit directamente. Las miniaturas piden
  `deliveryMode = .fastFormat` a propósito, no solo por velocidad: es el único modo con el que
  PhotoKit garantiza una única llamada al completion handler — con `.opportunistic` la segunda
  pasada "mejor calidad" podría necesitar red (que tenemos desactivada) y no hay garantía
  documentada de que llegue una llamada final en ese caso, así que se arriesgaría a colgar la
  `continuation` para siempre.
- Si PhotoKit marca un asset como solo-en-iCloud, se salta y se cuenta — no se descarga.
- CI (`.github/workflows/ci.yml`) tiene un `grep` que **falla el build** si aparece
  `PHImageManager`/`requestImage` fuera de ese fichero. Si tocas algo de Photos y el guard salta,
  el fix es mover el código a `PhotoLibrary.swift`, no relajar el grep.
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
- **Sin Mac.** Pablo desarrolla en Windows. El proyecto Xcode (`FotIACleaner.xcodeproj`) **no se
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
- **La cobertura de CI de Fase 2 es solo lógica pura** (`Detectors`, `Grouping`, con tests reales).
  La pantalla de análisis (settings + resultados) no se verifica en CI: hacerlo exigiría conceder
  permiso de fotos sin interacción (`simctl privacy grant`) y sembrar imágenes fixture, lo que
  además rompería el test de Fase 1 que depende de que el simulador arranque en `.notDetermined`.
  Quedó fuera a propósito — es una pieza de ingeniería de CI aparte, no una tarea de esta fase. La
  pipeline de Vision (`CalculateImageAestheticsScoresRequest` + `VNGenerateImageFeaturePrintRequest`)
  solo se puede confirmar en el iPhone de Pablo, igual que el invariante de iCloud.

## Verificación

`xcodegen generate` + `xcodebuild test` en CI, más el guard de PhotoKit — todo lo automatizable
ya está en `ci.yml`. Lo que CI no puede cubrir (el invariante de iCloud en sí) se verifica a mano
en el iPhone de Pablo antes de dar una fase por cerrada.

Antes de cualquier entrega de UI: repaso completo de la ley anti-slop de
`~/.claude/CLAUDE.md` — está prometido ahí, no es opcional.
