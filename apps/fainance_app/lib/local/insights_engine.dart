import '../core/models.dart';

// Richtwerte: Anteil am Nettoeinkommen in Prozent (Destatis 2023)
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

class LocalInsightsEngine {
  static InsightResponse generate(AnalysisResult analysis) {
    final base = analysis.totalIncome > 0
        ? analysis.totalIncome
        : analysis.totalExpenses;

    final savings = analysis.totalIncome > 0
        ? analysis.net / analysis.totalIncome * 100
        : 0.0;

    // Kategorien gegen Benchmarks vergleichen
    final overBudget = <CategorySummary>[];
    CategorySummary? underSaving;

    for (final cat in analysis.categories) {
      final benchmark = _benchmarks[cat.category] ?? 5.0;
      final actualPct = base > 0 ? cat.total / base * 100 : 0.0;
      final deviation = actualPct - benchmark;

      if (deviation > 2.0) overBudget.add(cat);
      if (cat.category == 'Sparen / Investieren' && deviation < -3.0) {
        underSaving = cat;
      }
    }
    overBudget.sort((a, b) => b.total.compareTo(a.total));

    // ── Zusammenfassung ──────────────────────────────────────────────────────
    final summary = _buildSummary(analysis, savings);

    // ── Warnungen ────────────────────────────────────────────────────────────
    final warnings = <String>[];
    for (final cat in overBudget.take(2)) {
      final benchmark = _benchmarks[cat.category] ?? 5.0;
      final actualPct = base > 0 ? cat.total / base * 100 : 0.0;
      warnings.add(
        '${cat.category}: ${cat.total.toStringAsFixed(2)}€ '
        '(${actualPct.toStringAsFixed(1)}% deines Einkommens, '
        'Richtwert: ${benchmark.toStringAsFixed(0)}%)',
      );
    }
    if (savings < 5 && analysis.totalIncome > 0) {
      warnings.add(
        'Sparquote nur ${savings.toStringAsFixed(1)}% — '
        'Empfehlung: mindestens 10%.',
      );
    }

    // ── Tipps ────────────────────────────────────────────────────────────────
    final tips = <String>[];

    // Spezifische Tipps je Kategorie
    for (final cat in overBudget.take(3)) {
      final tip = _tipForCategory(cat.category, cat.total);
      if (tip != null) tips.add(tip);
    }

    if (underSaving != null) {
      tips.add(
        'Richte einen automatischen Dauerauftrag für einen ETF-Sparplan ein — '
        'selbst 50€/Monat machen langfristig einen großen Unterschied.',
      );
    }

    if (tips.isEmpty) {
      tips.add(
        'Behalte deine größten Ausgabenkategorien im Blick und '
        'vergleiche sie monatlich.',
      );
    }

    // ── Positives ────────────────────────────────────────────────────────────
    final positive = <String>[];

    if (savings >= 15) {
      positive.add(
        'Sehr gute Sparquote von ${savings.toStringAsFixed(1)}% — '
        'du bist auf dem richtigen Weg.',
      );
    } else if (savings >= 10) {
      positive.add('Sparquote von ${savings.toStringAsFixed(1)}% — solide.');
    }

    if (analysis.net > 0) {
      positive.add(
        'Monatlicher Überschuss von '
        '${analysis.net.toStringAsFixed(2)}€ — '
        'du lebst unter deinen Verhältnissen.',
      );
    }

    if (overBudget.isEmpty) {
      positive.add(
        'Alle Kategorien liegen im Rahmen der Richtwerte. Weiter so!',
      );
    }

    if (positive.isEmpty) {
      positive.add('Deine Finanzen wurden erfolgreich analysiert.');
    }

    return InsightResponse(
      summary: summary,
      warnings: warnings,
      tips: tips,
      positive: positive,
    );
  }

  static String _buildSummary(AnalysisResult a, double savings) {
    final period = '${a.periodStart.day}.${a.periodStart.month} – '
        '${a.periodEnd.day}.${a.periodEnd.month}.${a.periodEnd.year}';

    if (a.totalIncome == 0) {
      return 'Im Zeitraum $period wurden ${a.totalExpenses.toStringAsFixed(2)}€ '
          'ausgegeben. Kein Einkommen erfasst.';
    }

    final savingsText = savings >= 10
        ? 'Die Sparquote von ${savings.toStringAsFixed(1)}% ist gut.'
        : 'Die Sparquote von ${savings.toStringAsFixed(1)}% sollte höher sein.';

    return 'Im Zeitraum $period: ${a.totalExpenses.toStringAsFixed(2)}€ '
        'Ausgaben bei ${a.totalIncome.toStringAsFixed(2)}€ Einnahmen. '
        '$savingsText';
  }

  static String? _tipForCategory(String category, double amount) {
    switch (category) {
      case 'Freizeit & Freunde':
        return 'Bei Restaurants und Lieferdiensten kannst du mit einem '
            'Wochenbudget von ${(amount * 0.7 / 4).toStringAsFixed(0)}€ '
            'etwa 30% einsparen.';
      case 'Unterhaltung':
        return 'Prüfe welche Streaming-Abos du wirklich nutzt — '
            'viele zahlen für 3+ Dienste gleichzeitig.';
      case 'Lebensmittel':
        return 'Wochenplanung und Einkaufsliste können Lebensmittelausgaben '
            'um 15–20% senken.';
      case 'Transport':
        return 'Ein Deutschlandticket (49€/Monat) lohnt sich wenn du '
            'regelmäßig Bahn oder ÖPNV nutzt.';
      case 'Drogerie':
        return 'Drogerieprodukte im Eigenmarken-Vergleich sind oft '
            '30–50% günstiger als Markenprodukte.';
      default:
        return null;
    }
  }
}
