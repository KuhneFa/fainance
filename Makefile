# ── Fainance ───────────────────────────────────────────────────────────────────
.PHONY: flutter ios test clean dev up down logs k8s-up k8s-build k8s-status k8s-forward k8s-logs k8s-down

# ── Flutter (Hauptentwicklung) ─────────────────────────────────────────────────

## Flutter Web starten
flutter:
	@cd apps/fainance_app && flutter run -d chrome

## Flutter iOS starten
ios:
	@cd apps/fainance_app && flutter run -d ios

## Flutter Tests
test:
	@cd apps/fainance_app && flutter test

## Build-Cache leeren
clean:
	@cd apps/fainance_app && flutter clean && flutter pub get

# ── Docker (nice2have) ─────────────────────────────────────────────────────────

## Docker: Backend + Ollama starten
up:
	@echo "🐳 Prüfe Docker Daemon..."
	@colima status 2>/dev/null | grep -q "Running" || \
		colima start --vm-type=qemu
	@echo "🚀 Starte Docker Services..."
	@cd docker && docker-compose up --build -d
	@echo "✅ Backend: http://localhost:8000/docs"

## Docker: stoppen
down:
	@cd docker && docker-compose down

## Docker: Logs live
logs:
	@cd docker && docker-compose logs -f

# ── Kubernetes (nice2have) ─────────────────────────────────────────────────────

## minikube + alle Manifeste deployen
k8s-up:
	@echo "☸️  Starte minikube..."
	@minikube start --memory=2048 --cpus=2 --driver=docker
	@kubectl apply -f k8s/namespace.yaml
	@kubectl apply -f k8s/backend/configmap.yaml
	@kubectl apply -f k8s/backend/deployment.yaml
	@kubectl apply -f k8s/backend/service.yaml
	@echo "⏳ Status: make k8s-status"

## Backend Image in minikube laden
k8s-build:
	@minikube image build -t fainance-backend:latest \
		-f docker/backend/Dockerfile .
	@kubectl rollout restart deployment/backend -n fainance

## Pod-Status
k8s-status:
	@kubectl get pods,services -n fainance

## Backend auf localhost:8000 forwarden
k8s-forward:
	@echo "🔗 http://localhost:8000/docs (Ctrl+C zum Beenden)"
	@kubectl port-forward -n fainance service/backend 8000:8000

## Pod-Logs (make k8s-logs POD=backend)
k8s-logs:
	@kubectl logs -n fainance deployment/$(POD) --follow

## Alles löschen
k8s-down:
	@kubectl delete namespace fainance --ignore-not-found
	@minikube stop