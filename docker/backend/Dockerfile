# ── Build Stage ────────────────────────────────────────────────────────────────
# Multi-Stage Build: erst Dependencies installieren, dann nur das Nötigste
# in das finale Image kopieren. Ergebnis: kleineres, sichereres Image.
FROM python:3.12-slim AS builder

WORKDIR /app

# Nur requirements zuerst kopieren — Docker cached diesen Layer.
# Wenn sich nur der Code ändert aber nicht die Dependencies,
# muss pip install nicht erneut laufen. Spart viel Zeit.
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Final Stage ────────────────────────────────────────────────────────────────
FROM python:3.12-slim

WORKDIR /app

# Dependencies aus Builder-Stage übernehmen
COPY --from=builder /install /usr/local

# App-Code kopieren
COPY . .

# Sicherheit: App nicht als root laufen lassen
# Falls jemand die App hackt, hat er keinen root-Zugriff auf den Container
RUN useradd --no-create-home --shell /bin/false appuser
USER appuser

# Port dokumentieren (nur Doku, kein echtes Mapping)
EXPOSE 8000

# Healthcheck: Docker prüft alle 30s ob die App noch läuft
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/')"

# Kein --reload in Produktion!
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]