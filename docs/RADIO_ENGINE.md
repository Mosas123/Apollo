# Apollo Radio Engine

Objetivo: una radio propia, explicable y local-first que no dependa del catálogo
de YouTube Music. Primero un ranker determinista y bueno; después IA.

## 1. Principios

- **Semilla clara**: track, artista, álbum, playlist, género o “para ti”.
- **Explicable**: cada recomendación tiene un motivo (mismo artista, similar,
  género, gustó, novedad…).
- **Diversa**: no repetir artista/álbum en ventanas cortas.
- **Respetuosa**: calidad, explícito, disponibilidad de audio y país.
- **Local-first**: el perfil y los eventos viven en el dispositivo.
- **Sin features de audio de Spotify**: usaremos metadata, tags, relaciones y
  embeddings propios.

## 2. Señales

### Del catálogo
- Artista(s), álbum, año, género/topics, duración, explícito.
- Top tracks del artista y orden de popularidad.
- Artistas relacionados (Spotify `relatedArtists`).
- Tags/similitud de Last.fm / MusicBrainz.
- Co-ocurrencia en playlists/editorial.

### Del usuario (local)
- Likes, guardados, follows, playlists.
- Reproducciones completas, skips, repeticiones, hora del día.
- Artistas/géneros con afinidad.
- Historial reciente y ventana de “no repetir”.

### De disponibilidad
- Proveedores con audio para la pista y calidad disponible.
- Región/país y restricciones.

## 3. Generación de candidatos (recall)

| Fuente | Uso |
|---|---|
| Top tracks del artista semilla | Núcleo del artista |
| Álbum/EPs del artista | Deep cuts |
| Artistas relacionados Spotify | Descubrimiento cercano |
| Last.fm `track.getSimilar` / `artist.getSimilar` | Variedad externa |
| Tags/géneros (Spotify/Last.fm) | Estaciones por mood |
| Playlists editoriales/co-ocurrencia | Puentes entre artistas |
| Likes/historial local | Familiaridad |
| Audius trending | Electrónica/indie |
| Search por género | Cold start de género |

Cada candidato guarda **procedencia** y se deduplica por `CatalogIdentity`
(ISRC → MBID → título/artista/duración + edición).

## 4. Ranking v1 (sin IA)

Score inicial:

```
score = 0.30 * artistAffinity
      + 0.20 * relatedArtistScore
      + 0.15 * genreOverlap
      + 0.10 * eraProximity
      + 0.10 * localAffinity
      + 0.08 * popularity
      + 0.07 * novelty
      - 0.25 * repeatPenalty
      - 0.20 * skipPenalty
      - explicitPenalty
```

- `artistAffinity`: historial/likes/follows del artista.
- `relatedArtistScore`: fuerza de la relación (orden de related/similar).
- `genreOverlap`: Jaccard de tags/géneros.
- `eraProximity`: cercanía de año (suave, no rígida).
- `localAffinity`: plays/saves locales, con decaimiento temporal.
- `popularity`: orden de top tracks (proxy, no contador absoluto).
- `novelty`: no escuchado recientemente / artista nuevo.
- `repeatPenalty`: mismo artista/álbum en ventana de N pistas.
- `skipPenalty`: skips recientes del artista/tema.

Después, **MMR/diversificación**:

```
MMR = λ * relevance - (1-λ) * maxSimilarityToSelected
```

- λ≈0.75 para radio normal; 0.6 para “variety”; 0.85 para “deep cuts”.
- Ventana mínima de artista (p. ej. 3 pistas) y álbum (8).

## 5. Feedback

- Registrar: play, play>30s, complete, skip<10s, like, save, repeat.
- Actualizar afinidades con **decaimiento exponencial** (vida media 14–30 días).
- Skips repetidos bajan al artista/tema; completions y saves suben.
- Todo local; exportable/borrable por el usuario.

## 6. Cold start

- Sin historial: radio por artista/track usando top tracks + relacionados.
- Sin artista: género/tag + editorial.
- Sin nada: “Apollo’s pick” + top del home.
- País/mercado para filtrar disponibilidad.

## 7. IA (fase posterior)

1. **Embeddings de metadata** (título/artista/álbum/tags) para similitud
   semántica; almacenar vectores localmente o generarlos on-device.
2. **Learning-to-rank** con feedback local (pairwise: completado vs skipped).
3. **Contextual bandits** para explorar/explotar por sesión.
4. **LLM opcional** solo para explicaciones o estaciones en lenguaje natural,
   nunca para decidir disponibilidad/calidad.

## 8. Arquitectura

```
StationService (actor)
 ├─ SeedResolver        (track/artist/album/genre → IDs canónicos)
 ├─ CandidateSources[]  (Spotify, LastFM, Local, Audius, Editorial)
 ├─ CatalogIdentity     (dedupe y merge)
 ├─ StationRanker       (score + MMR)
 ├─ AvailabilityFilter  (audio providers + calidad + región)
 └─ StationCache        (por seed/opciones, TTL)
```

`StationService` devuelve `[SongItem]` (IDs namespaced), y el audio se resuelve
con el pipeline actual.

## 9. Evaluación

- **Offline**: diversidad de artistas, repetición, novedad, cobertura,
  latencia, % de candidatos con audio disponible.
- **Online local**: skip rate, completion, save rate, repeat rate.
- **A/B local** por `RadioOptions` (similar/variety/deepCuts).
- Golden tests con seeds fijos y catálogo cacheado.

## 10. Fases

### R0 — Datos y feedback
- [x] Señales play/skip/complete/like vía `TasteProfileStore` (persistidas, con decaimiento).
- [x] Afinidades por artista/género y penalización por skips en el ranker.
- [x] Ventanas de “no repetir” configurables en Customize Radio (artista/álbum).

### R1 — StationService v1 (sin IA)
- [x] Seed track/artist.
- [x] Candidatos: top tracks, álbum, related artists.
- [x] Ranker ponderado + diversidad por artista/álbum.
- [x] Filtro de explícito; calidad/availability delegadas al playback.
- [x] Start Radio, Similar y autoplay sin radio de YouTube.

### R2 — Más recall
- [x] Last.fm `track.getSimilar` (solo API key, cache 24 h).
- [x] `artist.getSimilar` para ampliar artistas relacionados.
- [ ] Estaciones por mood/tags.
- [ ] Co-ocurrencia/editorial.
- [ ] Local taste y “para ti”.

### R3 — Evaluación y ajuste
- [x] Métricas locales por estación (candidatos, diversidad, repetición, latencia, mix de fuentes) y pantalla de diagnóstico.
- [x] Pesos por estilo y límites de repetición.
- [x] Cache de estaciones (10 min).
- [ ] Golden tests automáticos.
- [ ] Prefetch de la siguiente estación.

### R4 — IA
- [x] Embeddings de metadata on-device (`NLEmbedding`) como feature de similitud.
- [x] Learning-to-rank online local: pesos por estilo que aprenden de completions/skips/likes.
- [x] Bandit Beta por fuente/estilo (multiplicador 0.85–1.15) con feedback local.
- [x] Contexto de sesión v1: refuerzo por artistas/álbumes recientes en la cola.
- [ ] Modelo secuencial neuronal (SASRec/GRU).
- [ ] Explicaciones generadas (opcional).

## 11. Estado y pendientes (27-nov)

### Hecho
- Seed track/artist con resolución vía Spotify (también para seeds YouTube).
- Candidatos: top tracks, álbum, relacionados Spotify, Last.fm track/artist similar.
- Taste local: plays, skips, completions, likes, follows, géneros.
- Ranker con diversidad por artista/álbum y filtros de explícito/skips.
- Embeddings on-device y learning-to-rank online por estilo.
- Start Radio / Similar / autoplay / Surprise sin radio de YouTube.
- Diagnóstico local (Settings → Radio diagnostics) y explicaciones en cola.

### Pendiente
- [x] Señales de feedback locales vía TasteProfileStore + DB (event store propio pendiente).
- [ ] Tags/géneros normalizados por identidad para similitud y mood.
- [ ] Co-ocurrencia/editorial y estaciones por mood.
- [ ] Golden tests automáticos y cobertura de audio por candidato.
- [ ] Prefetch de la siguiente estación.
- [ ] Bandits contextuales.
- [ ] Modelo de secuencia de sesión (SASRec/GRU pequeño on-device).
- [ ] Explicaciones generadas con LLM/Foundation Models.
- [x] Ventanas de “no repetir” configurables en Customize Radio (artista/álbum).

## 12. Backlog de ideas avanzadas

Prioridad alta:
1. **Pesos de señal finos**: play>30s, completion, like/save, repeat, skip<10s,
   skip tardío neutro, añadir a playlist. Contexto por hora/dispositivo.
2. **Grafo de gusto personal**: artistas/géneros/álbumes/eras/moods, propagación
   tipo PageRank desde likes/plays.
3. **Co-ocurrencia pública sin backend**: playlists públicas/editorial,
   ListenBrainz, Last.fm, MusicBrainz para item-item similarity.
4. **Retrieval con embeddings + ANN local**: “user tower” con historial
   ponderado + contexto; “item tower” con metadata.
5. **LTR pairwise**: pares completado vs skip; sustituir el logístico simple.
6. **Bandits** (Thompson/LinUCB) para fuente, novedad y exploración.
7. **Calibración/diversidad**: MMR/DPP, cuotas de género/era/idioma, dial
   familiar ↔ descubrir.

Prioridad media:
8. **Modelo secuencial de sesión**: últimas 5–10 pistas; detectar intención.
9. **Online learning con caducidad** (estilo Monolith): TTL/frecuencia por
   entidad y actualización inmediata.
10. **Taste fingerprint**: energía/acústica/era/idioma/popularidad/mood
    inferidos de tags, no de audio features.
11. **Negativo explícito y contextual**: “no este artista por un tiempo”, skips
    por contexto.
12. **Arcos de sesión**: warmup → peak → cooldown.

Prioridad baja / experimental:
13. **LLM/Foundation Models** para intención en lenguaje natural y
    explicaciones; verificar siempre contra el catálogo.
14. **Cold start onboarding** con 3–5 artistas/géneros + charts/editorial.
15. **Datos públicos**: ListenBrainz para señales colaborativas sin subir datos
    del usuario; MusicBrainz/Last.fm para tags y relaciones.

Métricas:
- Offline: NDCG, recall@k, cobertura, diversidad, novedad, intra-list
  similarity, calibración.
- Online local: skip<10s, completion, save, repeat, duración de sesión.
- Guardrails: repetición por artista/álbum, explícito, calidad, disponibilidad.
