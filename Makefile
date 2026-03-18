# ── Fainance Dev Commands ──────────────────────────────────────────────────────
.PHONY: dev ollama backend flutter up down logs test k8s-up k8s-build k8s-status k8s-forward k8s-down clean

# ── Nativ (empfohlen für Entwicklung) ─────────────────────────────────────────

## Alles nativ starten: Ollama + Backend + Flutter
dev:
	@echo "🦙 Starte Ollama im Hintergrund..."
	@ollama serve > /tmp/ollama.log 2>&1 & echo "   PID: $$!"
	@sleep 2
	@echo "🚀 Starte Backend im Hintergrund..."
	@cd fainance-backend && source venv/bin/activate && \
		uvicorn main:app --reload --port 8000 > /tmp/backend.log 2>&1 & \
		echo "   PID: $$!"
	@sleep 2
	@echo "🎨 Starte Flutter (öffnet Browser)..."
	@echo ""
	@echo "📋 Logs: tail -f /tmp/ollama.log /tmp/backend.log"
	@echo "   Backend:  http://localhost:8000/docs"
	@cd apps/fainance_app && flutter run -d chrome

## Nur Ollama
ollama:
	@echo "🦙 Starte Ollama..."
	@ollama serve

## Nur Backend
backend:
	@echo "🚀 Starte Backend..."
	@cd fainance-backend && source venv/bin/activate && \
		uvicorn main:app --reload --port 8000

## Nur Flutter
flutter:
	@echo "🎨 Starte Flutter..."
	@cd apps/fainance_app && flutter run -d chrome

# ── Docker ────────────────────────────────────────────────────────────────────

## Docker: alles starten
up:
	@echo "🐳 Prüfe Docker Daemon..."
	@colima status 2>/dev/null | grep -q "Running" || \
		colima start --vm-type=qemu
	@echo "🚀 Starte Docker Services..."
	@cd docker && docker-compose up --build -d
	@echo ""
	@echo "✅ Bereit:"
	@echo "   Backend:  http://localhost:8000/docs"

## Docker: stoppen
down:
	@cd docker && docker-compose down

## Docker: Logs live
logs:
	@cd docker && docker-compose logs -f

# ── Tests ─────────────────────────────────────────────────────────────────────

## Unit Tests
test:
	@cd fainance-backend && source venv/bin/activate && \
		pytest tests/test_parser.py -v

## Integrationstests (Backend muss laufen)
test-integration:
	@cd fainance-backend && source venv/bin/activate && \
		pytest tests/test_integration.py -v -s

# ── Kubernetes ────────────────────────────────────────────────────────────────

## minikube starten + alle Manifeste deployen
## Nutzt nur 2 CPUs — passend für MacBook mit 2 Cores
k8s-up:
	@echo "☸️  Starte minikube..."
	@minikube start --memory=2048 --cpus=2 --driver=docker
	@echo "📦 Deploye Manifeste..."
	@kubectl apply -f k8s/namespace.yaml
	@kubectl apply -f k8s/backend/configmap.yaml
	@kubectl apply -f k8s/backend/deployment.yaml
	@kubectl apply -f k8s/backend/service.yaml
	@echo ""
	@echo "⚠️  Ollama separat starten: make ollama"
	@echo "⏳ Pods starten... (kubectl get pods -n fainance -w)"

## Backend Image bauen und in minikube laden (nach k8s-up ausführen)
k8s-build:
	@echo "🔨 Baue Backend Image in minikube..."
	@minikube image build -t fainance-backend:latest \
		-f docker/backend/Dockerfile .
	@echo "✅ Image geladen — Pods neu starten:"
	@kubectl rollout restart deployment/backend -n fainance

## Status aller Pods
k8s-status:
	@echo "── Pods ──────────────────────────────"
	@kubectl get pods -n fainance
	@echo ""
	@echo "── Services ──────────────────────────"
	@kubectl get services -n fainance

## Port-Forward: Backend auf localhost:8000
k8s-forward:
	@echo "🔗 Backend → http://localhost:8000/docs"
	@echo "   (Ctrl+C zum Beenden)"
	@kubectl port-forward -n fainance service/backend 8000:8000

## Logs eines Pods anzeigen (Beispiel: make k8s-logs POD=backend)
k8s-logs:
	@kubectl logs -n fainance deployment/$(POD) --follow

## Alles löschen
k8s-down:
	@kubectl delete namespace fainance --ignore-not-found
	@minikube stop
	@echo "✅ Kubernetes gestoppt"

# ── Aufräumen ─────────────────────────────────────────────────────────────────

## Docker und Volumes löschen
clean:
	@cd docker && docker-compose down -v
	@docker system prune -f