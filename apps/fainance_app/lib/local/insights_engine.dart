import '../core/models.dart';
import 'language_detector.dart';

// ── Benchmarks (Destatis 2023) ─────────────────────────────────────────────────
const _benchmarks = <String, double>{
  'Miete': 30.0,
  'Lebensmittel': 14.0,
  'Transport': 8.0,
  'Freizeit & Freunde': 7.0,
  'Versicherungen': 6.0,
  'Unterhaltung': 4.0,
  'Drogerie': 3.0,
  'Gesundheit': 3.0,
  'Sport': 2.0,
  'Sparen / Investieren': 10.0,
  'Geschenke': 2.0,
  'Sonstiges': 5.0,
};

// ── Strings je Sprache ─────────────────────────────────────────────────────────
class _Strings {
  final String lang;
  const _Strings(this.lang);

  bool get isDe => lang == 'de';

  String get analysisTitle => isDe ? 'Analyse' : 'Analysis';

  String summary(double expenses, double income, double savings) => isDe
      ? 'Du hast ${expenses.toStringAsFixed(2)}€ ausgegeben bei '
          '${income.toStringAsFixed(2)}€ Einnahmen. '
          '${_savingsComment(savings)}'
      : 'You spent ${expenses.toStringAsFixed(2)}€ with '
          '${income.toStringAsFixed(2)}€ income. '
          '${_savingsCommentEn(savings)}';

  String summaryNoIncome(double expenses) => isDe
      ? 'Ausgaben in diesem Zeitraum: ${expenses.toStringAsFixed(2)}€. '
          'Kein Einkommen erfasst.'
      : 'Expenses this period: ${expenses.toStringAsFixed(2)}€. '
          'No income recorded.';

  String _savingsComment(double s) {
    if (s >= 20)
      return 'Ausgezeichnete Sparquote von ${s.toStringAsFixed(1)}%.';
    if (s >= 10) return 'Gute Sparquote von ${s.toStringAsFixed(1)}%.';
    if (s >= 0)
      return 'Sparquote von ${s.toStringAsFixed(1)}% — Luft nach oben.';
    return 'Ausgaben übersteigen Einnahmen um ${(-s).toStringAsFixed(1)}%.';
  }

  String _savingsCommentEn(double s) {
    if (s >= 20) return 'Excellent savings rate of ${s.toStringAsFixed(1)}%.';
    if (s >= 10) return 'Good savings rate of ${s.toStringAsFixed(1)}%.';
    if (s >= 0)
      return 'Savings rate of ${s.toStringAsFixed(1)}% — room to improve.';
    return 'Expenses exceed income by ${(-s).toStringAsFixed(1)}%.';
  }

  String overBudgetWarning(
          String cat, double amount, double actual, double bench) =>
      isDe
          ? '$cat: ${amount.toStringAsFixed(2)}€ '
              '(${actual.toStringAsFixed(1)}% deines Einkommens, '
              'Richtwert: ${bench.toStringAsFixed(0)}%)'
          : '$cat: ${amount.toStringAsFixed(2)}€ '
              '(${actual.toStringAsFixed(1)}% of your income, '
              'benchmark: ${bench.toStringAsFixed(0)}%)';

  String lowSavingsWarning(double s) => isDe
      ? 'Sparquote nur ${s.toStringAsFixed(1)}% — Empfehlung: mindestens 10%.'
      : 'Savings rate only ${s.toStringAsFixed(1)}% — aim for at least 10%.';

  String get tipSavingsPlan => isDe
      ? 'Richte einen automatischen ETF-Sparplan ein — '
          'bereits 50€/Monat machen langfristig einen großen Unterschied.'
      : 'Set up an automatic ETF savings plan — '
          'even 50€/month makes a big difference over time.';

  String get tipBudget => isDe
      ? 'Behalte deine größten Kategorien im Blick und vergleiche sie monatlich.'
      : 'Track your biggest categories and compare them monthly.';

  String get positiveAllGood => isDe
      ? 'Alle Kategorien liegen im Rahmen der Richtwerte. Weiter so!'
      : 'All categories are within benchmark ranges. Keep it up!';

  String positiveOverflow(double net) => isDe
      ? 'Monatlicher Überschuss von ${net.toStringAsFixed(2)}€ — '
          'du lebst unter deinen Verhältnissen.'
      : 'Monthly surplus of ${net.toStringAsFixed(2)}€ — '
          'you\'re living within your means.';

  String positiveSavings(double s) => isDe
      ? 'Sparquote von ${s.toStringAsFixed(1)}% — solide Basis.'
      : 'Savings rate of ${s.toStringAsFixed(1)}% — solid foundation.';

  String tipForCategory(String cat, double amount) {
    if (isDe) {
      switch (cat) {
        case 'Freizeit & Freunde':
          return 'Bei Restaurants & Lieferdiensten könntest du mit einem '
              'Wochenbudget von ${(amount * 0.7 / 4).toStringAsFixed(0)}€ '
              'etwa 30% einsparen.';
        case 'Unterhaltung':
          return 'Prüfe welche Streaming-Abos du wirklich nutzt — '
              'viele zahlen für 3+ Dienste gleichzeitig.';
        case 'Lebensmittel':
          return 'Wochenplanung und Einkaufsliste können Lebensmittelausgaben '
              'um 15–20% senken.';
        case 'Transport':
          return 'Ein Deutschlandticket (49€/Monat) lohnt sich '
              'wenn du regelmäßig Bahn oder ÖPNV nutzt.';
        case 'Drogerie':
          return 'Eigenmarken sind oft 30–50% günstiger als Markenprodukte.';
      }
    } else {
      switch (cat) {
        case 'Freizeit & Freunde':
          return 'Set a weekly budget of ${(amount * 0.7 / 4).toStringAsFixed(0)}€ '
              'for restaurants to save around 30%.';
        case 'Unterhaltung':
          return 'Check which streaming subscriptions you actually use — '
              'many people pay for 3+ services simultaneously.';
        case 'Lebensmittel':
          return 'Meal planning and shopping lists can reduce food costs by 15–20%.';
        case 'Transport':
          return 'Consider a public transport subscription if you commute regularly.';
        case 'Drogerie':
          return 'Store brands are often 30–50% cheaper than name brands.';
      }
    }
    return '';
  }

  // ── Bewusstseins-Analyse ───────────────────────────────────────────────────
  // Zeigt wo viel gebucht wurde — ohne Wertung, nur Bewusstsein schaffen
  String get awarenessHeader =>
      isDe ? 'Wo du am meisten buchst' : 'Where you book the most';

  String awarenessItem(String cat, int count, double total) => isDe
      ? '$cat: $count Buchungen · ${total.toStringAsFixed(2)}€'
      : '$cat: $count bookings · ${total.toStringAsFixed(2)}€';

  String awarenessTopMerchant(String merchant, double amount) => isDe
      ? 'Häufigste Buchung: $merchant (${amount.toStringAsFixed(2)}€)'
      : 'Most frequent: $merchant (${amount.toStringAsFixed(2)}€)';
}

// ── Awareness Item ─────────────────────────────────────────────────────────────
class CategoryAwareness {
  final String category;
  final int bookingCount;
  final double total;
  final double percentageOfExpenses;

  const CategoryAwareness({
    required this.category,
    required this.bookingCount,
    required this.total,
    required this.percentageOfExpenses,
  });
}

// ── InsightResponse erweitert ──────────────────────────────────────────────────
// Wir nutzen das bestehende InsightResponse Model, packen awareness in positive
// und fügen einen separaten awareness-Block hinzu

// ── Haupt-Engine ───────────────────────────────────────────────────────────────
class LocalInsightsEngine {
  /// Generiert Insights aus einer Analyse.
  /// Sprache wird automatisch aus den Transaktionsbeschreibungen erkannt.
  static InsightResponse generate(
    AnalysisResult analysis, {
    List<String>? descriptions, // für Spracherkennung
  }) {
    // Sprache erkennen
    final lang = descriptions != null && descriptions.isNotEmpty
        ? LanguageDetector.detect(descriptions)
        : 'de';
    final s = _Strings(lang);

    final base = analysis.totalIncome > 0
        ? analysis.totalIncome
        : analysis.totalExpenses;
    final savings = analysis.totalIncome > 0
        ? analysis.net / analysis.totalIncome * 100
        : 0.0;

    // Kategorien gegen Benchmarks prüfen
    final overBudget = <CategorySummary>[];
    var underSaving = false;

    for (final cat in analysis.categories) {
      final benchmark = _benchmarks[cat.category] ?? 5.0;
      final actualPct = base > 0 ? cat.total / base * 100 : 0.0;
      final deviation = actualPct - benchmark;
      if (deviation > 2.0) overBudget.add(cat);
      if (cat.category == 'Sparen / Investieren' && deviation < -3.0) {
        underSaving = true;
      }
    }
    overBudget.sort((a, b) => b.total.compareTo(a.total));

    // ── Zusammenfassung ──────────────────────────────────────────────────────
    final summary = analysis.totalIncome > 0
        ? s.summary(analysis.totalExpenses, analysis.totalIncome, savings)
        : s.summaryNoIncome(analysis.totalExpenses);

    // ── Warnungen ────────────────────────────────────────────────────────────
    final warnings = <String>[];
    for (final cat in overBudget.take(2)) {
      final benchmark = _benchmarks[cat.category] ?? 5.0;
      final actualPct = base > 0 ? cat.total / base * 100 : 0.0;
      warnings.add(
          s.overBudgetWarning(cat.category, cat.total, actualPct, benchmark));
    }
    if (savings < 5 && analysis.totalIncome > 0) {
      warnings.add(s.lowSavingsWarning(savings));
    }

    // ── Tipps ────────────────────────────────────────────────────────────────
    final tips = <String>[];
    for (final cat in overBudget.take(3)) {
      final tip = s.tipForCategory(cat.category, cat.total);
      if (tip.isNotEmpty) tips.add(tip);
    }
    if (underSaving) tips.add(s.tipSavingsPlan);
    if (tips.isEmpty) tips.add(s.tipBudget);

    // ── Bewusstseins-Analyse ─────────────────────────────────────────────────
    // Top-Kategorien nach Buchungsanzahl — nicht nach Betrag
    // Zeigt wo viel passiert, ohne zu werten
    final awareness = _buildAwareness(analysis, s);

    // ── Positives ────────────────────────────────────────────────────────────
    final positive = <String>[];
    if (savings >= 15) positive.add(s.positiveSavings(savings));
    if (analysis.net > 0) positive.add(s.positiveOverflow(analysis.net));
    if (overBudget.isEmpty) positive.add(s.positiveAllGood);
    if (positive.isEmpty) {
      positive.add(s.positiveSavings(savings.clamp(0, 100)));
    }

    return InsightResponse(
      summary: summary,
      warnings: warnings,
      tips: tips,
      positive: positive,
      awareness: awareness,
      language: lang,
    );
  }

  static List<CategoryAwareness> _buildAwareness(
    AnalysisResult analysis,
    _Strings s,
  ) {
    // Nach Buchungsanzahl sortieren — zeigt wo am aktivsten gebucht wird
    final items = analysis.categories
        .where((c) => c.count > 1) // Einzel-Buchungen weglassen
        .map((c) => CategoryAwareness(
              category: c.category,
              bookingCount: c.count,
              total: c.total,
              percentageOfExpenses: c.percentage,
            ))
        .toList()
      ..sort((a, b) => b.bookingCount.compareTo(a.bookingCount));

    return items.take(5).toList(); // Top 5
  }
}
