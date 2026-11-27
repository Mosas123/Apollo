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
- [ ] `AppleCatalogClient` (iTunes Search): artwork de alta resolución, género,
      fecha; nunca sustituye artistas de Spotify.
- [ ] Fotos de artista: **Spotify → Deezer → placeholder**; sin prioridad de
      YouTube. (iTunes público no da foto de artista; Apple Music API sí, con
      token de developer.)
- [ ] Portada de álbum: Apple/iTunes → Spotify → Deezer.
- [ ] Arreglar podcasts vacíos en Home: revisar shapes `show/episode` del feed y
      de search; añadir diagnóstico.

### Fase 2 — Identidad y deduplicación
- [ ] Clave canónica: ISRC/MBID primero.
- [ ] Huella secundaria: título normalizado + artistas + duración ±2 s +
      álbum/año.
- [ ] Reglas para no fusionar remix/live/remaster/versiones explícitas.
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
- [ ] Abstracción `AudioProvider` (YouTube/add-ons) separada del catálogo.
- [ ] Matching por ISRC → título/artista/duración.
- [ ] Fallback y disponibilidad por región.
- [ ] Sin metadatos de YouTube en la UI nueva.

### Fase 6 — Cierre
- [ ] Eliminar rutas legacy de catálogo YT.
- [ ] Revisión de rendimiento, caché y cuotas.
- [ ] QA en dispositivo y build final.

## Estado actual

- Rama: `feat/spotify-catalog`.
- Build de referencia: 877 (compila).
- Pendiente inmediato: fotos Spotify-first, iTunes artwork/ISRC y bug de
  podcasts vacíos.
