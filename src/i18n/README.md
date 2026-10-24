# Translations

Quickshell loads rishot through a plain `QQmlEngine` and never installs a
`QTranslator`, so `qsTr()` and `.qm` catalogues cannot work. rishot therefore
ships plain JSON catalogues read at runtime by the `I18n` singleton
(`src/Singletons/I18n.qml`).

## Files

- `languages.json`: the manifest. Every catalogue must be listed here so the
  settings panel can offer it and the tests know what to validate.
- `<code>.json`: one flat map of dotted keys per language. `en.json` is the
  source of truth; every other catalogue must keep the same keys and the same
  `{placeholders}`.

## Key conventions

- Flat, lowercase, dot separated: `tooltip.copy`, `notify.screenshot_saved`,
  `settings.group.shortcut`. Use `snake_case` inside a segment, never camelCase.
- One key per sentence or label. Do not build sentences by concatenating
  fragments; pass values through `{name}` placeholders instead.
- Never translate the product name, tool ids, keyboard shortcut names
  (`Ctrl+S`), file names or paths.
- `settings.title` is the whole heading, brand included: `"{brand} settings"`
  in English, `"Ajustes de {brand}"` in Spanish. The panel passes the styled
  brand as the `{brand}` parameter so word order can change per language.
- No plural forms yet. If a string needs one, add `_one`/`_other` keys and
  extend `lib/i18n.js` at the same time.

## Language resolution

`I18n` builds the language in this order:

1. `Config.language` when it names a catalogue in the manifest (the settings
   panel writes it; `""` means automatic).
2. `RISHOT_LANG`.
3. `LANGUAGE`, `LC_ALL`, `LC_MESSAGES`, `LANG`, in that order.
4. English.

A regional tag falls back to its language (`es_AR` uses `es` when there is no
`es_AR.json`). An unknown locale falls back to English.

## Adding a language

1. Copy `en.json` to `<code>.json` and translate the values, keeping keys and
   placeholders untouched.
2. Add `{ "code": "<code>", "name": "<endonym>" }` to `languages.json` (use the
   language's own name, e.g. `Español`).
3. Run `sh src/lib/run-tests.sh`; `translations.test.mjs` checks JSON validity,
   key parity, placeholder parity, duplicate keys and the manifest.

## Trying a translation

```sh
RISHOT_LANG=es bin/rishot
RISHOT_LANG=es qs -p src   # run the config in place during development
```

Missing keys fall back to English and are logged once with
`rishot: missing translation key: <key>`.
