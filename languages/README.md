# Apollo translations

The app declares English (`en`), Spanish (`es`), French (`fr`), Brazilian
Portuguese (`pt-BR`) and Chinese (`zh`, simplified characters). iOS chooses among them using the user's app language settings.
English is the development language and fallback.

Edit the JSON catalogs in this directory, then run:

```sh
python3 scripts/generate_localizations.py
python3 scripts/test_localizations.py
```

`Apollo/Resources/*/Localizable.strings` are generated. Do not edit them directly.
Counted labels use `Localizable.stringsdict` in each language directory. Keep
those plural rules in sync with `AppStrings.swift` and the JSON fallback text.
The checks do not compile or launch the app.

## Writing translations

- Write natural interface copy, not word-for-word translations. Keep actions
  concise and explain failures in language a listener can act on.
- Use neutral Spanish consistently: “Biblioteca”, “Reproducir a continuación”,
  “Accesos rápidos”, “Sin pérdida” and “Descargas”.
- Use natural French interface terms: “Bibliothèque”, “Écouter ensuite”,
  “Sélection rapide” and “Sans perte”. Address the listener with “vous”.
- Use Brazilian Portuguese: “Configurações”, “Reproduzir a seguir”,
  “Músicas curtidas”, “Baixar” and “Sem perdas”. Avoid European Portuguese
  terms such as “ficheiro”, “ecrã” or “transferir” for downloads.
- Preserve provider names and technical identifiers such as FLAC, Qobuz and
  Last.fm. Song titles, artist names and fetched descriptions are content.
- Preserve printf argument types (`%@`, `%ld`) and escaped percentages (`%%`).
  Use numbered arguments when a translation needs to change argument order.
- Localize a complete sentence before inserting a title, name or number.
  Do not assemble English fragments and attempt to translate them separately.
- `Text("literal")` can use SwiftUI localization. App-owned keys stored in
  variables need `LocalizedStringKey`; dynamic messages outside SwiftUI need
  `String(localized:)` or `AppStrings.format`. Do not treat fetched content as
  a localization key.
- Use `AppStrings` and plural resources for counts, not an English `s` suffix.

Before release, inspect Home, Search, Settings, playback, VoiceOver labels,
errors, and singular/plural counts on an iPhone in each language. Check long
French, Spanish and Portuguese labels and large text sizes for clipping. Automated catalog and syntax
checks do not replace that visual review.
