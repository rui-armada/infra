# Platform Infrastructure

Repositório de **Platform Engineering** que provisiona clusters Kubernetes locais com [Kind](https://kind.sigs.k8s.io/), instala [ArgoCD](https://argo-cd.readthedocs.io/) e faz bootstrap de toda a stack de plataforma via GitOps.

## Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                    clusters.yaml                             │
│            (declaração de teams + environments)              │
└────────────────────────────┬────────────────────────────────┘
                             │ terraform apply
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                   Terraform (platform/main.tf)               │
│   • Lê clusters.yaml                                        │
│   • Flatten teams × environments                            │
│   • Auto-assign de portas (HTTP + ArgoCD)                   │
│   • Chama module/cluster para cada entrada                  │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│              modules/cluster/main.tf                          │
│   1. Cria Kind cluster com NodePort mappings                 │
│   2. Instala ArgoCD via Helm CLI                             │
│   3. Cria App of Apps (platform tools)                       │
│   4. Cria Team Application (app do team)                     │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                  ArgoCD (auto-sync)                           │
│                                                              │
│   platform/apps/*.yaml ──► Platform Tools (Istio, Kyverno…) │
│   team repo helm chart ──► Team Application                  │
└─────────────────────────────────────────────────────────────┘
```

## Estrutura do Repositório

```
infra/
├── platform/
│   ├── clusters.yaml          # Configuração declarativa de clusters e teams
│   ├── main.tf                # Terraform root module
│   └── apps/                  # ArgoCD Application manifests (App of Apps)
│       ├── cert-manager.yaml
│       ├── istio.yaml
│       ├── monitoring.yaml    # Prometheus + Alertmanager
│       ├── grafana.yaml
│       ├── castai.yaml
│       ├── metrics-server.yaml
│       ├── reloader.yaml
│       ├── kyverno.yaml
│       ├── external-secrets.yaml
│       ├── keda.yaml
│       └── velero.yaml
└── modules/
    └── cluster/
        └── main.tf            # Module: Kind + ArgoCD + App of Apps + Team App
```

## Pré-requisitos

| Ferramenta | Versão mínima | Instalação |
|------------|---------------|------------|
| Docker Desktop | 4.x | [docker.com](https://www.docker.com/products/docker-desktop/) |
| Terraform | >= 1.0 | `brew install terraform` |
| Kind | >= 0.20 | `brew install kind` |
| Helm | >= 3.0 | `brew install helm` |
| kubectl | >= 1.28 | `brew install kubectl` |

## Quick Start

```bash
# 1. Clone o repositório
git clone https://github.com/rui-armada/infra.git
cd infra/platform

# 2. Inicializar Terraform
terraform init

# 3. Criar toda a plataforma
terraform apply

# 4. Aceder ao ArgoCD
# URL: http://localhost:8080
# User: admin
# Password:
kubectl get secret argocd-initial-admin-secret -n argocd \
  --context kind-<team>-<env> \
  -o jsonpath='{.data.password}' | base64 -d
```

## Configuração: clusters.yaml

Para adicionar teams ou ambientes, edita `platform/clusters.yaml` e faz `terraform apply`:

```yaml
platform_repo: https://github.com/rui-armada/infra.git

teams:
  - name: my-app
    repo: https://github.com/org/my-app.git
    chart_path: charts/my-app
    branch: main
    environments:
      - name: prod

  - name: payments
    repo: https://github.com/rui-armada/payments.git
    chart_path: charts/payments
    branch: main
    environments:
      - name: dev
      - name: staging
      - name: prod
```

Cada entrada `team × environment` cria:
- 1 Kind cluster (`<team>-<env>`)
- 1 ArgoCD instalação
- 1 App of Apps com todos os platform tools
- 1 Application para o app do team

### Auto-assign de Portas

As portas são atribuídas automaticamente por ordem alfabética dos cluster names:

| Cluster | App (HTTP) | ArgoCD |
|---------|-----------|--------|
| 1º cluster | localhost:3000 | localhost:8080 |
| 2º cluster | localhost:3001 | localhost:8081 |
| 3º cluster | localhost:3002 | localhost:8082 |

## Platform Tools (Bootstrap)

Todos os tools são instalados automaticamente via ArgoCD App of Apps:

| Componente | Versão | Namespace | Descrição |
|------------|--------|-----------|-----------|
| **cert-manager** | v1.16.3 | cert-manager | Gestão automática de certificados TLS |
| **Istio** | 1.24.0 | istio-system | Service mesh (mTLS, traffic management, observability) |
| **Prometheus + Alertmanager** | 67.4.0 | monitoring | Métricas e alerting (kube-prometheus-stack) |
| **Grafana** | 8.8.2 | monitoring | Dashboards de observabilidade |
| **CAST AI** | 0.75.0 | castai-agent | Otimização de custos cloud |
| **metrics-server** | 3.12.1 | kube-system | Métricas para HPA/VPA autoscaling |
| **Reloader** | 1.2.0 | reloader | Restart automático de pods quando ConfigMaps/Secrets mudam |
| **Kyverno** | 3.3.4 | kyverno | Policy engine (segurança, compliance, best practices) |
| **External Secrets** | 0.10.7 | external-secrets | Sync de secrets de providers externos (Vault, AWS SM, GCP) |
| **KEDA** | 2.16.1 | keda | Event-driven autoscaling (scale-to-zero, queues, cron) |
| **Velero** | 7.2.1 | velero | Backup e disaster recovery |

## Acessos

| Serviço | URL | Credenciais |
|---------|-----|-------------|
| ArgoCD | http://localhost:8080 | admin / `kubectl get secret ...` |
| Grafana | http://localhost:30090 | admin / admin |
| App (1º team) | http://localhost:3000 | — |

## Team Onboarding

Para adicionar um novo team à plataforma:

1. **Criar repo do team** no GitHub com a app + Helm chart em `charts/<app-name>/`
2. **Editar `clusters.yaml`** — adicionar entrada no array `teams`
3. **`terraform apply`** — cluster(s) criado(s) automaticamente
4. **Profit** — ArgoCD faz deploy automático do chart do team

### Estrutura esperada no repo do team:

```
my-team-repo/
├── src/                   # Código da app
├── Dockerfile
├── .github/workflows/     # CI/CD (build + push image)
└── charts/my-app/         # Helm chart
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── deployment.yaml
        ├── service.yaml
        └── namespace.yaml
```

## Operações

### Destruir um cluster específico

```bash
terraform destroy -target='module.cluster["<team>-<env>"]'
```

### Destruir tudo

```bash
terraform destroy
```

### Ver estado

```bash
terraform output clusters
```

### Re-sync ArgoCD manualmente

```bash
kubectl get applications -n argocd --context kind-<team>-<env>
argocd app sync platform --context kind-<team>-<env>
```

### Aceder a pods/serviços

```bash
kubectl get pods -A --context kind-<team>-<env>
kubectl get svc -n monitoring --context kind-<team>-<env>
```

## CI/CD Pipeline (Team Apps)

Os team repos usam GitHub Actions para build e push de imagens:

```
Push to main → Build Docker image (multi-platform) → Push to GHCR → ArgoCD auto-sync → Deploy
```

O ArgoCD monitoriza o branch configurado e faz auto-sync quando deteta alterações no Helm chart.

## Notas

- **Kind** é para desenvolvimento local. Para produção, substituir por EKS/GKE/AKS
- **CAST AI** requer `apiKey` e `clusterID` — preencher em `platform/apps/castai.yaml`
- **Velero** está configurado com MinIO como backend de storage (local)
- O Terraform state está local em `platform/terraform.tfstate` — considerar migrar para Terraform Cloud
- NodePort range: 30000-30090 está reservado para serviços da plataforma
