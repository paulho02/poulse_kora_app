/// Guessing what language a post is written in, on-device.
///
/// This exists so the backend never has to read a post to route it. The server
/// cannot verify a declared language without doing exactly the work we are
/// avoiding, so the language a post carries is self-declared: the client
/// detects, **prefills the picker**, and the author can always override. Nothing
/// here decides anything — it only saves a tap.
///
/// [LanguageDetector] is the seam. The shipped implementation is a stopword
/// heuristic in pure Dart, chosen over an on-device ML model (Google's ML Kit
/// language-id) for three reasons: it discriminates between two well-separated
/// languages nearly perfectly, it is ~100 lines with no plugin, and it works on
/// Flutter **web**, which ML Kit does not. Swap the implementation at
/// `languageDetectorProvider` when the candidate set grows to languages that are
/// genuinely hard to separate; nothing outside this directory should change.
library;

/// Guesses the language of a piece of text.
abstract class LanguageDetector {
  /// The language code for [text], or **null** when there is no confident
  /// answer.
  ///
  /// Null is a real answer and callers must honour it by leaving the picker
  /// where it is. A detector that always guesses is worse than one that
  /// abstains: a wrong guess that the author does not notice routes the post to
  /// people who cannot read it, and the only correction left is those readers
  /// dropping it.
  String? detect(String text);
}

/// Counts how many of the text's words are function words of each candidate
/// language, and answers with the clear winner if there is one.
///
/// Function words ("the", "and", "ist", "nicht") are the right signal because
/// they are frequent, short, and almost never shared across languages, so even
/// a couple of sentences separates English from German decisively. Content
/// words are useless for this — loanwords, names and technical terms look the
/// same in both.
class StopwordLanguageDetector implements LanguageDetector {
  const StopwordLanguageDetector({
    this.candidates = const ['en', 'de'],
    this.minimumWords = 4,
    this.minimumScore = 0.10,
    this.minimumMargin = 0.06,
  });

  /// Languages this detector may answer with — in practice the server's
  /// `content_languages` (see `PublicAppConfig`), so the picker, the values the
  /// API accepts and what this can return cannot drift apart.
  ///
  /// A candidate with no stopword list in [_stopwords] is simply never returned.
  /// That is the deliberate failure mode for a language added to the backend
  /// before a list is added here: detection abstains and the author picks, which
  /// is a missing convenience rather than a wrong answer.
  final List<String> candidates;

  /// Below this many words, abstain outright.
  ///
  /// Four, not eight. Eight was tuned for reliability in isolation and was
  /// wrong in the app: a first post is routinely one short line ("Hallo, das
  /// ist mein erster Post hier" is seven words), so the detector abstained on
  /// exactly the posts people write and the feature read as broken rather than
  /// as cautious. Four still abstains on the things that genuinely have no
  /// language — a list of names, "lol", "nice one" — because [minimumScore] and
  /// [minimumMargin] do that work, not the word count. At four words a single
  /// German article already carries the score, which is the point: function
  /// words are dense enough that a short sentence is plenty of evidence.
  final int minimumWords;

  /// The winning language must account for at least this share of the words.
  /// Ordinary prose runs 30-50% function words; a paragraph of names, hashtags
  /// or code hits neither language and correctly gets no answer.
  final double minimumScore;

  /// ...and must beat the runner-up by at least this much. What this rejects is
  /// text sitting between two languages — a quote, a mixed-language caption —
  /// where picking either would be a coin flip presented as a fact.
  final double minimumMargin;

  @override
  String? detect(String text) {
    final words = _words(text);
    if (words.length < minimumWords) return null;

    final scores = <String, double>{};
    for (final code in candidates) {
      final stopwords = _stopwords[code];
      if (stopwords == null) continue;
      final hits = words.where(stopwords.contains).length;
      scores[code] = hits / words.length;
    }
    if (scores.isEmpty) return null;

    // Umlauts and ß are a strong positive signal for German and appear in
    // English only in loanwords. Additive rather than decisive: "über" in an
    // otherwise English sentence must not outvote a dozen English function
    // words, so it is worth about one extra word's weight.
    if (scores.containsKey('de') && _germanLetters.hasMatch(text)) {
      scores['de'] = scores['de']! + (1 / words.length);
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    if (best.value < minimumScore) return null;
    final runnerUp = ranked.length > 1 ? ranked[1].value : 0.0;
    if (best.value - runnerUp < minimumMargin) return null;
    return best.key;
  }

  /// Lowercased word tokens. Splits on anything that is not a letter or an
  /// apostrophe, so "don't" stays one word while "well-known" becomes two —
  /// both of which are what the stopword lists expect.
  static List<String> _words(String text) => text
      .toLowerCase()
      .split(_notWord)
      .where((word) => word.isNotEmpty)
      .toList();

  /// The function-word list for [code], or null if this detector has none and
  /// therefore can never answer with it. Exposed for tests, which assert the
  /// lists stay disjoint — the one property that keeps the scores meaningful.
  static Set<String>? stopwordsFor(String code) => _stopwords[code];

  static final _notWord = RegExp(r"[^\p{L}']+", unicode: true);
  static final _germanLetters = RegExp('[äöüßÄÖÜ]');
}

/// Function words per language. Not exhaustive vocabularies — these are the
/// closed-class words (articles, pronouns, prepositions, auxiliaries,
/// conjunctions) a sentence cannot avoid, which is what makes a short sample
/// enough.
///
/// Words that exist in both languages are deliberately **excluded from both**
/// rather than counted for each: "in", "so", "man", "war", "die", "am", "an",
/// "hat", "was", "gut", "bin" and friends are either shared spellings or common
/// false friends, and leaving them in adds noise to both scores without
/// separating anything. Scoring "an" or "hat" for German is worse than dropping
/// them, because it makes ordinary English prose look faintly German.
/// `test/language_detector_test.dart` asserts the lists stay disjoint — that is
/// the invariant, not the individual entries.
const _stopwords = <String, Set<String>>{
  'en': {
    'the', 'and', 'that', 'have', 'for', 'not', 'with', 'you', 'this', 'but',
    'his', 'from', 'they', 'say', 'her', 'she', 'will', 'one', 'all', 'would',
    'there', 'their', 'what', 'out', 'about', 'who', 'get', 'which', 'when',
    'make', 'like', 'time', 'just', 'him', 'know', 'take', 'into', 'your',
    'some', 'could', 'them', 'than', 'then', 'now', 'only', 'its', 'also',
    'back', 'after', 'how', 'our', 'well', 'even', 'because', 'any', 'these',
    'give', 'most', 'us', 'is', 'are', 'was', 'were', 'been', 'being', 'has',
    'had', 'does', 'did', 'doing', 'should', 'might', 'must', 'shall', 'few',
    'while', 'where', 'why', 'both', 'each', 'other', 'such', 'over', 'under',
    'again', 'very', 'much', 'many', 'here', 'through', 'between', 'against',
    'off', 'own', 'same', 'too', 'once', 'still', 'never', 'always',
  },
  'de': {
    'der', 'und', 'den', 'von', 'zu', 'das', 'mit', 'sich', 'des', 'auf',
    'für', 'ist', 'nicht', 'ein', 'eine', 'als', 'auch', 'es', 'werden',
    'aus', 'er', 'dass', 'sie', 'nach', 'wird', 'bei', 'einer', 'um',
    'noch', 'wie', 'einem', 'über', 'einen', 'aber', 'oder', 'zur', 'bis',
    'mehr', 'durch', 'schon', 'wenn', 'nur', 'wir', 'wieder', 'einige',
    'ihre', 'zum', 'vor', 'ganz', 'diese', 'nun', 'weil', 'ihm', 'immer',
    'sein', 'seine', 'ihr', 'ihn', 'dann', 'unter', 'sehr', 'selbst', 'ihnen',
    'hier', 'doch', 'dort', 'jetzt', 'etwas', 'nichts', 'alles', 'ohne',
    'gegen', 'zwischen', 'während', 'kann', 'können', 'muss', 'müssen', 'soll',
    'sollen', 'darf', 'dürfen', 'habe', 'haben', 'hatte', 'hatten', 'wurde',
    'wurden', 'sind', 'waren', 'ich', 'du', 'wer', 'wo', 'warum', 'welche',
    'dieser', 'jeder', 'alle', 'viele', 'wenig', 'nein', 'ja', 'mal',
  },
};
