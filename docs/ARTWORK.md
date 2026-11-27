# Artwork quality

Objetivo: la mejor resolución útil para cada superficie, sin descargar imágenes
gigantes para miniaturas.

## Medidas reales (27-nov)

| Fuente | Variante | Tamaño real |
|---|---|---|
| Apple/iTunes | `100x100` → `1200x1200` | 1200×1200, ~478 KB |
| Apple/iTunes | `2000x2000` | 2000×2000, ~1.1 MB |
| Apple/iTunes | `3000x3000` | 3000×3000, ~2.2 MB |
| Deezer | `picture_xl` artista | 1000×1000, ~142 KB |
| Podcast RSS (Simplecast) | `3000x3000` | 3000×3000, ~134 KB |
| Spotify GraphQL | coverArt sources | 64 / 300 / **640** (máx.) |
| Spotify GraphQL | headerImage artista | normalmente 1920+ |

Spotify **no permite pedir** una variante mayor que 640 de un cover: el hash es
fijo. La única forma de subir resolución es otra fuente (Apple/Deezer/RSS).

## Política por superficie

| Superficie | Tamaño útil | Fuente |
|---|---|---|
| Fila / mini | 160 px | Spotify 640 o rung de Apple |
| Card Home/Search | 480 px | Spotify 640 |
| Header de detalle | 720 px | Spotify 640 / Apple 1200 |
| Hero / player | 1200 px | Apple 1200, podcast RSS 1200 |
| Avatar artista | 640 px | Spotify; Deezer XL si hace falta |
| Portrait libro | 640 px | Spotify |

`ArtworkURLs.playerPx = 1200`; no hay superficie de la app que necesite 3000.

## Reglas implementadas

1. **Apple/iTunes**: 1200 px es la variante base. Se reescribe `100x100` →
   `1200x1200`; nunca se piden 2000/3000 para UI.
2. **`ArtworkURLs.highRes`**: para `mzstatic` sube a **1200**, no a 3000.
3. **`AsyncImageView`**: si la URL es `mzstatic`, reescribe sus dimensiones al
   **rung** de la vista (160/480/720/1200), así una fila no baja 1200.
4. **Álbum sin portada o <1000 px**: `CatalogEnricher` pide Apple y
   `ArtworkQuality.better` sustituye solo si mejora.
5. **Podcast**:
   - El RSS aporta `<itunes:image>` o `<image><url>` (a menudo 3000).
   - Se guarda en `PodcastFeedContent.artworkURL` y se sirve a **1200** en el
     detalle y en el episodio en reproducción.
6. **Fallback Deezer**: `cover_xl`/`picture_xl` 1000.
7. **Cache**: Nuke memoria 64 MB + disco 64 MB; rungs compartidos.

## Límites

- **Playlist cover**: Spotify solo 640; no hay API de portada de playlist en
  Apple/Deezer. Se queda en 640 (suficiente para cards; algo suave en hero).
- **Avatar Spotify**: 640; Deezer 1000 solo si se valida el artista. El header
  del artista sí es grande.
- **Audiolibros**: Spotify 640; iTunes no expone portada de audiolibro de forma
  fiable. Podría mejorarse con Google Books/Apple Books.
- **Artwork 3000**: no se usa en UI; solo ocuparía memoria y datos.

## Próximos pasos opcionales

- Upgrade de avatar de artista a Deezer XL/TheAudioDB con verificación.
- Portada de playlist vía collage de tracks (no es la portada real; no hacer).
- Portada de audiolibro vía Google Books/Apple Books si se consigue API.
- Cache de artwork RSS por show para Home, no solo detalle/reproducción.
