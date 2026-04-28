import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../core/theme.dart';
import '../../local/insights_engine.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _touchedIndex = -1;
  late AnalysisResult _analysis;
  late List<Transaction> _transactions;
  late InsightResponse _insights;
  bool _initialized = false;

  final _currencyFmt = NumberFormat.currency(locale: 'de_DE', symbol: '€');
  final _dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      _analysis = args['analysis'] as AnalysisResult;
      _transactions = args['transactions'] as List<Transaction>;
      // Insights lokal generieren — synchron, kein Server
      _insights = LocalInsightsEngine.generate(_analysis);
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildStatCards()),
          SliverToBoxAdapter(child: _buildPieChart()),
          SliverToBoxAdapter(child: _buildInsightsBlock()),
          SliverToBoxAdapter(child: _buildCategoryList()),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          _buildTransactionList(),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.background,
      pinned: true,
      title: const Text('Analyse',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Neu laden', style: TextStyle(color: AppColors.accent)),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }

  Widget _buildStatCards() {
    final items = [
      (
        'Einnahmen',
        _currencyFmt.format(_analysis.totalIncome),
        AppColors.income
      ),
      (
        'Ausgaben',
        _currencyFmt.format(_analysis.totalExpenses),
        AppColors.expense
      ),
      (
        'Saldo',
        _currencyFmt.format(_analysis.net),
        _analysis.net >= 0 ? AppColors.income : AppColors.expense
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: items
            .map((item) => Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$1,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11)),
                        const SizedBox(height: 4),
                        FittedBox(
                          child: Text(item.$2,
                              style: TextStyle(
                                  color: item.$3,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildPieChart() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ausgaben nach Kategorie',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (_, response) => setState(() {
                    _touchedIndex =
                        response?.touchedSection?.touchedSectionIndex ?? -1;
                  }),
                ),
                sectionsSpace: 2,
                centerSpaceRadius: 60,
                sections: _analysis.categories.asMap().entries.map((e) {
                  final isTouched = e.key == _touchedIndex;
                  return PieChartSectionData(
                    value: e.value.total,
                    title: isTouched
                        ? '${e.value.percentage.toStringAsFixed(1)}%'
                        : '',
                    radius: isTouched ? 50 : 40,
                    color: AppColors
                        .chartColors[e.key % AppColors.chartColors.length],
                    titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  );
                }).toList(),
              )),
            ),
          ],
        ),
      ),
    );
  }

  // ── Insights direkt unter Pie Chart ───────────────────────────────────────
  Widget _buildInsightsBlock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.auto_awesome, color: AppColors.accent, size: 16),
              const SizedBox(width: 8),
              Text('Analyse',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            Text(_insights.summary,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.5)),
            if (_insights.warnings.isNotEmpty) ...[
              const SizedBox(height: 10),
              _chip(Icons.warning_amber_rounded, _insights.warnings.first,
                  const Color(0xFFF59E0B)),
            ],
            if (_insights.tips.isNotEmpty) ...[
              const SizedBox(height: 8),
              _chip(Icons.lightbulb_outline, _insights.tips.first,
                  AppColors.accent),
            ],
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () =>
                  Navigator.pushNamed(context, '/insights', arguments: {
                'analysis': _analysis,
                'transactions': _transactions,
              }),
              child: Text('Alle Tipps →',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: _analysis.categories.asMap().entries.map((e) {
            final color =
                AppColors.chartColors[e.key % AppColors.chartColors.length];
            final cat = e.value;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(children: [
                Row(children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(cat.category,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14))),
                  Text(_currencyFmt.format(cat.total),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: Text('${cat.percentage.toStringAsFixed(1)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12)),
                  ),
                ]),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: cat.percentage / 100,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ]),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTransactionList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text('Transaktionen (${_transactions.length})',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            );
          }
          final t = _transactions[index - 1];
          return Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.description,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text(_dateFmt.format(t.date),
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12)),
                      if (t.category != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(t.category!,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11)),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              Text(_currencyFmt.format(t.amount),
                  style: TextStyle(
                      color:
                          t.amount > 0 ? AppColors.income : AppColors.expense,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ]),
          );
        },
        childCount: _transactions.length + 1,
      ),
    );
  }
}
