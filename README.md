# fainance
Application to analyse your own finances privately and secure

# Architecture
```text
┌─────────────────────────────────────────┐
│           Flutter App (Mobile)          │
│                                         │
│  📁 CSV Upload Screen                   │
│  📊 Dashboard Screen (Charts)           │
│  💡 Insights Screen (LLM Tipps)         │
│                                         │
│  Packages: fl_chart, dio, file_picker   │
└─────────────────┬───────────────────────┘
                  │ HTTP REST (localhost)
┌─────────────────▼───────────────────────┐
│           FastAPI Backend               │
│                                         │
│  POST /upload-csv   → CSV parsen        │
│  GET  /analysis     → Aggregationen     │
│  POST /insights     → LLM anfragen      │
│                                         │
│  pandas (CSV) + SQLite (Speicher)       │
└──────────┬──────────────────────────────┘
           │
┌──────────▼──────────────────────────────┐
│         Ollama (localhost:11434)         │
│         Modell: mistral:7b-instruct-q4  │
└─────────────────────────────────────────┘
```

# Flutter
```text
lib/
├── main.dart                  ← App-Einstiegspunkt, Theme
├── core/
│   ├── api_client.dart        ← HTTP-Kommunikation mit FastAPI
│   ├── models.dart            ← Dart-Versionen unserer Pydantic-Models
│   └── theme.dart             ← Farben, Schriften, dark theme
├── features/
│   ├── upload/
│   │   └── upload_screen.dart
│   ├── dashboard/
│   │   └── dashboard_screen.dart
│   └── insights/
│       └── insights_screen.dart
└── widgets/
    └── stat_card.dart         ← Wiederverwendbare UI-Komponenten
```