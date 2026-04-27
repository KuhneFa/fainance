import '../core/models.dart';

// ── Kategorien ────────────────────────────────────────────────────────────────
// Exakt dieselbe Liste wie im Python-Backend — Single Source of Truth
// wird später aus einer shared JSON-Datei geladen.
const validCategories = {
  'Lebensmittel',
  'Miete',
  'Sparen / Investieren',
  'Drogerie',
  'Sport',
  'Freizeit & Freunde',
  'Geschenke',
  'Transport',
  'Versicherungen',
  'Gesundheit',
  'Unterhaltung',
  'Sonstiges',
};

// ── Keyword-Regeln ────────────────────────────────────────────────────────────
// Reihenfolge ist wichtig — erste Übereinstimmung gewinnt.
const _keywordRules = <String, List<String>>{
  'Miete': [
    'miete',
    'warmmiete',
    'kaltmiete',
    'nebenkosten',
    'hausgeld',
    'wohnungsmiete',
  ],
  'Sparen / Investieren': [
    'sparplan',
    'etf',
    'depot',
    'investition',
    'aktien',
    'trade republic',
    'scalable',
    'tagesgeld',
    'festgeld',
    'comdirect depot',
    'ing-diba depot',
  ],
  'Lebensmittel': [
    'rewe',
    'edeka',
    'aldi',
    'lidl',
    'penny',
    'netto',
    'kaufland',
    'tegut',
    'norma',
    'nahkauf',
    'backerei',
    'bäckerei',
    'metzgerei',
    'bioladen',
    'denns',
    'supermarkt',
  ],
  'Drogerie': [
    'dm ',
    'dm-',
    'rossmann',
    'müller drogerie',
    'budni',
    'drogerie',
    'douglas',
    'parfümerie',
  ],
  'Sport': [
    'fitnessstudio',
    'fitness',
    'mcfit',
    'clever fit',
    'planet fitness',
    'sportverein',
    'schwimmbad',
    'tennis',
    'yoga',
    'pilates',
    'decathlon',
    'intersport',
  ],
  'Transport': [
    'deutsche bahn',
    'db bahn',
    'mvv',
    'hvv',
    'bvg',
    'rheinbahn',
    'tankstelle',
    'shell',
    'aral',
    'esso',
    'uber',
    'taxi',
    'flixbus',
    'parken',
    'parkhaus',
  ],
  'Unterhaltung': [
    'netflix',
    'spotify',
    'amazon prime',
    'disney+',
    'apple tv',
    'youtube premium',
    'dazn',
    'sky ',
    'kino',
    'cinema',
    'theater',
    'konzert',
    'steam',
  ],
  'Gesundheit': [
    'apotheke',
    'arzt',
    'arztpraxis',
    'krankenhaus',
    'zahnarzt',
    'physiotherapie',
    'optiker',
    'zuzahlung',
  ],
  'Versicherungen': [
    'versicherung',
    'allianz',
    'huk',
    'axa',
    'ergo',
    'techniker krankenkasse',
    'barmer',
    'aok',
    'dak',
    'haftpflicht',
    'kfz-versicherung',
  ],
  'Freizeit & Freunde': [
    'restaurant',
    'gasthaus',
    'cafe ',
    'café',
    'bistro',
    'vapiano',
    'mcdonalds',
    'burger king',
    'subway',
    'lieferando',
    'uber eats',
    'wolt',
    'pizza',
  ],
  'Geschenke': [
    'geschenk',
    'blumen',
    'florist',
    'thalia',
    'hugendubel',
    'mayersche',
  ],
};

// ── Kategorisierungs-Ergebnis ─────────────────────────────────────────────────
enum CategorizationSource { keyword, income, fallback }

class CategorizationResult {
  final String category;
  final CategorizationSource source;

  const CategorizationResult(this.category, this.source);
}

// ── Categorizer ───────────────────────────────────────────────────────────────
class LocalCategorizer {
  /// Kategorisiert eine einzelne Transaktion.
  /// Gibt immer eine gültige Kategorie zurück.
  static CategorizationResult categorize(Transaction transaction) {
    // Einnahmen → immer Sonstiges
    if (transaction.amount > 0) {
      return const CategorizationResult(
        'Sonstiges',
        CategorizationSource.income,
      );
    }

    final desc = transaction.description.toLowerCase();

    // Keyword-Matching
    for (final entry in _keywordRules.entries) {
      for (final keyword in entry.value) {
        if (desc.contains(keyword)) {
          return CategorizationResult(entry.key, CategorizationSource.keyword);
        }
      }
    }

    // Kein Match → Sonstiges
    return const CategorizationResult(
      'Sonstiges',
      CategorizationSource.fallback,
    );
  }

  /// Kategorisiert eine Liste von Transaktionen.
  /// Gibt Statistiken zurück wie viele per Keyword erkannt wurden.
  static CategorizationStats categorizeAll(
    List<Transaction> transactions,
  ) {
    var keywordCount = 0;
    var fallbackCount = 0;

    final categorized = transactions.map((t) {
      final result = categorize(t);
      if (result.source == CategorizationSource.keyword) {
        keywordCount++;
      } else if (result.source == CategorizationSource.fallback) {
        fallbackCount++;
      }
      return t.copyWith(category: result.category);
    }).toList();

    return CategorizationStats(
      transactions: categorized,
      keywordMatches: keywordCount,
      fallbackCount: fallbackCount,
    );
  }

  /// Berechnet eine Analyse aus kategorisierten Transaktionen.
  /// Entspricht dem /analysis Endpoint im Backend.
  static AnalysisResult analyze(List<Transaction> transactions) {
    if (transactions.isEmpty) {
      throw StateError('Keine Transaktionen zum Analysieren.');
    }

    double totalIncome = 0;
    double totalExpenses = 0;
    final categoryTotals = <String, double>{};
    final categoryCounts = <String, int>{};

    for (final t in transactions) {
      if (t.amount > 0) {
        totalIncome += t.amount;
      } else {
        totalExpenses += t.amount.abs();
        final cat = t.category ?? 'Sonstiges';
        categoryTotals[cat] = (categoryTotals[cat] ?? 0) + t.amount.abs();
        categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
      }
    }

    final categories = categoryTotals.entries.map((e) {
      final pct = totalExpenses > 0 ? e.value / totalExpenses * 100 : 0.0;
      return CategorySummary(
        category: e.key,
        total: e.value,
        count: categoryCounts[e.key] ?? 0,
        percentage: double.parse(pct.toStringAsFixed(1)),
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    final dates = transactions.map((t) => t.date).toList()..sort();

    return AnalysisResult(
      totalIncome: (totalIncome * 100).round() / 100,
      totalExpenses: (totalExpenses * 100).round() / 100,
      net: ((totalIncome - totalExpenses) * 100).round() / 100,
      categories: categories,
      periodStart: dates.first,
      periodEnd: dates.last,
    );
  }
}

class CategorizationStats {
  final List<Transaction> transactions;
  final int keywordMatches;
  final int fallbackCount;

  const CategorizationStats({
    required this.transactions,
    required this.keywordMatches,
    required this.fallbackCount,
  });

  int get total => transactions.length;
  double get keywordAccuracy => total > 0 ? keywordMatches / total * 100 : 0;
}
