# fainance
Application to analyse your own finances privately and secure

# Architecture
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