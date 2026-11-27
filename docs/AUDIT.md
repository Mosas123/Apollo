# Auditoría de Apollo (base "Apollo") — bugs, mejoras y plan Swift 6

Fecha: 15-nov. Alcance: los 169 ficheros Swift de `/root/work/Apollo`.
Veredicto global: código **limpio y bien estructurado** (sin TODOs, sin `print` sueltos, casi sin force-unwraps). Los problemas reales se concentran en **concurrencia** (PlayerController con mpv) y en **detalles de BD/estado**. Abajo, por severidad.

## A. Bugs que causan fallos o datos incorrectos

1. **`PlayerController.swift` — estado compartido entre hilos sin sincronizar.** ~15 vars `nonisolated(unsafe)` (`currentVideoId`, `desiredPlaying`, `videoFlipAwaitingRestart`, …) se leen desde el event-loop de mpv y se escriben en MainActor:
   - `:461` `handleFileLoaded` lee `desiredPlaying` en el hilo de mpv; `:554` `handleEndFile` lee `currentVideoId`. Son data-races reales (a veces pausa/avanza mal o pierde el `stoppedVideoId`).
2. **`PlaybackManager.swift:76/200`** — `resolveAndPlay` y `resolve` comparten clave de resolución (`videoId`). El `preloadNextTrack` (`NowPlaying.swift:540`) puede pisar la tarea de `resolveAndPlay` y **saltarse el `play()`**, o resolver puede disparar reproducción como efecto colateral.
3. **`DatabaseService.fetchForgottenFavorites`** (`:257-268`) — compara `event.timestamp` (GRDB guarda `Date` como `yyyy-MM-dd HH:mm:ss.SSS`) contra un string `ISO8601DateFormatter`. El formato no coincide → el `NOT IN` falla → devuelve **todas** las canciones con like como "olvidadas".
4. **`SettingsStore.defaultTab`** (`:403-405`) — la migración (`storedTab == 2 ? 3`) corre en **cada arranque**, no una vez: si eliges Explore (índice 2) como pestaña por defecto, al siguiente lanzamiento te lo convierte en 3.
5. **`ApolloApp.observePlaybackSettings`** (`:29-43`) — `withObservationTracking` es de un solo disparo; `onChange` no vuelve a llamar `register()`, así que el EQ/normalización/gapless solo se aplica una vez tras el arranque.
6. **`PlaybackQueue.swift:80`** — `Dictionary(uniqueKeysWithValues:)` **crash** si hay el mismo `videoId` dos veces en la cola. `QueueView.swift:69` usa `id: \.videoId` → IDs duplicados en SwiftUI (indefinido). `NowPlaying.swift:161` accede a `queueSongs[queueIndex]` sin comprobar límites.
7. **`DatabaseMigrations.swift:222-224`** — v7 escribe `downloaded_at` con ISO8601, que GRDB no puede leer de vuelta → filas recuperadas fallan al fetch.

## B. Concurrencia que bloquea Swift 6 (strict)

- **`PlayerController`** es el muro: mpv accede a `_mpv`/propiedades desde dos hilos, y `withMpv` toma un closure `@Sendable (OpaquePointer)` (OpaquePointer no es `Sendable`). Requiere rediseño (actor puente o `@unchecked Sendable` documentado).
- **Singletons mutables sin `@MainActor`**: `SettingsStore.shared`, `AppRouter`, `DurationResolver`, `SearchViewModel`/`HomeViewModel` (estado `static`), `MusixmatchProvider.guestToken`.
- `KeychainStorage` accede a un `SecureStore` desde métodos `nonisolated`; solo compila en Swift 6 si `SecureStore` es `Sendable`.
- `SpotifyAccountStore.cookie()` muta `cachedCookie` dentro de un `queue.sync` sin barrera (data race bajo `@unchecked Sendable`).

## C. Seguridad / privacidad

- **Fuga de sesión a disco**: `LoginWebView` + `Utilities/Log.swift` escriben cookies/`dataSyncId` parcial en `Documents/log.txt` en texto plano.
- `dataSyncId` se extrae tras el login pero **no se persiste** (`LoginWebView.swift:124-141`) → se pierde al relanzar.
- `CookieStore` traga errores de keychain con `try?` (fallo de persistencia invisible).
- `MusixmatchProvider` embebe `app_id` de invitado y cachea el token para siempre sin expiry.

## D. Otras mejoras (menor)

- Letras: sin cache/rate-limit ni backoff (`LyricsHTTP` usa `URLSession.shared` en crudo); `GeniusProvider` parsea HTML a mano (frágil); `Kugou`/`LyricsHTTP` pierden la distinción 4xx/5xx/429.
- `FullPlayerView.activeLyricText` hace un scan O(n) en cada `body` (perf).
- `ImagePreloader` con throttle muerto; `SponsorBlock` borra todo el cache en vez de LRU.
- Varios `ForEach` con `id` por índice (rompen diffing/animaciones): `Detail/*`, `HomeScreenView`, `HistoryView`, `DownloadsView`.
- Localización incompleta (Settings, Search, Library, History con strings en inglés duro).

---

# Plan de migración Swift 5 → Swift 6 (lento)

Estado: `SWIFT_VERSION = 5.0`, sin `SWIFT_STRICT_CONCURRENCY`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`.

**Paso 1 — Lenguaje Swift 6 (bajo riesgo).**
`SWIFT_VERSION = 6.0`, mantener concurrencia en `minimal` y `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Arreglar errores del modo de lenguaje (API renombradas, `nonisolated(unsafe)` admisibles, checks más estrictos). Verificar en CI.

**Paso 2 — Strict concurrency progresivo (el trabajo real).**
Subir por módulos `SWIFT_STRICT_CONCURRENCY = complete` (se puede activar por target/file si fuera necesario), quitando `SWIFT_APPROACHABLE_CONCURRENCY`. Orden sugerido (de fácil a difícil):
1. `Networking`, `Auth`, `Database` (GRDB ya es actor-friendly), `Utilities`.
2. `Lyrics/Providers` (arreglar `Musixmatch.guestToken` global).
3. `Settings`/`Services`/`Home`/`Search` (marcar singletons `@MainActor`).
4. **`Audio`/`PlayerController`** (lo último y más duro: rediseñar el puente mpv con un actor dedicado o `@unchecked Sendable` con invariantes documentados; `OpaquePointer` via `Unmanaged`).

**Paso 3 — Limpieza post-migración.**
Quitar `nonisolated(unsafe)` sustituyéndolo por aislamiento real; `MainActor.assumeIsolated` solo donde esté garantizado.

Regla para no romper nada: **un cambio de concurrencia → un build de CI verde antes de pasar al siguiente.**
