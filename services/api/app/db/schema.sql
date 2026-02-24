-- transactions
CREATE TABLE IF NOT EXISTS transactions (
  id TEXT PRIMARY KEY,
  booking_date TEXT NOT NULL,          -- ISO date: YYYY-MM-DD
  amount_cents INTEGER NOT NULL,       -- negative = Ausgabe, positive = Einnahme
  currency TEXT NOT NULL DEFAULT 'EUR',
  description TEXT NOT NULL,
  merchant TEXT,
  category TEXT NOT NULL DEFAULT 'Unkategorisiert',
  source TEXT NOT NULL DEFAULT 'csv',
  raw_hash TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(booking_date);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category);
CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_rawhash ON transactions(raw_hash);

-- simple rules
CREATE TABLE IF NOT EXISTS category_rules (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pattern TEXT NOT NULL,     -- keyword or regex
  category TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 100
);

CREATE INDEX IF NOT EXISTS idx_rules_priority ON category_rules(priority);
