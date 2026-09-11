# Ficha de la App Store — Clearer

Listo para copiar y pegar en App Store Connect (App Information + la página de cada
versión). Los límites de caracteres de Apple están anotados junto a cada campo;
todo lo de aquí ya cabe dentro de ellos.

---

## Español (mercado principal)

**Nombre** (máx. 30):
```
Clearer
```

**Subtítulo** (máx. 30 — 21 usados):
```
Tu fototeca, sin nube
```

**Palabras clave** (máx. 100, sin espacios tras las comas — 96 usados):
```
limpiar fotos,liberar espacio,duplicados,capturas,privacidad,papelera,organizar,rafagas,fototeca
```

**Descripción** (máx. 4000):
```
Clearer te ayuda a encontrar las fotos que sobran en tu iPhone: capturas de
pantalla olvidadas, fotos borrosas, ráfagas enteras cuando solo necesitabas
una, casi-duplicados que se acumulan sin que te dieras cuenta.

Todo el análisis pasa en tu iPhone. Ninguna foto sale de tu teléfono, nunca.
Y si tienes fotos guardadas solo en iCloud, Clearer no las descarga para
analizarlas: las respeta tal como están. Si una foto en concreto se ve mal
y quieres decidir con más calidad, puedes pedir verla en su resolución
original — eso sí baja de iCloud, pero solo esa foto y solo si tú lo pides.

Cómo funciona:

- Eliges qué buscar: capturas, recibos y documentos, fotos de baja calidad,
  vídeos largos, ráfagas.
- Revisas una a una lo que Clearer encontró, con el motivo a la vista.
- Nada se borra hasta que tú lo confirmes. Dos veces: primero en la papelera
  propia de Clearer, luego en la confirmación nativa de iOS.

Sin cuentas, sin conexión a internet necesaria. Clearer funciona igual con
el móvil en modo avión.
```

**Notas de la versión** (v1.0):
```
Primera versión de Clearer.
```

---

## English

**Name** (max 30):
```
Clearer
```

**Subtitle** (max 30 — 21 used):
```
Your photos, no cloud
```

**Keywords** (max 100, no spaces after commas — 94 used):
```
photo cleaner,free up space,duplicates,screenshots,privacy,trash,organize,bursts,photo library
```

**Description** (max 4000):
```
Clearer helps you find the photos that don't need to stick around: forgotten
screenshots, blurry shots, whole bursts when you only needed one,
near-duplicates piling up without you noticing.

All the analysis happens on your iPhone. No photo ever leaves your phone.
And if you have photos that only live in iCloud, Clearer never downloads
them just to look at them: it leaves them exactly as they are. If a
particular photo looks rough and you want a closer look before deciding,
you can ask to see it at full resolution — that does download from
iCloud, but only that one photo, and only when you ask for it.

How it works:

- Choose what to look for: screenshots, receipts and documents, low-quality
  photos, long videos, extra burst shots.
- Review what Clearer found one at a time, with the reason right there.
- Nothing gets deleted until you say so. Twice: first into Clearer's own
  trash, then iOS's own native confirmation.

No account, no internet connection required. Clearer works exactly the same
in airplane mode.
```

**What's New** (v1.0):
```
First version of Clearer.
```

---

## Categoría y clasificación

- **Categoría primaria sugerida**: Fotografía (Photo & Video). Es la categoría
  correcta — no "Utilidades" ni "Productividad" — porque la app trabaja
  directamente sobre la fototeca del sistema, que es exactamente lo que Apple
  espera ver ahí.
- **Clasificación por edades**: sin contenido sensible, 4+.
- **Etiqueta de privacidad (App Privacy)**: al rellenar el cuestionario en App
  Store Connect, la respuesta honesta a "Data Used to Track You" y "Data
  Linked to You" es **ninguna** — la app no manda nada a ningún sitio. El
  manifiesto `Sources/PrivacyInfo.xcprivacy` ya lo declara a nivel de bundle;
  el cuestionario de App Store Connect es un formulario aparte que hay que
  rellenar a mano, pero la respuesta es la misma en los dos sitios.

## Nota sobre las capturas de pantalla de la ficha

Las capturas que exige la ficha (6.5" y 5.5" como mínimo) tienen que ser de la
app real corriendo en un dispositivo o simulador — no se pueden generar a
ciegas sin verlas. Cuando tengas la app instalada en tu iPhone (vía
SIGNING.md), es el momento de capturarlas: la pantalla de bienvenida del
onboarding, la rejilla de fotos, la pantalla de análisis con resultados, y la
revisión con una tarjeta. Son las cuatro que mejor cuentan la historia de la
app en el primer vistazo.
