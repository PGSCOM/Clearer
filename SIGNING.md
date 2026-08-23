# Firmar, instalar y publicar — sin Mac

`ci.yml` produce en cada push un `.ipa` **sin firmar** (`CODE_SIGNING_ALLOWED=NO`). Sirve para
comprobar que el archive se genera bien, pero **no se puede instalar en un iPhone tal cual** —
iOS exige que todo binario esté firmado. Este documento cubre las dos vías para instalarlo de
verdad, ninguna de las cuales necesita un Mac.

## Vía A — Apple Developer Program (99 €/año), para TestFlight y publicar

Es la única vía que llega a la App Store. El certificado y el perfil se pueden generar enteros
sin Mac, con `openssl` (viene con Git Bash en Windows) más el propio portal web de Apple.

**1. Generar la clave privada y el CSR en Windows:**

```bash
openssl req -new -newkey rsa:2048 -nodes \
  -keyout distribution.key \
  -out CertificateSigningRequest.certSigningRequest \
  -subj "/CN=Pablo Garcia Santamaria/emailAddress=tu-correo@ejemplo.com"
```

**2. Subir el `.certSigningRequest`** en
[developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates/list)
→ tipo "Apple Distribution" → descarga el `.cer` resultante.

**3. Convertir cert + clave a `.p12`** (el formato que consume `xcodebuild`):

```bash
openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
openssl pkcs12 -export \
  -inkey distribution.key -in distribution.pem \
  -out distribution.p12 -passout pass:UNA_CONTRASEÑA_TUYA
```

**4. Perfil de aprovisionamiento**: en el mismo portal, crear un identificador de app
(`com.pablogarcia.clearer`, el mismo de `project.yml`), luego un perfil "App Store" o
"Ad Hoc" que use el certificado del paso 2. Descargar el `.mobileprovision`.

**5. Clave de App Store Connect API** (para que la Action pueda subir el build sin tu
contraseña): App Store Connect → Users and Access → Integrations → Keys → genera una, descarga
el `.p8` una sola vez (no se puede volver a descargar).

**6. Secrets del repo** (Settings → Secrets and variables → Actions), todo en base64
(`base64 -w0 fichero > fichero.b64` en Git Bash):

| Secret | Contenido |
|---|---|
| `DIST_CERTIFICATE_P12` | `distribution.p12` en base64 |
| `DIST_CERTIFICATE_PASSWORD` | la contraseña del paso 3 |
| `PROVISIONING_PROFILE` | el `.mobileprovision` en base64 |
| `ASC_API_KEY_P8` | el `.p8` del paso 5, en base64 |
| `ASC_API_KEY_ID` | el Key ID que muestra el portal |
| `ASC_API_ISSUER_ID` | el Issuer ID que muestra el portal |

**7. Pasos que añadir a `ci.yml`** cuando llegue el momento (no están en el workflow actual
porque hasta la Fase 4 no hay nada que merezca subirse):

- Crear un keychain temporal e importar `DIST_CERTIFICATE_P12` (`security create-keychain` +
  `security import`).
- Copiar `PROVISIONING_PROFILE` a `~/Library/MobileDevice/Provisioning Profiles/`.
- Sustituir el archive sin firmar por uno firmado (`CODE_SIGN_STYLE=Manual`,
  `CODE_SIGN_IDENTITY="Apple Distribution"`, `PROVISIONING_PROFILE_SPECIFIER=...`).
- `xcodebuild -exportArchive` con un `ExportOptions.plist` (`method: app-store-connect`).
- `xcrun altool --upload-package` (o `xcrun notarytool`/Transporter si Apple lo sustituye)
  autenticado con `ASC_API_KEY_*` para subir a TestFlight.

Una vez en TestFlight, el build dura 90 días y se instala desde la propia app TestFlight en el
iPhone — cero cables, cero Mac.

## Vía B — Apple ID gratis, para probar en tu iPhone ya

Sin pagar el Developer Program. Sirve para desarrollo, no para publicar.

- **[Sideloadly](https://sideloadly.io/)** o **AltStore** (ambos con versión Windows), por USB.
  Firman el `.ipa` sin firmar de la Action con tu Apple ID gratis.
- Límite real: máx. 3 apps a la vez en el dispositivo, y **hay que reinstalar cada 7 días**
  (la firma de un Apple ID gratis caduca a la semana). Para el ritmo de "compilo en la Action,
  lo pruebo en el móvil" varias veces por semana es molesto pero viable.
- No hace falta certificado ni perfil de los pasos de la Vía A — la propia herramienta gestiona
  la firma ad-hoc con tu Apple ID.

## Estado actual

Ahora mismo el proyecto está en la Vía B implícita: cada push deja un `.ipa` sin firmar como
artefacto de la Action, listo para pasarlo por Sideloadly/AltStore. La Vía A se activa cuando
Pablo dé de alta el Developer Program, ańadiendo los secrets de la tabla y los pasos del punto 7.
