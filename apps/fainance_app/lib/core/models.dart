import 'package:flutter/foundation.dart';
import '../local/insights_engine.dart' show CategoryAwareness;

@immutable
class Transaction {
  final int? id;
  final DateTime date;
  final String description;
  final double amount;
  final String? category;

  const Transaction({
    this.id,
    required this.date,
    required this.description,
    required this.amount,
    this.category,
  });

  bool get isExpense => amount < 0;
  bool get isIncome => amount > 0;

  Transaction copyWith({
    int? id,
    DateTime? date,
    String? description,
    double? amount,
    String? category,
  }) {
    return Transaction(
      id: id ?? this.id,
      date: date ?? this.date,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      category: category ?? this.category,
    );
  }

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        id: json['id'] as int?,
        date: DateTime.parse(json['date'] as String),
        description: json['description'] as String,
        amount: (json['amount'] as num).toDouble(),
        category: json['category'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'date': date.toIso8601String().split('T')[0],
        'description': description,
        'amount': amount,
        if (category != null) 'category': category,
      };
}

@immutable
class CategorySummary {
  final String category;
  final double total;
  final int count;
  final double percentage;

  const CategorySummary({
    required this.category,
    required this.total,
    required this.count,
    required this.percentage,
  });

  factory CategorySummary.fromJson(Map<String, dynamic> json) =>
      CategorySummary(
        category: json['category'] as String,
        total: (json['total'] as num).toDouble(),
        count: json['count'] as int,
        percentage: (json['percentage'] as num).toDouble(),
      );
}

@immutable
class AnalysisResult {
  final double totalIncome;
  final double totalExpenses;
  final double net;
  final List<CategorySummary> categories;
  final DateTime periodStart;
  final DateTime periodEnd;

  const AnalysisResult({
    required this.totalIncome,
    required this.totalExpenses,
    required this.net,
    required this.categories,
    required this.periodStart,
    required this.periodEnd,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) => AnalysisResult(
        totalIncome: (json['total_income'] as num).toDouble(),
        totalExpenses: (json['total_expenses'] as num).toDouble(),
        net: (json['net'] as num).toDouble(),
        categories: (json['categories'] as List)
            .map((c) => CategorySummary.fromJson(c as Map<String, dynamic>))
            .toList(),
        periodStart: DateTime.parse(json['period_start'] as String),
        periodEnd: DateTime.parse(json['period_end'] as String),
      );

  Map<String, dynamic> toJson() => {
        'total_income': totalIncome,
        'total_expenses': totalExpenses,
        'net': net,
        'categories': categories
            .map((c) => {
                  'category': c.category,
                  'total': c.total,
                  'count': c.count,
                  'percentage': c.percentage,
                })
            .toList(),
        'period_start': periodStart.toIso8601String().split('T')[0],
        'period_end': periodEnd.toIso8601String().split('T')[0],
      };
}

@immutable
class InsightResponse {
  final String summary;
  final List<String> warnings;
  final List<String> tips;
  final List<String> positive;
  final List<CategoryAwareness> awareness;
  final String language; // 'de' oder 'en'

  const InsightResponse({
    required this.summary,
    required this.warnings,
    required this.tips,
    required this.positive,
    this.awareness = const [],
    this.language = 'de',
  });

  factory InsightResponse.fromJson(Map<String, dynamic> json) =>
      InsightResponse(
        summary: json['summary'] as String,
        warnings: List<String>.from(json['warnings'] as List),
        tips: List<String>.from(json['tips'] as List),
        positive: List<String>.from(json['positive'] as List),
      );
}

@immutable
class UploadResponse {
  final String uploadId;
  final int transactionCount;

  const UploadResponse({
    required this.uploadId,
    required this.transactionCount,
  });

  factory UploadResponse.fromJson(Map<String, dynamic> json) => UploadResponse(
        uploadId: json['upload_id'] as String,
        transactionCount: json['transaction_count'] as int,
      );
}
