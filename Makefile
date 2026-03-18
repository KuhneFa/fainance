# ── Fainance Dev Commands ──────────────────────────────────────────────────────
.PHONY: up down logs backend flutter ollama test clean

## Alles nativ starten (ohne Docker) — empfohlen für Entwicklung
dev:
	@echo "🦙 Starte Ollama im Hintergrund..."
	@ollama serve &
	@sleep 2
	@echo "🚀 Starte Backend..."
	@cd fainance-backend && source venv/bin/activate && \
		uvicorn main:app --reload --port 8000 &
	@echo "🎨 Starte Flutter..."
	@cd apps/fainance_app && flutter run -d chrome
	@echo ""
	@echo "✅ Alle Services gestartet:"
	@echo "   Backend:  http://localhost:8000/docs"
	@echo "   Flutter:  http://localhost:8080"

## Nur Ollama starten (Hintergrund)
ollama:
	@echo "🦙 Starte Ollama..."
	@ollama serve &
	@echo "✅ Ollama läuft auf http://localhost:11434"

## Nur Backend starten
backend:
	@echo "🚀 Starte Backend..."
	@cd fainance-backend && source venv/bin/activate && \
		uvicorn main:app --reload --port 8000

## Nur Flutter starten
flutter:
	@echo "🎨 Starte Flutter..."
	@cd apps/fainance_app && flutter run -d chrome

## Docker: alles starten
up:
	@echo "🐳 Starte Docker Daemon..."
	@colima status 2>/dev/null | grep -q "Running" || \
		colima start --vm-type=qemu
	@echo "🚀 Starte Docker Services..."
	@cd docker && docker-compose up --build -d
	@echo ""
	@echo "✅ Bereit:"
	@echo "   Backend:  http://localhost:8000"
	@echo "   API Docs: http://localhost:8000/docs"

## Docker: alles stoppen
down:
	@cd docker && docker-compose down

## Docker: Logs
logs:
	@cd docker && docker-compose logs -f

## Tests ausführen
test:
	@cd fainance-backend && source venv/bin/activate && \
		pytest tests/test_parser.py -v

test-integration:
	@cd fainance-backend && source venv/bin/activate && \
		pytest tests/test_integration.py -v -s

## Docker aufräumen
clean:
	@cd docker && docker-compose down -v
	@docker system prune -f