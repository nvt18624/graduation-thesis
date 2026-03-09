# Zero-trust and AI-driven in devsecops pipeline

> A production-ready graduation thesis project focused on designing a Zero-Trust system and providing an AI-driven mechanism to control and automatically roll back CI/CD pipelines when anomalies are detected in system logs.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Architecture Overview](#architecture-overview)
- [Infrastructure Configuration](#infrastructure-configuration)
  - [VM Setup](#vm-setup)
  - [ELK Cluster Configuration](#elk-cluster-configuration)
  - [Cloud Account Setup (AWS)](#cloud-account-setup-aws)
- [Installation](#installation)
  - [System Requirements](#system-requirements)
  - [Elasticsearch Setup](#elasticsearch-setup)
  - [Logstash Setup](#logstash-setup)
  - [Kibana Setup](#kibana-setup)
- [Network & Security Configuration](#network--security-configuration)
- [Log Pipeline Configuration](#log-pipeline-configuration)
- [Monitoring & Health Checks](#monitoring--health-checks)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## Prerequisites

Before proceeding with the setup, ensure all of the following infrastructure components are provisioned and accessible.

### Minimum Infrastructure Requirements

#### Virtual Machines (Minimum: 4 VMs)

You must provision **at least 7 VMs** with the following roles:

| VM | Role | Min CPU | Min RAM | Min Disk | OS |
|----|------|---------|---------|----------|----|
| `vm-app-01` | Application Server | 2 vCPU | 4 GB | 40 GB | Window server 2022 |
| `vm-app-02` | Application Server (HA) | 2 vCPU | 4 GB | 40 GB | Ubuntu 22.04 LTS |
| `vm-elk-01` | Elasticsearch | 4 vCPU | 8 GB | 100 GB | Ubuntu 22.04 LTS |
| `vm-elk-02` | Kibana| 4 vCPU | 8 GB | 100 GB | Ubuntu 22.04 LTS |
| `vm-elk-03` | Logstash | 4 vCPU | 8 GB | 80 GB | Ubuntu 22.04 LTS |
| `vm-dev-01` | Developer | 2 vCPU | 4 GB | 80 GB | Window 11 |
| `vm-dev-02` | Developer | 2 vCPU | 4 GB | 80 GB | Window 11 |

> **Note:** VMs `vm-elk-01`, `vm-elk-02`, and `vm-elk-03` form the **dedicated ELK logging cluster** (3 VMs). The remaining VMs host your application workloads and developer(dev) join, test.

#### ELK Logging Cluster (3 Dedicated VMs)
#### Public Cloud Account (Recommended: AWS)

You must have **at least one active public cloud account**. AWS is the recommended provider for this setup.

**Minimum required AWS services:**

- **EC2** — For provisioning cloud-based VMs (optional, but recommended for scalability)
- **S3** — For long-term log archiving and backup of Elasticsearch snapshots
- **IAM** — For access control and service-to-service authentication
- **VPC** — For network isolation and secure connectivity
- **Security Groups** — For firewall rules between services

**AWS IAM Minimum Permissions Required:**
