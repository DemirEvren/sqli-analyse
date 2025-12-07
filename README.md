[![Review Assignment Due Date](https://classroom.github.com/assets/deadline-readme-button-22041afd0340ce965d47ae6ef1cefeee28c7c493a6346c4f15d667ab976d596c.svg)](https://classroom.github.com/a/LGE2D9CO)
# Kubernetes Examenopdracht

- [Applicatie: PXL Shelfware Tracker](#applicatie-pxl-shelfware-tracker)
- [Op te leveren](#op-te-leveren)
- [Opdracht: Minimum Requirements (10/20)](#opdracht-minimum-requirements-1020)
  - [Applicatie deployment](#applicatie-deployment)
  - [Container Images](#container-images)
  - [Kustomize Configuration](#kustomize-configuration)
  - [Load Testing (Cluster 2)](#load-testing-cluster-2)
  - [Deployment met ArgoCD](#deployment-met-argocd)
- [Extra Punten](#extra-punten)
  - [Extra 1: Automatische Deployment (2 punten)](#extra-1-automatische-deployment-2-punten)
  - [Extra 2: Pipeline Gating (2 punten)](#extra-2-pipeline-gating-2-punten)
  - [Extra 3: Prometheus/Grafana (3 punten)](#extra-3-prometheusgrafana-3-punten)
  - [Extra 4: Event-Driven Autoscaling (KEDA) (2 punten)](#extra-4-event-driven-autoscaling-keda-2-punten)
  - [Extra 5: Service Mesh \& mTLS (1 punt)](#extra-5-service-mesh--mtls-1-punt)
- [Belangrijk](#belangrijk)
- [ERRATA](#errata)

---

## Applicatie: PXL Shelfware Tracker

<https://github.com/PXL-Digital-Application-Samples/shelfware>

Je mag die src code in deze repo brengen.

---

## Op te leveren

Solution files/directories in `INFRA/` in deze repo.

Verplicht:

- `INFRA/OPERATIONS.md` met de exacte commands per subopdracht

  - cluster creatie
  - ArgoCD installatie
  - deployment van de applicatie
  - teststappen
- `INFRA/README.md` met een overzicht van de aanpak:

  - gebruikte tools (k3d, minikube, Terraform, cloudprovider, enz.)
  - architectuuroverzicht van de kustomize structuur
  - hoe de applicatie end-to-end getest kan worden
- Dockerfiles in `INFRA/` (mogen kopies zijn van elders in de repo)

Voorbeeld Kubernetes en ArgoCD configuratie:

```bash
INFRA/
├── kustomize/
│   ├── shelfware/           # De hoofdapplicatie
│   │   ├── base/
│   │   └── overlays/
│   │       ├── test/
│   │       └── prod/
│   └── locust/              # De loadtest cluster
│       ├── base/
│       └── overlays/
│           └── loadtest/
├── argocd/
│   ├── applications/
│   │   ├── test-app.yaml
│   │   ├── prod-app.yaml
│   │   └── locust-app.yaml
│   └── install.yaml
├── Dockerfile.*
├── OPERATIONS.md
└── README.md
```

CI/CD workflow:

```bash
.github/
└── workflows/
    └── build-and-deploy.yaml
```

Let op: GitHub Actions workflows moeten in `.github/workflows/` op repo-root staan om door GitHub gebruikt te worden. De infra-specifieke inhoud staat in `INFRA/`, de workflow verwijst daarnaar.

---

## Opdracht: Minimum Requirements (10/20)

Minpunten worden aangerekend per fout.
Niet-werkende applicatie: -6.

### Applicatie deployment

- De applicatie werkt volledig.
- De applicatie is toegankelijk via Ingress of Gateway API. Geen port-forwarding.
- De oplossing moet testbaar zijn vanaf een andere machine enkel op basis van deze repository.
- Alle manuele handelingen en configuratiestappen zijn gedocumenteerd in `INFRA/OPERATIONS.md`.
- Toegestane commands voor deployment per cluster:

  - 1 command voor de creatie van het cluster (bijvoorbeeld minikube op linux, docker desktop kubernetes op windows, k3d, kind, Terraform, cloud CLI, ...)
  - 1 command om argocd te deployen (bv kubectl op een directory)
  - 1 `kubectl` command om alle Kubernetes resources te deployen (bijvoorbeeld een directory apply)

### Container Images

Maak automatisch container images aan als GitHub Packages bij creatie van een nieuwe GitHub tag.

- Gebruik GitHub Actions.
- Bouw images voor alle services.
- Gebruik de GitHub tag als image tag, bijvoorbeeld:

  - tag `TEST_v0.8` resulteert in `ghcr.io/<org>/shelfware-frontend:TEST_v0.8`
  - tag `PROD_v1.0` resulteert in `ghcr.io/<org>/shelfware-api:PROD_v1.0`
- Naamgeving van tags:

  - TEST labels beginnen met `TEST_` (bijvoorbeeld `TEST_v0.8`)
  - PROD labels beginnen met `PROD_` (bijvoorbeeld `PROD_v1.0`)

### Kustomize Configuration

Gebruik Kustomize om 2 environments te definiëren via overlays: `test` en `prod` (directorynamen) voor de TEST en PROD omgevingen.

**Service Scaling Requirements:**

- **TEST Environment:**

  - Frontend: 1 fixed replica
  - Backend: 1 fixed replica
  - Database: 1 fixed replica met PVC van minstens 5Gi
  - Resource limits:
    - standaard: 500Mi RAM per container

- **PROD Environment:**

  - Frontend: autoscaling (HPA v2): Configureer een HorizontalPodAutoscaler met de volgende eisen:
    - Scale op basis van CPU utilization (target average: 70%).
    - Constraints: Minimaal 1 replica, maximaal 3 replicas.
    - Smoothing / Stabilization: voorkom "flapping".
  - Backend: 1 replica (fixed).
  - Database: 1 replica (fixed).
  - Resource limits & requests:
    - Configureer voor alle pods zinnige CPU/Memory requests en limits. Zonder requests kan de HPA geen percentages berekenen.

**Technische Requirements:**

- PostgreSQL moet een StatefulSet zijn met persistent storage (PVC).
- Environment variabelen moeten via ConfigMaps en Secrets beheerd worden (niet hardcoded in Deployments).

### Load Testing (Cluster 2)

Deploy Locust op de `loadtest` cluster om de stabiliteit van de applicatie op de `app` cluster te verifiëren.

- Locust deployment en service gedefinieerd in YAML.
- Het `locustfile.py` script moet in een **ConfigMap** staan en als volume gemount worden in de Pod.
- Het script simuleert GET requests naar `/` en `/api/projects`.
  - Werkende testrun (geen 100% errors) naar de PROD omgeving.
- Locust (Cluster 2) moet verbinden met het extern endpoint van Cluster 1 (bv. `http://shelfware-prod.local`), geen port-forwards.
- Locust Web UI mag via port-forwarding.

### Deployment met ArgoCD

We simuleren een echte omgeving met twee gescheiden clusters:

1. **Applicatie Cluster:** draait de Shelfware applicatie.
2. **Loadtest Cluster:** draait de Locust tool.

**Per cluster:**

- Installeer ArgoCD declaratief.
- Deploy met ArgoCD de juiste software op de juiste cluster:
  - **Op App Cluster:** Deploy Shelfware TEST (`test-shelfware` namespace) en PROD (`prod-shelfware` namespace) via de Kustomize overlays in `INFRA/kustomize/shelfware/overlays/...`.
  - **Op Loadtest Cluster:** Deploy Locust (`locust` namespace) via de Kustomize overlay in `INFRA/kustomize/locust/overlays/...`.
- **Ingress:**
  - PROD: <http://shelfware.local>
  - TEST: <http://test.shelfware.local>
- Alles blijft binnen deze repo. ArgoCD Applications verwijzen naar de paden in deze repo.
- ArgoCD Applications moeten automatisch synchroniseren (auto-sync).

---

## Extra Punten

Enkel mogelijk wanneer de minimum requirements 100 procent zijn voldaan.

### Extra 1: Automatische Deployment (2 punten)

Automatische deployment van de juiste environment zonder manuele stappen:

Github:

- Creatie van GitHub tag `TEST_v0.9` triggert:

  - automatische image builds voor beide services
  - automatische update van de image tags in de Kustomize files voor TEST (bijvoorbeeld `images:` sectie in `INFRA/kustomize/shelfware/overlays/test/kustomization.yaml`)
  - commit en push van deze wijzigingen naar de repo
  - ArgoCD pikt de wijzigingen op en deployt naar de TEST namespace.
- Zelfde flow voor PROD tags (`PROD_*`), maar dan naar de PROD namespace.
- Gebruik GitHub Actions om `kustomization.yaml` (of aparte image manifests) te updaten.

ArgoCD:

- Alles wordt gedeployed via GitOps principes.
- ArgoCD wordt zelf declaratief opgezet met Application (en eventueel ApplicationSet) CRDs.
- ArgoCD apps worden beheerd via IaC: manifests in `INFRA/argocd/applications/`, niet via CLI of UI clicks.
- **Gebruik een App of Apps pattern voor environment management:**
  - **bijvoorbeeld een root Application die `test-app.yaml` en `prod-app.yaml` beheert.**

---

### Extra 2: Pipeline Gating (2 punten)

In plaats van Locust manueel te draaien, moet dit onderdeel worden van de CI/CD pipeline (of een aparte 'nightly build' workflow).

- Integreer de locus loadtest in een GitHub Actions workflow. Wanneer er een nieuwe release naar `TEST` gaat, moet er automatisch een korte loadtest draaien.
- De test moet falen als de **Average Response Time** boven de 500ms komt, OF als de **Error Rate** boven de 1% komt.
- Als de test faalt, mag de promotie naar `PROD` niet doorgaan (of moet de pipeline rood kleuren).
- Zorg dat je met een kleine tweak ook de negatieve werking van deze workflow kan triggeren/testen/demonstreren.

---

### Extra 3: Prometheus/Grafana (3 punten)

- Installeer Prometheus en Grafana in de applicatie cluster (bijvoorbeeld via de kube-prometheus-stack Helm chart) op een declaratieve IaC manier.
- Bouw een geavanceerd Grafana Dashboard specifiek voor de Backend API, gebaseerd op de Google SRE standaarden.
  - Operations teams sturen op de "Four Golden Signals".
    1. **Latency:** P95 en P99 histogrammen (niet gemiddeldes!).
    2. **Traffic:** Requests per seconde (uitgesplitst per HTTP method: GET vs POST).
    3. **Errors:** Percentage gefaalde requests (5xx codes) t.o.v. totaal.
    4. **Saturation:** Hoeveel "werk" kan de pod nog aan? (Visualiseer CPU throttling of Memory limits).
  - Dit dashboard komt automatisch in de installatie via IaC (dus niet via de "Import" knop)

---

### Extra 4: Event-Driven Autoscaling (KEDA) (2 punten)

**Deze extra is enkel mogelijk als je eerst de prometheus extra voldaan hebt.**

Standaard HPA (Horizontal Pod Autoscaler) scalet op CPU/Memory. In de echte wereld is dit vaak te traag. We willen scalen op basis van **incoming traffic** (HTTP requests) voordat de CPU spike plaatsvindt.

- Vervang de standaard HPA door **KEDA** (Kubernetes Event-driven Autoscaling).
  - Installeer KEDA in de cluster.
  - Configureer een `ScaledObject` voor de **Frontend**.
  - Gebruik de **Prometheus Scaler**: scale de frontend pods op basis van de query `sum(rate(http_requests_total[2m]))`.
  - Als er meer dan 10 requests per seconde per pod zijn, scale up.

**Deliverables:**

- Grafana screenshot waarin te zien is dat de *Replicas* omhoog gaan gelijktijdig met de *Request Rate* (en niet pas als CPU volloopt).

---

### Extra 5: Service Mesh & mTLS (1 punt)

**Deze extra is enkel mogelijk als je eerst de prometheus extra voldaan hebt.**

- Implementeer **Linkerd** (of Istio of een andere service mesh) als Service Mesh declaratief via IaC.
- Al het verkeer tussen Frontend en Backend moet versleuteld zijn en geauthenticeerd via mTLS.
- Zet de service mesh UI op (mag manueel)
  - Toon een dashboard dat automatisch de Success Rate, Request Volume en Latency toont van de communicatie tussen frontend en backend op basis van data de service mesh.
- In grafana:
  - Maak deze info, op basis van service mesh data, beschikbaar in een customized grafana dashboard.

---

## Belangrijk

- De oplossing moet testbaar zijn vanaf een andere machine of cloudomgeving, via de ingediende repository en de gedocumenteerde stappen.

- Deliverables worden beoordeeld op het moment van de deadline.

  - Als de ingeleverde oplossing niet werkt, of als de clusters tijdens de demo verschillen van de ingeleverde oplossing, wordt dit expliciet vermeld met een volledige lijst van veranderingen. Niet vermelden betekent score 0.
  - Je wordt beoordeeld op de toestand van de inzending op de deadline.
  - Alle bestanden moeten voor de deadline ingecheckt zijn. Bestanden die zelfs 1 seconde te laat zijn, worden genegeerd.
  - Commits na de deadline leveren -2 punten op en worden niet behandeld.

- Er moet regelmatig gecommit worden naar GitHub: minstens 1 commit per uur effectief werk. Niet naleven betekent score 0. Hiervoor mag een tool gebruikt worden.

- Er wordt uitsluitend individueel gewerkt.

- Plagiaat is verboden (zie PXL-examenreglement). Straffen kunnen gaan tot uitsluiting van alle examens.

  - De persoon die oplossingen doorgeeft, is ook schuldig aan plagiaat.
  - Er mag niet gecommuniceerd worden over de PE met andere studenten. Dit geldt als plagiaat.

- Controleer datum en tijd van de deadline.

- Test je deployment grondig voordat je indient.

- Zorg dat de applicatie echt werkt, niet alleen gedeployed is.

---

## ERRATA

Mogelijke errata en extra verduidelijkingen worden gepubliceerd op Blackboard als mededelingen en discussies.
