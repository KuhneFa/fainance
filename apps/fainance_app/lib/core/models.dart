// ── models.dart ───────────────────────────────────────────────────────────────
// Dart-Entsprechungen der Python Pydantic-Models.
// fromJson: API-Response (Map) → Dart-Objekt
// toJson:   Dart-Objekt → Map (für POST-Requests)

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

  // factory-Konstruktor: erstellt ein Objekt aus einer JSON-Map.
  // Der `factory`-Keyword erlaubt es, null zurückzugeben oder
  // gecachte Instanzen zurückzugeben — flexibler als ein normaler Konstruktor.
  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as int?,
      date: DateTime.parse(json['date'] as String),
      description: json['description'] as String,
      amount: (json['amount'] as num).toDouble(),
      category: json['category'] as String?,
    );
  }

  bool get isExpense => amount < 0;
  bool get isIncome => amount > 0;

  // copyWith: erstellt eine Kopie mit einzelnen geänderten Feldern.
  // Das Dart-Äquivalent zu Pydantics model_copy(update={...}).
  Transaction copyWith({String? category}) {
    return Transaction(
      id: id,
      date: date,
      description: description,
      amount: amount,
      category: category ?? this.category,
    );
  }
}


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

  factory CategorySummary.fromJson(Map<String, dynamic> json) {
    return CategorySummary(
      category: json['category'] as String,
      total: (json['total'] as num).toDouble(),
      count: json['count'] as int,
      percentage: (json['percentage'] as num).toDouble(),
    );
  }
}


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

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      totalIncome: (json['total_income'] as num).toDouble(),
      totalExpenses: (json['total_expenses'] as num).toDouble(),
      net: (json['net'] as num).toDouble(),
      categories: (json['categories'] as List)
          .map((c) => CategorySummary.fromJson(c as Map<String, dynamic>))
          .toList(),
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
    );
  }
}


class InsightResponse {
  final String summary;
  final List<String> warnings;
  final List<String> tips;
  final List<String> positive;

  const InsightResponse({
    required this.summary,
    required this.warnings,
    required this.tips,
    required this.positive,
  });

  factory InsightResponse.fromJson(Map<String, dynamic> json) {
    return InsightResponse(
      summary: json['summary'] as String,
      warnings: List<String>.from(json['warnings'] as List),
      tips: List<String>.from(json['tips'] as List),
      positive: List<String>.from(json['positive'] as List),
    );
  }

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'warnings': warnings,
        'tips': tips,
        'positive': positive,
      };
}


class UploadResponse {
  final String uploadId;
  final String filename;
  final int transactionCount;
  final String uploadedAt;
  final String message;

  const UploadResponse({
    required this.uploadId,
    required this.filename,
    required this.transactionCount,
    required this.uploadedAt,
    required this.message,
  });

  factory UploadResponse.fromJson(Map<String, dynamic> json) {
    return UploadResponse(
      uploadId: json['upload_id'] as String,
      filename: json['filename'] as String,
      transactionCount: json['transaction_count'] as int,
      uploadedAt: json['uploaded_at'] as String,
      message: json['message'] as String,
    );
  }
}