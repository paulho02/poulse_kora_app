import 'package:flutter_test/flutter_test.dart';
import 'package:peerkola/src/core/languages/language_detector.dart';

void main() {
  const detector = StopwordLanguageDetector();

  group('StopwordLanguageDetector', () {
    test('recognises ordinary English prose', () {
      expect(
        detector.detect(
          'I went to the shop this morning and there was nobody there, '
          'which is why I could get the last one they had.',
        ),
        'en',
      );
    });

    test('recognises ordinary German prose', () {
      expect(
        detector.detect(
          'Ich bin heute Morgen zum Laden gegangen und es war niemand da, '
          'deshalb konnte ich noch das letzte Stück bekommen.',
        ),
        'de',
      );
    });

    test('recognises German without any umlauts', () {
      // The umlaut bonus must be a nudge, not the mechanism - plenty of German
      // sentences contain none at all.
      expect(
        detector.detect(
          'Das ist ein Test ohne besondere Zeichen, damit wir sehen '
          'ob die Erkennung auch so funktioniert wie sie soll.',
        ),
        'de',
      );
    });

    test('abstains on text too short to judge', () {
      // Not "guesses badly" - null, so the picker stays where the author put it
      // instead of flickering while they type their first few words.
      expect(detector.detect('Hallo Welt'), isNull);
      expect(detector.detect(''), isNull);
      expect(detector.detect('   '), isNull);
    });

    test('answers on one short sentence', () {
      // The case the threshold exists to serve rather than block: a first post
      // is usually one line, and abstaining on it reads as the feature being
      // broken. `test/composer_language_test.dart` drives the same case through
      // the real screen.
      expect(detector.detect('Das ist ein Test'), 'de');
      expect(detector.detect('This is a test'), 'en');
    });

    test('still abstains on short text with no function words', () {
      // Proof the word count is not what does the work - the score and margin
      // are. These are all at or above the minimum length.
      expect(detector.detect('Berlin Hamburg Munich Cologne'), isNull);
      expect(detector.detect('Kaffee Kuchen Sonne Strand'), isNull);
    });

    test('abstains on text that is neither language', () {
      // Names, hashtags, code: no function words, so no answer. The author
      // picks, which is right - this text genuinely has no detectable language.
      expect(
        detector.detect(
          'Berlin Hamburg Munich Cologne Frankfurt Stuttgart '
          'Dortmund Essen Leipzig Bremen Dresden Hannover',
        ),
        isNull,
      );
    });

    test('abstains when a language it cannot score would be the answer', () {
      // A language configured on the backend before a stopword list exists here
      // degrades to "no suggestion", never to a wrong one.
      const french = StopwordLanguageDetector(candidates: ['fr']);
      expect(
        french.detect(
          'Je suis alle au magasin ce matin et il n y avait personne, '
          'donc j ai pu prendre le dernier.',
        ),
        isNull,
      );
    });

    test('an English sentence containing a German loanword stays English', () {
      // The umlaut bonus is worth about one word, so it cannot outvote a dozen
      // English function words.
      expect(
        detector.detect(
          'This is the über popular one that everybody has been talking '
          'about, and I would like to know why they all want it.',
        ),
        'en',
      );
    });

    test('only answers with a configured candidate', () {
      const englishOnly = StopwordLanguageDetector(candidates: ['en']);
      expect(
        englishOnly.detect(
          'Ich bin heute Morgen zum Laden gegangen und es war niemand da, '
          'deshalb konnte ich noch das letzte Stueck bekommen.',
        ),
        anyOf(isNull, 'en'),
      );
    });
  });

  group('stopword lists', () {
    test('share no words between languages', () {
      // The invariant, rather than any individual entry. A word in both lists
      // scores for both and separates nothing; worse, an ordinary English word
      // left in the German list ("an", "hat", "was") makes English prose read
      // as faintly German.
      final english = StopwordLanguageDetector.stopwordsFor('en')!;
      final german = StopwordLanguageDetector.stopwordsFor('de')!;
      expect(english.intersection(german), isEmpty);
    });

    test('are lowercase, since tokens are lowercased before lookup', () {
      for (final code in ['en', 'de']) {
        final words = StopwordLanguageDetector.stopwordsFor(code)!;
        expect(words.where((w) => w != w.toLowerCase()), isEmpty, reason: code);
      }
    });
  });
}
