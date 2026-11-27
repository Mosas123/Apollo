#!/usr/bin/env python3
"""Read-only localization checks; does not build or launch the iOS app."""
import json
import plistlib
import re
import tempfile
import unittest
from pathlib import Path

import generate_localizations as generator

ROOT = Path(__file__).resolve().parent.parent
LOCALES = ('en', 'es', 'fr', 'pt-BR', 'zh')


class LocalizationTests(unittest.TestCase):
    def setUp(self):
        self.catalogs = {
            locale: generator.read_language(ROOT / 'languages' / f'{locale}.json')
            for locale in LOCALES
        }

    def test_catalogs_have_the_same_keys(self):
        for locale, values in self.catalogs.items():
            with self.subTest(locale=locale):
                self.assertEqual(set(values), set(self.catalogs['en']))
                self.assertTrue(all(value.strip() for key, value in values.items() if key.strip()))

    def test_format_arguments_match_english(self):
        for locale, values in self.catalogs.items():
            for key, value in values.items():
                with self.subTest(locale=locale, key=key):
                    self.assertEqual(generator.format_arguments(value),
                                     generator.format_arguments(self.catalogs['en'][key]))

    def test_generated_resources_are_current(self):
        for locale, values in self.catalogs.items():
            path = ROOT / 'Apollo' / 'Resources' / f'{locale}.lproj' / 'Localizable.strings'
            with self.subTest(locale=locale):
                self.assertEqual(path.read_text(), generator.render_strings(values))

    def test_plural_resources(self):
        for locale in LOCALES:
            path = ROOT / 'Apollo' / 'Resources' / f'{locale}.lproj' / 'Localizable.stringsdict'
            entries = plistlib.loads(path.read_bytes())
            for key in ('songs.count', 'offline_tracks.count', 'episodes.count'):
                with self.subTest(locale=locale, key=key):
                    self.assertEqual(entries[key]['NSStringLocalizedFormatKey'], '%#@count@')
                    count = entries[key]['count']
                    self.assertEqual(count['NSStringFormatSpecTypeKey'], 'NSStringPluralRuleType')
                    self.assertEqual(count['NSStringFormatValueTypeKey'], 'ld')
                    self.assertIn('other', count)
                    if locale != 'zh':
                        self.assertIn('one', count)
                        self.assertNotEqual(count['one'], count['other'])
                    for rule, text in count.items():
                        if rule.startswith('NSString'):
                            continue
                        self.assertEqual(generator.format_arguments(text), generator.format_arguments('%ld'))

    def test_declared_languages(self):
        project = (ROOT / 'Apollo.xcodeproj' / 'project.pbxproj').read_text()
        regions = re.search(r'knownRegions = \((.*?)\);', project, re.S).group(1)
        for locale in LOCALES:
            self.assertIn(locale, [item.strip().strip(chr(34)) for item in regions.split(',')])

    def test_no_accidental_chinese_in_spanish(self):
        for key, value in self.catalogs['es'].items():
            with self.subTest(key=key):
                self.assertNotRegex(value, r'[\u4e00-\u9fff]')

    def test_static_ui_literals_have_catalog_entries(self):
        literal = r'"(?:[^"\\]|\\.)*"'
        sequence = literal + r'(?:\s*\+\s*' + literal + r')*'
        pattern = re.compile(
            r'\b(?:Text|Label|Button|Toggle|Section|Picker|TextField|SecureField|ProgressView|LabeledContent|'
            r'SettingsNavigationRow|SettingsToggleRow|SettingsPickerRow|SettingsStepperRow|NSLocalizedString|'
            r'LocalizedStringKey)\(\s*(' + sequence + r')'
            r'|\.(?:navigationTitle|accessibilityLabel|alert|confirmationDialog|destructiveConfirm)\(\s*(' + sequence + r')'
            r'|String\(localized:\s*(' + sequence + r')'
            r'|AppStrings\.format\(\s*(' + sequence + r')'
        )
        for path in (ROOT / 'Apollo').rglob('*.swift'):
            for match in pattern.finditer(path.read_text()):
                raw = next(group for group in match.groups() if group is not None)
                # Interpolation and fetched content require a context-aware audit.
                if '\\(' in raw:
                    continue
                try:
                    key = ''.join(json.loads(part) for part in re.findall(literal, raw))
                except ValueError:
                    continue
                if not any(character.isalpha() for character in key):
                    continue
                with self.subTest(path=str(path.relative_to(ROOT)), key=key):
                    self.assertTrue(key in self.catalogs['en'], f'Missing UI translation key: {key!r}')

    def test_format_validation_supports_reordering_and_literal_percent(self):
        self.assertEqual(generator.format_arguments('%@ — %ld%%'),
                         generator.format_arguments('%2$ld%%：%1$@'))
        self.assertNotEqual(generator.format_arguments('%@'), generator.format_arguments('%ld'))
        self.assertEqual(generator.format_arguments('100%%'), {})

    def test_duplicate_keys_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'test.json'
            path.write_text('{"Play": "Play", "Play": "Reproducir"}')
            with self.assertRaisesRegex(ValueError, 'duplicate translation key'):
                generator.read_language(path)

    def test_strings_escaping(self):
        self.assertEqual(generator.escape_strings_value('"Song"\n\\path'), '\\"Song\\"\\n\\\\path')


if __name__ == '__main__':
    unittest.main()
