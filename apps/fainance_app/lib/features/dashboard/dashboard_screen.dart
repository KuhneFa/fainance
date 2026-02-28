import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/theme.dart';

// ── Formatter ──────────────────────────────────────────────────────────────────
// intl-Package: formatiert Zahlen und Daten nach Locale.
// `de_DE` gibt uns "1.234,56 €" statt "1234.56"
final _currencyFormat = NumberFormat.currency(locale: 'de_DE', symbol: '€');
final _dateFormat = DateFormat('dd.MM.yy', 'de_DE');


// ── Dashboard State ────────────────────────────────────────────────────────────
class DashboardState extends ChangeNotifier {
  LoadingStatus status = LoadingStatus.loading;
  String? errorMessage;
  AnalysisResult? analysis;
  List<Transaction> transactions = [];
  int? touchedIndex; // welcher Donut-Sektor ist gerade angetippt

  final _api = ApiClient();

  Future<void> load(String uploadId) async {
    status = LoadingStatus.loading;
    notifyListeners();

    try {
      // Beide Requests parallel starten — schneller als nacheinander
      // Future.wait wartet bis BEIDE fertig sind
      final results = await Future.wait([
        _api.getAnalysis(uploadId),
        _api.getTransactions(uploadId),
      ]);

      analysis = results[0] as AnalysisResult;
      transactions = results[1] as List<Transaction>;
      status = LoadingStatus.success;
    } on Exception catch (e) {
      errorMessage = parseApiError(e);
      status = LoadingStatus.error;
    }

    notifyListeners();
  }

  void setTouchedIndex(int? index) {
    touchedIndex = index;
    notifyListeners();
  }

  // Gibt die Farbe für eine Kategorie zurück — konsistent durch die ganze App
  static Color colorForIndex(int index) {
    return AppColors.chartColors[index % AppColors.chartColors.length];
  }
}

enum LoadingStatus { loading, success, error }


// ── Dashboard Screen ───────────────────────────────────────────────────────────
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // uploadId kommt als Argument von der Navigation
    final uploadId = ModalRoute.of(context)!.settings.arguments as String;

    return ChangeNotifierProvider(
      create: (_) => DashboardState()..load(uploadId),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DashboardState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          // Insights-Button
          TextButton.icon(
            onPressed: state.analysis == null
                ? null
                : () => Navigator.of(context).pushNamed(
                      '/insights',
                      arguments: state.analysis,
                    ),
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('KI-Tipps'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
            ),
          ),
        ],
      ),
      body: switch (state.status) {
        LoadingStatus.loading => const _LoadingView(),
        LoadingStatus.error => _ErrorView(message: state.errorMessage!),
        LoadingStatus.success => _SuccessView(
            analysis: state.analysis!,
            transactions: state.transactions,
          ),
      },
    );
  }
}


// ── Loading ────────────────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        color: AppColors.accent,
        strokeWidth: 2,
      ),
    );
  }
}


// ── Error ──────────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.expense, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}


// ── Success: Haupt-Content ─────────────────────────────────────────────────────
class _SuccessView extends StatelessWidget {
  final AnalysisResult analysis;
  final List<Transaction> transactions;

  const _SuccessView({required this.analysis, required this.transactions});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      // CustomScrollView + Slivers ermöglicht es, verschiedene
      // scroll-fähige Elemente zu mischen (z.B. fixe Header + Liste)
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Zeitraum
              _PeriodHeader(analysis: analysis),
              const SizedBox(height: 16),

              // Einnahmen / Ausgaben / Saldo
              _SummaryRow(analysis: analysis),
              const SizedBox(height: 24),

              // Donut Chart
              _CategoryChart(analysis: analysis),
              const SizedBox(height: 24),

              // Kategorie-Legende
              _CategoryLegend(categories: analysis.categories),
              const SizedBox(height: 24),

              // Transaktionen Header
              Text(
                'Transaktionen',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 16,
                    ),
              ),
              const SizedBox(height: 12),
            ]),
          ),
        ),

        // Transaktionsliste als eigener Sliver — performantes Lazy Rendering
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: transactions.length,
            itemBuilder: (context, index) =>
                _TransactionTile(transaction: transactions[index]),
          ),
        ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }
}


// ── Zeitraum Header ────────────────────────────────────────────────────────────
class _PeriodHeader extends StatelessWidget {
  final AnalysisResult analysis;
  const _PeriodHeader({required this.analysis});

  @override
  Widget build(BuildContext context) {
    return Text(
      '${_dateFormat.format(analysis.periodStart)} – ${_dateFormat.format(analysis.periodEnd)}',
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}


// ── Summary Row: 3 Karten nebeneinander ───────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  final AnalysisResult analysis;
  const _SummaryRow({required this.analysis});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Einnahmen',
            value: _currencyFormat.format(analysis.totalIncome),
            valueColor: AppColors.income,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Ausgaben',
            value: _currencyFormat.format(analysis.totalExpenses),
            valueColor: AppColors.expense,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Saldo',
            value: _currencyFormat.format(analysis.net),
            valueColor: analysis.net >= 0 ? AppColors.income : AppColors.expense,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 11)),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
          ),
        ],
      ),
    );
  }
}


// ── Donut Chart ────────────────────────────────────────────────────────────────
class _CategoryChart extends StatelessWidget {
  final AnalysisResult analysis;
  const _CategoryChart({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DashboardState>();
    final categories = analysis.categories;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ausgaben nach Kategorie',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                // pieTouchData: reagiert auf Antippen eines Sektors
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions ||
                        response == null ||
                        response.touchedSection == null) {
                      state.setTouchedIndex(null);
                      return;
                    }
                    state.setTouchedIndex(
                        response.touchedSection!.touchedSectionIndex);
                  },
                ),
                sectionsSpace: 2,      // Abstand zwischen Sektoren
                centerSpaceRadius: 60, // Loch in der Mitte (Donut)
                sections: categories.asMap().entries.map((entry) {
                  final index = entry.key;
                  final cat = entry.value;
                  final isTouched = index == state.touchedIndex;

                  return PieChartSectionData(
                    value: cat.total,
                    color: DashboardState.colorForIndex(index),
                    // Angetippter Sektor wird größer dargestellt
                    radius: isTouched ? 32 : 24,
                    title: isTouched ? '${cat.percentage.toStringAsFixed(1)}%' : '',
                    titleStyle: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Mitte des Donuts: zeigt angetippte Kategorie oder Gesamtausgaben
          if (state.touchedIndex != null &&
              state.touchedIndex! < categories.length)
            Center(
              child: Column(
                children: [
                  Text(
                    categories[state.touchedIndex!].category,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    _currencyFormat
                        .format(categories[state.touchedIndex!].total),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}


// ── Kategorie Legende ──────────────────────────────────────────────────────────
class _CategoryLegend extends StatelessWidget {
  final List<CategorySummary> categories;
  const _CategoryLegend({required this.categories});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: categories.asMap().entries.map((entry) {
          final index = entry.key;
          final cat = entry.value;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                // Farb-Dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: DashboardState.colorForIndex(index),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cat.category,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontSize: 13,
                        ),
                  ),
                ),
                // Fortschrittsbalken
                SizedBox(
                  width: 80,
                  child: LinearProgressIndicator(
                    value: cat.percentage / 100,
                    backgroundColor: AppColors.border,
                    color: DashboardState.colorForIndex(index),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 64,
                  child: Text(
                    _currencyFormat.format(cat.total),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}


// ── Transaktion Tile ───────────────────────────────────────────────────────────
class _TransactionTile extends StatelessWidget {
  final Transaction transaction;
  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.isExpense;

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        // Erste und letzte Tile bekommen abgerundete Ecken oben/unten
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          // Kategorie-Icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _iconForCategory(transaction.category),
              size: 16,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(width: 12),

          // Beschreibung + Datum
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_dateFormat.format(transaction.date)} · ${transaction.category ?? 'Sonstiges'}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),

          // Betrag
          Text(
            _currencyFormat.format(transaction.amount),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isExpense ? AppColors.expense : AppColors.income,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
          ),
        ],
      ),
    );
  }

  IconData _iconForCategory(String? category) {
    return switch (category) {
      'Lebensmittel' => Icons.shopping_basket_outlined,
      'Miete' => Icons.home_outlined,
      'Sport' => Icons.fitness_center_outlined,
      'Drogerie' => Icons.local_pharmacy_outlined,
      'Transport' => Icons.directions_car_outlined,
      'Unterhaltung' => Icons.movie_outlined,
      'Gesundheit' => Icons.favorite_outline,
      'Versicherungen' => Icons.security_outlined,
      'Sparen / Investieren' => Icons.savings_outlined,
      'Geschenke' => Icons.card_giftcard_outlined,
      'Freizeit & Freunde' => Icons.people_outline,
      _ => Icons.receipt_outlined,
    };
  }
}