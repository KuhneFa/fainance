/// Erkennt die Sprache der Buchungsdaten anhand typischer Begriffe.
/// Gibt 'de' oder 'en' zurück.
class LanguageDetector {
  static const _germanMarkers = [
    'gmbh',
    'danke',
    'beitrag',
    'überweisung',
    'lastschrift',
    'miete',
    'gehalt',
    'sparkasse',
    'volksbank',
    'drogerie',
    'buchung',
    'verwendungszweck',
    'gutschrift',
    'abbuchung',
    'rechnung',
    'zahlung',
    'monatsbeitrag',
    'einzug',
  ];

  static const _englishMarkers = [
    'payment',
    'transfer',
    'invoice',
    'subscription',
    'monthly',
    'direct debit',
    'salary',
    'deposit',
    'charge',
    'purchase',
    'refund',
    'fee',
    'balance',
    'credit',
    'debit',
  ];

  /// Analysiert eine Liste von Beschreibungen und gibt 'de' oder 'en' zurück.
  static String detect(List<String> descriptions) {
    var deScore = 0;
    var enScore = 0;

    for (final desc in descriptions) {
      final lower = desc.toLowerCase();
      for (final marker in _germanMarkers) {
        if (lower.contains(marker)) deScore++;
      }
      for (final marker in _englishMarkers) {
        if (lower.contains(marker)) enScore++;
      }
    }

    // Bei Gleichstand → Deutsch als Default
    return enScore > deScore ? 'en' : 'de';
  }
}
