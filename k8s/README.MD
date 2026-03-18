# Fainance — Kubernetes Setup

## Voraussetzungen

```bash
brew install minikube kubectl
minikube start --memory=8192 --cpus=4   # 8GB RAM für Ollama
```

## Deployment

```bash
# Einmalig: Namespace + alle Ressourcen anlegen
make k8s-up

# Image bauen und in minikube laden
make k8s-build

# Status prüfen
make k8s-status

# Backend erreichbar machen
make k8s-forward
```

## Struktur

```
k8s/
├── namespace.yaml          Namespace: fainance
├── backend/
│   ├── configmap.yaml      Umgebungsvariablen (OLLAMA_BASE_URL etc.)
│   ├── deployment.yaml     2 Replicas, Liveness/Readiness Probes, PVC
│   └── service.yaml        ClusterIP intern + NodePort für lokalen Zugriff
└── ollama/
    ├── pvc.yaml            10Gi für Modelle (persistent über Restarts)
    ├── deployment.yaml     1 Replica, InitContainer lädt Modell
    └── service.yaml        ClusterIP — nur Backend hat Zugriff
```

## Warum diese Struktur?

**Backend: 2 Replicas** — das Backend ist stateless (SQLite liegt auf PVC),
kann also horizontal skaliert werden. Kubernetes verteilt Requests automatisch.

**Ollama: 1 Replica + Recreate** — LLMs profitieren nicht von horizontaler
Skalierung ohne GPU-Koordination. `Recreate` statt `RollingUpdate` weil
der PVC `ReadWriteOnce` ist — nur ein Pod kann gleichzeitig schreiben.

**InitContainer für Modell-Pull** — der Hauptcontainer startet erst wenn
das Modell fertig geladen ist. Kein Race Condition zwischen Backend und Ollama.

## Proxmox-Integration (später)

Für Production auf Proxmox:
1. Terraform provisioniert VMs auf Proxmox
2. kubeadm oder k3s richtet Kubernetes ein
3. Diese Manifeste werden auf dem echten Cluster deployed

Siehe: `terraform/` (noch nicht erstellt)
