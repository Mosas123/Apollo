# Catálogo canónico y fusión de proveedores

Objetivo: un solo catálogo de Apollo que use **lo mejor de cada proveedor**, sin
depender de YouTube Music para metadatos y con YouTube únicamente como audio.

## Principios

1. **Spotify es la columna vertebral del catálogo** (descubrimiento, artistas,
   colaboraciones, playlists, podcasts y audiolibros).
2. **Los campos se eligen por proveedor**, no por un único ganador:
   artistas/colaboraciones de Spotify, artwork de Apple/iTunes, ISRC de
   Apple/MusicBrainz, géneros de Apple/Spotify, audio de YouTube/add-ons.
3. **Nada bloquea la UI**: se responde con la fuente primaria y se enriquece en
   segundo plano.
4. **YouTube solo resuelve audio**. No se usa para fotos, portadas, géneros ni
   búsqueda de catálogo nuevo.
5. **Library local-first**: favoritos, guardados, follows, playlists e historial
   viven en la DB del dispositivo. Una cuenta de Spotify, si se añade, solo
   importa datos; no es obligatoria.

## Prioridad por campo

| Campo | Primero | Fallback |
|---|---|---|
| Título | Spotify | Apple/iTunes |
| Artistas y colaboraciones | Spotify (`artists[]`) | Apple Music API |
| Álbum / tipo | Spotify | Apple/iTunes |
| ISRC / MBID | Apple Music API / MusicBrainz | Spotify Web API |
| Portada | Apple (hasta 3000 px) | Spotify → Deezer/iTunes |
| Fecha de lanzamiento | Apple/iTunes | Spotify → MusicBrainz |
| Géneros / tags | Apple/iTunes | Spotify → Last.fm |
| Créditos | MusicBrainz | Apple Music API |
| Bio / relacionados | Spotify | MusicBrainz/Last.fm |
| Podcasts | Spotify | PodcastIndex/iTunes |
| Audiolibros | Spotify | fuente de audiolibros (TBD) |
| Disponibilidad de audio | YouTube | add-ons |

## Fases

### Fase 0 — Base (en curso)
- [x] Modelos de catálogo independientes del proveedor.
- [x] Cliente anónimo de Spotify (TOTP + GraphQL).
- [x] Catálogo Spotify en Home, Search, Explore, fichas, podcasts y audiolibros.
- [x] Library local (likes, guardados, follows, playlists, historial).
- [x] Canvas y login de YouTube eliminados.
- [ ] Registro de proveedores con prioridad y procedencia por campo.
- [ ] Caché de catálogo canónico.

### Fase 1 — Enriquecedores pequeños
- [x] `AppleCatalogClient` (iTunes Search): artwork de alta resolución, género,
      fecha; nunca sustituye artistas de Spotify. (falta conectarlo al enriquecedor)
- [x] Fotos de artista: **Spotify → Deezer → placeholder**; sin prioridad de
      YouTube. (iTunes público no da foto de artista; Apple Music API sí, con
      token de developer.)
- [ ] Portada de álbum: Apple/iTunes → Spotify → Deezer.
- [x] Podcasts/Audiobooks: si el home feed no trae secciones, se siembran con
      búsquedas de Spotify (podcasts, true crime, comedy, news, audiobooks…).

### Fase 2 — Identidad y deduplicación
- [x] MusicBrainz ISRC/MBID (rate limit 1 req/s, caché 24 h).
- [x] Persistir identidad/enriquecimiento en DB (`catalog_identity`, migración v10).
- [x] Clave canónica: ISRC → MBID → fallback título/artista/duración (en memoria).
- [ ] Huella secundaria: título normalizado + artistas + duración ±2 s +
      álbum/año.
- [x] Reglas para no fusionar remix/live/remaster/sped up/demo/version sin ISRC/MBID.
- [ ] Resolver IDs entre Spotify, Apple, YouTube y add-ons.

### Fase 3 — Enriquecimiento asíncrono
- [ ] Cola de enriquecimiento con prioridad y rate limits.
- [ ] Caché en memoria, disco y DB con TTL por campo.
- [ ] Procedencia visible y atribución legal.
- [ ] Reintentos y circuit breaker por proveedor.

### Fase 4 — Descubrimiento combinado
- [ ] Home/Explore con secciones de Spotify y huecos rellenados por Apple.
- [ ] Charts/recomendaciones multi-proveedor.
- [ ] Podcasts/audiolibros con providers propios además de Spotify.

### Fase 5 — Audio
- [x] Fallback integrado: YouTube → JioSaavn/Audius (lossy) → Qobuz/add-ons (lossless) respetando el quality mode.
- [ ] Abstracción formal `AudioProvider` y matching por ISRC.
- [ ] Matching por ISRC → título/artista/duración (hoy se usa título/artista/duración).
- [ ] Fallback y disponibilidad por región.
- [ ] Sin metadatos de YouTube en la UI nueva.

### Fase 6 — Cierre
- [ ] Eliminar rutas legacy de catálogo YT.
- [ ] Revisión de rendimiento, caché y cuotas.
- [ ] QA en dispositivo y build final.

## Estado actual

- Rama: `feat/spotify-catalog`.
- Build de referencia: 877 (compila).
- Pendiente inmediato: conectar el enriquecedor (Apple/MusicBrainz) a las
  vistas y al catálogo en segundo plano.
