# GamingSocial

Red social gamer para Android hecha con Flutter + Firebase.

**Incluye:** registro e inicio de sesión · perfil (bio, foto, juegos favoritos) ·
publicaciones con imagen por enlace · me gusta · comentarios · seguir / dejar de seguir ·
búsqueda de usuarios · denuncias · bloqueos · diseño adaptable (teléfono y pantallas anchas) ·
**panel de admin visible solo para ti**.

---

## 1. Crear el proyecto de Firebase

1. Entra a <https://console.firebase.google.com> → **Agregar proyecto**.
2. **Authentication** → *Comenzar* → activa **Correo electrónico/contraseña**.
3. **Firestore Database** → *Crear base de datos* → modo **producción** → elige región.
4. En Firestore → pestaña **Reglas** → pega todo el contenido de `firestore.rules` → **Publicar**.

## 2. Conectar la app con Firebase

1. En Firebase: *Configuración del proyecto* → *Tus apps* → **Android**.
2. Nombre del paquete: **`com.gamingsocial.gamingsocial`** (tiene que ser exactamente ese).
3. Descarga `google-services.json` y ábrelo con un editor de texto.
4. Copia 4 valores a `lib/firebase_options.dart`:

| Campo en `firebase_options.dart` | Dónde está en `google-services.json` |
|---|---|
| `apiKey` | `client[0].api_key[0].current_key` |
| `appId` | `client[0].client_info.mobilesdk_app_id` |
| `messagingSenderId` | `project_info.project_number` |
| `projectId` | `project_info.project_id` |

> Estos valores de Firebase no son secretos (la seguridad la ponen las reglas del paso 1),
> pero si prefieres, haz el repositorio privado.

## 3. Compilar la APK en GitHub

1. Sube **todo** este proyecto a un repositorio de GitHub (rama `main`).
2. Pestaña **Actions** → workflow **Build APK** → se ejecuta solo al subir (o *Run workflow*).
3. Cuando termine (unos 5-10 min), abre la ejecución y descarga **GamingSocial-apk** en *Artifacts*.
4. Descomprime el zip e instala `app-release.apk` en tu teléfono.

## 4. Hacerte administrador (solo tú)

1. Abre la app, **regístrate** con tu correo y elige tu usuario.
2. En Firebase → **Authentication → Usuarios** → copia tu **UID**.
3. En **Firestore Database** → *Iniciar colección* → ID de colección: `admins`
   → ID del documento: **tu UID** → agrega cualquier campo (por ejemplo `activo` = `true`) → Guardar.
4. Cierra y abre la app: aparece la pestaña **Admin** (solo para ti).

Nadie más puede crear ese documento: las reglas lo prohíben desde la app, así que el
panel no se puede "activar" desde un teléfono modificado.

## Qué puedes hacer en el panel de admin

- **Usuarios:** ver quién se registró (usuario, correo, fecha), **banear / reactivar**
  o **eliminar** (borra todas sus publicaciones y bloquea la cuenta).
- **Publicaciones:** ver y eliminar cualquier publicación, o banear a su autor.
- **Denuncias:** ver lo que reporta la gente, eliminar el contenido, banear al autor o descartar.

Un usuario baneado entra a una pantalla de "cuenta suspendida" y las reglas del servidor
le impiden publicar, comentar, dar me gusta o seguir.

## Límites de esta primera versión

- **Imágenes por enlace**, no se suben archivos (Firebase Storage exige plan de pago).
  Los clips de video y la subida de fotos quedan para una siguiente etapa.
- **Eliminar cuenta** borra el perfil y las publicaciones, pero el correo sigue en
  *Authentication*; si quieres quitarlo del todo, bórralo a mano en esa pestaña
  (hacerlo desde la app requeriría un servidor propio).
- **Bloquear** oculta a esa persona *para ti*; no impide que ella vea tu contenido.
- Los contadores de me gusta y comentarios los actualiza la app (no un servidor),
  así que un usuario con conocimientos podría falsearlos.
- El **Cloud Gaming** queda fuera de esta versión, como planeamos.
- La APK sale firmada con la clave de depuración: sirve para instalar y probar. Para
  publicarla en Google Play hay que firmarla con tu propia clave.
