
# Zero-Trust and AI-Driven DevSecOps Pipeline

> A production-ready graduation thesis project that designs a Zero-Trust CI/CD system and provides an AI-driven mechanism to automatically detect anomalies in system logs and roll back pipelines when threats are identified.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
  - [Virtual Machines](#virtual-machines)
  - [AWS Cloud Account](#aws-cloud-account)
- [Infrastructure Configuration](#infrastructure-configuration)
  - [AD and CA Server Setup](#ad-and-ca-server-setup)
  - [GitLab Server Setup](#gitlab-server-setup)
  - [Terraform AWS IaC Setup](#terraform-aws-iac-setup)
- [Developer Onboarding](#developer-onboarding)
  - [Export AD Certificate](#export-ad-certificate)
  - [Convert Certificate to PEM](#convert-certificate-to-pem)
  - [Configure Git to Use the Certificate](#configure-git-to-use-the-certificate)
- [GitLab Runner Registration](#gitlab-runner-registration)
- [Admin CI/CD Pipeline](#admin-cicd-pipeline)
- [ML Model Training](#ml-model-training)
- [AI Anomaly Detection Pipeline](#ai-anomaly-detection-pipeline)
- [Log Pipeline Configuration](#log-pipeline-configuration)

---

## Architecture Overview

<p align="center">
  <img src="references/architectures/ECS.png" alt="Existing control strategies" width="70%" />
  <br/>
  <em>Existing control strategies</em>
</p>

<p align="center">
  <img src="references/architectures/zero-trust-flow.png" alt="Zero-trust pipeline flow" width="70%" />
  <br/>
  <em>Zero-trust pipeline flow</em>
</p>

<p align="center">
  <img src="references/architectures/aws.png" alt="AWS network design (production zero-trust cloud)" width="70%" />
  <br/>
  <em>AWS network design — production zero-trust cloud</em>
</p>

<p align="center">
  <img src="references/architectures/AI.png" alt="AI detection & rollback loop" width="70%" />
  <br/>
  <em>AI detection &amp; rollback loop</em>
</p>

---

## Prerequisites

### Virtual Machines

You must provision **at least 8 VMs** with the following roles:

| VM | Role | Min CPU | Min RAM | Min Disk | OS |
|----|------|---------|---------|----------|----|
| `vm-server-01` | AD and CA Server | 2 vCPU | 4 GB | 40 GB | Windows Server 2022 |
| `vm-server-02` | GitLab Server | 2 vCPU | 8 GB | 80 GB | Ubuntu 22.04 LTS |
| `vm-elk-01` | Elasticsearch + Kibana | 4 vCPU | 8 GB | 100 GB | Ubuntu 22.04 LTS |
| `vm-elk-02` | Logstash | 4 vCPU | 8 GB | 80 GB | Ubuntu 22.04 LTS |
| `vm-app-01` | Application 1 | 1 vCPU | 4 GB | 40 GB | Ubuntu 22.04 LTS |
| `vm-app-02` | Application 2 | 1 vCPU | 4 GB | 40 GB | Ubuntu 22.04 LTS |
| `vm-dev-01` | Developer | 2 vCPU | 4 GB | 80 GB | Windows 11 |
| `vm-dev-02` | Developer | 2 vCPU | 4 GB | 80 GB | Windows 11 |

> `vm-elk-01` and `vm-elk-02` form the dedicated SIEM/ELK logging cluster. The remaining VMs host application workloads and developer endpoints.

### AWS Cloud Account

AWS is the recommended cloud provider. The following services are used:

| Service | Purpose |
|---------|---------|
| **Amazon EC2** | Cloud-based VMs for applications and SIEM stack |
| **Amazon ECR** | Container image registry per application (with lifecycle policies) |
| **Amazon S3** | Long-term log archiving, model artifacts, Elasticsearch snapshots |
| **AWS IAM** | Fine-grained access control and least-privilege roles per developer |
| **Amazon VPC** | Network isolation with public, private-app, private-SIEM, and private-data subnets |
| **Security Groups** | Instance-level firewall rules |
| **ALB / NLB** | Load balancing across application instances |
| **Route Tables + IGW** | Traffic routing and internet access for public subnets |
| **NAT Gateway** | Outbound internet access for private subnet instances |
| **AWS Network Firewall** | Advanced traffic filtering and intrusion prevention |
| **AWS Lambda** | Serverless inference and rollback automation |
| **Amazon EventBridge** | Scheduled trigger for anomaly detection Lambda |
| **Amazon SNS** | Alert notifications on anomaly detection |
| **AWS SSM** | Remote command execution for pipeline rollback |

<p align="center">
  <img src="references/readme/IAM_admin.png" alt="IAM admin example" width="70%" />
  <br/>
  <em>Example IAM setup for admin</em>
</p>

---

## Infrastructure Configuration

### AD and CA Server Setup

The Active Directory (AD) and Certificate Authority (CA) setup is documented in:  
`src/config/guides/P0_AD_CA.pdf`

Install **Winlogbeat** following the official guide:  
[Winlogbeat Installation & Configuration](https://www.elastic.co/docs/reference/beats/winlogbeat/winlogbeat-installation-configuration)

After installation, copy the configuration file `src/config/scripts/P0_winlogbeat` to your Winlogbeat installation directory, then restart the service:

```powershell
Restart-Service winlogbeat
```

> Update the Logstash server IP address inside the Winlogbeat configuration file before restarting.

---

### GitLab Server Setup

#### 1. Run the installation script

Copy `src/config/scripts/P0_gitlab_server_install.sh`, grant execute permission, and run it:

```bash
chmod +x P0_gitlab_server_install.sh
./P0_gitlab_server_install.sh
```

This installs GitLab, NGINX, and Filebeat.

#### 2. Configure Filebeat

Copy `src/config/scripts/P0_filebeat.yml` to `/etc/filebeat/filebeat.yml`, then restart:

```bash
sudo systemctl restart filebeat.service
```

> Update the Logstash server IP address in `/etc/filebeat/filebeat.yml`.

#### 3. Configure GitLab

Copy `src/config/scripts/P0_gitlab.rb` to `/etc/gitlab/gitlab.rb`, then apply:

```bash
sudo systemctl restart gitlab.slice gitlab-runsvdir.service
```

> Configure the username and password inside `gitlab.rb` before restarting.

#### 4. Configure NGINX reverse proxy

Copy `src/config/scripts/P1_ngxin_proxy` to `/etc/nginx/sites-available/gitlab-frontend`, then restart:

```bash
sudo systemctl restart nginx.service
```

> Ensure the certificate path in the NGINX config matches the actual certificate location used for AD integration. Install the root CA certificate before enabling AD authentication.

#### 5. Install Semgrep on the GitLab server

The pre-receive hook requires Semgrep to be installed in a dedicated virtualenv at `/opt/semgrep-venv`:

```bash
sudo python3 -m venv /opt/semgrep-venv
sudo /opt/semgrep-venv/bin/pip install semgrep
# Verify
/opt/semgrep-venv/bin/semgrep --version
```

#### 6. Configure Git hooks (Semgrep SAST)

Copy `src/config/scripts/P1_pre-receive_hook.sh` to `/opt/gitlab/embedded/service/gitlab-shell/hooks/pre-receive.d/semgrep.sh` and make it executable:

```bash
sudo chmod +x /opt/gitlab/embedded/service/gitlab-shell/hooks/pre-receive.d/semgrep.sh
```

This hook runs Semgrep static analysis on every push. Pushes to protected branches (`main`, `master`, `developer`, `production`, `dev1`, `dev2`) are **blocked** on findings; pushes to `feature` branches produce warnings only. Scan results are shipped to Logstash for centralized logging.

> After Terraform apply, update `LOGSTASH_URL` in the hook file to match the actual Logstash EC2 public IP (`terraform output logstash_public`). The hook defaults to a hardcoded IP if the variable is not set.

---

### Terraform AWS IaC Setup

All AWS infrastructure is defined under `src/IaC/` using Terraform modules.

#### Module layout

| Module | Resources |
|--------|-----------|
| `network` | VPC, public/private subnets, IGW, NAT Gateway, route tables, VPC endpoints |
| `security_groups` | ALB, Bastion, NLB, ELK, and DB security groups |
| `iam` | IAM roles and instance profiles for the ELK stack |
| `iam_users` | Per-developer IAM users, ECR repos, app security groups, rollback Lambda |
| `load_balancers` | ALB with dynamic listeners per application port |
| `instance` | Generic EC2 instance module (Bastion, ELK, Logstash, App VMs) |
| `anomaly_detection` | Inference Lambda, EventBridge schedule, SNS alert topic |
| `firewall` | AWS Network Firewall rules |

#### Pre-Terraform checklist

Before running `terraform init`, two S3 buckets must already exist:

| Bucket | Purpose |
|--------|---------|
| `thien-sa-terraform-backend` | Terraform remote state (referenced in `backend.tf`) |
| `zt-devsecops-logs` | Logstash log archive, ML model artifacts, Lambda log reads |

Create them in the AWS console or CLI (`aws s3 mb s3://<bucket-name> --region ap-southeast-1`) before proceeding.

The Inference Lambda also requires a **Lambda Layer** containing `scikit-learn` and `numpy` for Python 3.12. Build and publish it once:

```bash
mkdir -p lambda-layer/python
pip install scikit-learn numpy -t lambda-layer/python
cd lambda-layer && zip -r sklearn-layer.zip python/
aws lambda publish-layer-version \
  --layer-name sklearn-numpy-py312 \
  --zip-file fileb://sklearn-layer.zip \
  --compatible-runtimes python3.12 \
  --region ap-southeast-1
```

Copy the returned `LayerVersionArn` — you will need it as `sklearn_layer_arn` in `terraform.tfvars`.

#### Setup

1. Fill in `src/IaC/terraform.tfvars`. Required fields:

```hcl
network_name   = "zt-devsecops"
key_name       = "aws"               # EC2 key pair name in AWS
alert_email    = "you@example.com"
sklearn_layer_arn = "arn:aws:lambda:ap-southeast-1:<account-id>:layer:sklearn-numpy-py312:1"

# CIDRs allowed to SSH into the Bastion host
admin_cidr_blocks     = ["<your-ip>/32"]
# On-premise network allowed to push logs to Logstash (ports 5044, 8080)
onpremise_cidr_blocks = ["<on-premise-cidr>/24"]

apps = {
  app2 = { app_port = 3000 }
}

dev_users = {
  dev1 = { allowed_apps = ["app2"] }
  dev2 = { allowed_apps = ["app2"] }
}
```

2. Configure the remote state backend in `src/IaC/backend.tf`.

3. Initialize and apply:

```bash
cd src/IaC
terraform init
terraform plan
terraform apply
```

The Terraform run provisions the full AWS environment, copies setup scripts to EC2 instances over SSH via the Bastion host, deploys the Lambda functions, and bootstraps app EC2 instances with Docker CE + AWS CLI v2 via `scripts/docker.sh` so they are ready to pull and run containers from ECR immediately.

#### Post-apply: ELK stack initialization (manual steps)

Terraform copies the scripts but does **not** run them. After `terraform apply` completes, the admin must initialize the ELK stack in order:

**Step 1 — SSH into the ELK VM via Bastion and run `elas.sh`:**

```bash
# Step 1 — SSH into Bastion with agent forwarding
ssh -A -i C:\Users\LENOVO\.ssh\aws.pem ubuntu@<bastion-public-ip>

# Step 2 — From Bastion, SSH into the ELK VM (no key file needed, agent forwarding handles it)
ssh ubuntu@10.0.3.10

# On the ELK VM
chmod +x elas.sh
./elas.sh
```

This installs Elasticsearch and auto-generates credentials saved to:
- `/home/ubuntu/elastic_password.txt` — password for the `elastic` superuser
- `/home/ubuntu/password_kibana_system.txt` — password for the `kibana_system` user
- `/home/ubuntu/token-kibana.txt` — enrollment token for Kibana

**Step 2 — Run `kibana.sh` on the same ELK VM:**

```bash
chmod +x kibana.sh
./kibana.sh
```

`kibana.sh` reads `password_kibana_system.txt` automatically and configures Kibana to connect to Elasticsearch.

**Step 3 — Get the `elastic` password and fill it into `logstash.sh`:**

```bash
cat /home/ubuntu/elastic_password.txt
```

Open `logstash.sh` and replace the placeholder password with the actual `elastic` password in all three Elasticsearch output blocks:

```
password => "<elastic-password-from-step-3>"
```

**Step 4 — SSH into the Logstash VM via Bastion and run `logstash.sh`:**

```bash
# Step 1 — SSH into Bastion with agent forwarding
ssh -A -i C:\Users\LENOVO\.ssh\aws.pem ubuntu@<bastion-public-ip>

# Step 2 — From Bastion, SSH into the Logstash VM
ssh ubuntu@10.0.1.12

# On the Logstash VM
chmod +x logstash.sh
./logstash.sh
```

This installs Logstash, configures the pipeline (Beats on port `5044`, HTTP on port `8080`), sets up S3 log backup, and starts the service.

#### Post-apply: distribute IAM credentials to developers

After `terraform apply`, retrieve and distribute each developer's AWS access key:

```bash
terraform output -json user_credentials
```

This returns the `access_key_id` and `secret_access_key` for every IAM user defined in `dev_users`. The admin must securely deliver each developer their own credentials — these are used in the GitLab project's CI/CD variables so the pipeline can authenticate to ECR and SSM.

Also note the ECR repository URLs for each app:

```bash
terraform output ecr_urls
```

These URLs are set as CI/CD variables in GitLab (`ECR_REGISTRY`, etc.) so the pipeline can push images to the correct repository.

> See `src/config/guides/P0_Register_Gitlab_runner.pdf` for GitLab runner registration.

---

## Developer Onboarding

Each developer machine (`vm-dev-01`, `vm-dev-02`) must be joined to the Active Directory domain and have its AD-issued certificate configured before it can clone from or push to GitLab. GitLab is protected by mTLS via NGINX — unauthenticated clients are rejected at the proxy level.

### Export AD Certificate

On the developer's Windows machine, open **Manage user certificates** (search `certmgr.msc`), find the certificate issued by `TCOMP-CA` under **Personal → Certificates**, then:

1. Right-click the certificate → **All Tasks** → **Export**
2. Click **Next** on the Certificate Export Wizard
3. Select **Yes, export the private key** → **Next**
4. Choose format: **Personal Information Exchange – PKCS #12 (.PFX)**
   - Check: **Include all certificates in the certification path if possible**
   - Check: **Enable certificate privacy**
5. Set a password for the exported file (TripleDES-SHA1 encryption)
6. Choose an output path, e.g. `C:\Users\dev2\Downloads\dev2.pfx` → **Finish**

### Convert Certificate to PEM

Open **Git Bash** on the developer machine, navigate to the download folder and convert the `.pfx` to an unencrypted `.pem`:

```bash
openssl pkcs12 -in dev2.pfx -out dev2-encrypted.pem -nodes
```

### Configure Git to Use the Certificate

Open **PowerShell** and run the following commands (replace `dev2` with the actual username):

```powershell
# Clear any previously set SSL config (domain-specific)
git config --global --unset-all http."https://gitlab.zt.devsecops.local/".sslVerify
git config --global --unset-all http."https://gitlab.zt.devsecops.local/".sslCert
git config --global --unset-all http."https://gitlab.zt.devsecops.local/".sslKey
git config --global --unset-all http."https://gitlab.zt.devsecops.local/".sslCertPasswordProtected
git config --global --unset-all http."https://gitlab.zt.devsecops.local/".sslBackend

# Clear global SSL config
git config --global --unset-all http.sslCert
git config --global --unset-all http.sslKey
git config --global --unset-all http.sslCertPasswordProtected
git config --global --unset-all http.sslBackend
git config --global --unset-all http.sslVerify

# Switch Git to OpenSSL backend
git config --global http.sslBackend openssl

# Point Git at the developer's certificate for the GitLab domain
git config --global http."https://gitlab.zt.devsecops.local/".sslVerify false
git config --global http."https://gitlab.zt.devsecops.local/".sslCert "C:/Users/dev2/Downloads/dev2-encrypted.pem"
git config --global http."https://gitlab.zt.devsecops.local/".sslKey  "C:/Users/dev2/Downloads/dev2-encrypted.pem"
```

Verify the configuration and test a clone:

```powershell
git config --global --list | findstr gitlab
git clone https://gitlab.zt.devsecops.local/<group>/<repo>.git
```

> For a detailed visual walkthrough, see `src/config/guides/P0_Clone_project.pdf`.

---

## GitLab Runner Registration

The GitLab Runner authenticates to GitLab via an AD-signed client certificate (mTLS). The runner runs as a Docker container on the GitLab server (`vm-server-02`, `10.0.1.2`).

#### 1. Generate RSA key and CSR on the GitLab server

```bash
mkdir -p /etc/gitlab-runner/client-certs
cd /etc/gitlab-runner/client-certs

# Generate RSA private key
sudo openssl genrsa -traditional -out runner-client.key 2048

# Generate Certificate Signing Request
sudo openssl req -new \
  -key runner-client.key \
  -subj "/CN=gitlabrunner/OU=DevSecOps/O=ZT" \
  -out runner-client.csr
```

#### 2. Sign the CSR with the AD Certificate Authority

Copy the CSR to the AD/CA Windows server (`vm-server-01`), sign it using the **User** template, then copy the signed certificate back:

```powershell
# On the AD/CA server (Windows) — copy CSR from GitLab server
scp -P 2222 ubuntu@10.0.1.2:/etc/gitlab-runner/client-certs/runner-client.csr C:\Users\Administrator\Downloads\

# Sign with the CA User template
certreq -submit -attrib "CertificateTemplate:User" `
  C:\Users\Administrator\Downloads\runner-client.csr `
  C:\Users\Administrator\Downloads\runner-client.crt

# Copy the signed cert back to the GitLab server
scp -P 2222 C:\Users\Administrator\Downloads\runner-client.crt ubuntu@10.0.1.2:/tmp/
```

#### 3. Install and verify the certificate

```bash
sudo mv /tmp/runner-client.crt /etc/gitlab-runner/client-certs/

# Convert key to RSA traditional format
sudo openssl pkey \
  -in /etc/gitlab-runner/client-certs/runner-client.key \
  -out /etc/gitlab-runner/client-certs/runner-client-rsa.key \
  -traditional

# Verify that the certificate and key match (MD5 hashes must be identical)
sudo openssl x509 -noout -modulus -in runner-client.crt | openssl md5
sudo openssl rsa  -noout -modulus -in runner-client-rsa.key | openssl md5
```

#### 4. Run the GitLab Runner container

```bash
sudo docker run -d \
  --name gitlab-runner \
  --restart always \
  --add-host "gitlab.zt.devsecops.local:10.0.1.2" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v gitlab-runner-config:/etc/gitlab-runner \
  gitlab/gitlab-runner:latest
```

#### 5. Copy certificates into the container

```bash
# Server CA cert (for runner to trust GitLab's TLS)
sudo docker exec -it gitlab-runner mkdir -p /etc/gitlab-runner/certs
sudo docker cp /etc/ssl/certs/gitlab.crt \
  gitlab-runner:/etc/gitlab-runner/certs/gitlab.zt.devsecops.local.crt

# Client cert and key (for mTLS authentication)
sudo docker cp /etc/gitlab-runner/client-certs/runner-client.crt \
  gitlab-runner:/etc/gitlab-runner/runner-client.crt
sudo docker cp /etc/gitlab-runner/client-certs/runner-client-rsa.key \
  gitlab-runner:/etc/gitlab-runner/runner-client.key
```

#### 6. Register the runner

In the GitLab UI, go to **Project → Settings → CI/CD → Runners → New project runner** and copy the registration token. Then run:

```bash
sudo docker exec -it gitlab-runner gitlab-runner register \
  --url "https://gitlab.zt.devsecops.local" \
  --token "TOKEN" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --docker-network-mode "host" \
  --tls-cert-file "/etc/gitlab-runner/runner-client.crt" \
  --tls-key-file  "/etc/gitlab-runner/runner-client.key" \
  --non-interactive
```

#### 7. Verify

```bash
sudo docker exec -it gitlab-runner gitlab-runner list
```

A registered runner should appear in **Project → Settings → CI/CD → Runners** with status **online**.

> For a detailed visual walkthrough, see `src/config/guides/P0_Register_Gitlab_runner.pdf`.

---

## Admin CI/CD Pipeline

The admin creates a dedicated GitLab project that holds the **shared pipeline configuration** (`P4_gitlab-ci.yml`). In GitLab Admin Area, this file is set as the **Required Pipeline Configuration**, which means it is injected and run at the start of every project's pipeline across the entire instance — before the developer's own branch pipeline runs.

```
Dev pushes code to branch
         │
         ▼
  pre-receive hook (Semgrep SAST – server-side)
         │  blocked if findings on protected branch
         ▼
  GitLab CI starts
         │
         ├── 1. Admin pipeline runs first  (P4_gitlab-ci.yml — enforced by GitLab)
         │         • Security scan (Trivy image scan, Semgrep CI scan)
         │         • Build Docker image
         │         • Tag image:  sha-$CI_COMMIT_SHORT_SHA
         │         • Push to ECR  →  EventBridge picks it up → auto-deploy
         │
         └── 2. Developer's own .gitlab-ci.yml (if present in their branch)
                   • App-specific steps (tests, linting, etc.)
```

#### How to configure (admin steps)

1. In GitLab, create a project (e.g. `root/graduation-thesis-test`) and add `P4_gitlab-ci.yml` as `.gitlab-ci.yml` in that project.

2. Go to **Admin Area → Settings → CI/CD → Required pipeline configuration** and set:

   ```
   root/graduation-thesis-test:.gitlab-ci.yml@main
   ```

3. Set the following **CI/CD variables** at the GitLab instance or group level (**Protected + Masked**). Variables are scoped per developer — add one set per dev user:

   | Variable | Scope | Description |
   |----------|-------|-------------|
   | `DEV1_AWS_ACCESS_KEY_ID` | All | IAM access key for `dev1` (from `terraform output user_credentials`) |
   | `DEV1_AWS_SECRET_ACCESS_KEY` | All | IAM secret key for `dev1` |
   | `DEV1_EC2_HOST` | All | Private IP of the EC2 instance `dev1` is allowed to deploy to |
   | `DEV1_ECR` | All | ECR repository URL for `dev1`'s app (from `terraform output ecr_urls`) |
   | `DEV2_AWS_ACCESS_KEY_ID` | All | IAM access key for `dev2` |
   | `DEV2_AWS_SECRET_ACCESS_KEY` | All | IAM secret key for `dev2` |
   | `DEV2_EC2_HOST` | All | Private IP of the EC2 instance `dev2` is allowed to deploy to |
   | `DEV2_ECR` | All | ECR repository URL for `dev2`'s app |
   | `LOGSTASH_URL` | All | Logstash HTTP endpoint for CI log shipping (e.g. `http://<logstash-public-ip>:8080`) |

   To add more developers, extend the pattern: `DEV3_AWS_ACCESS_KEY_ID`, `DEV3_AWS_SECRET_ACCESS_KEY`, `DEV3_EC2_HOST`, `DEV3_ECR`, and so on.

From this point on every developer push — on any branch, in any project — will automatically run through the admin pipeline (security scan + build + ECR push) before their own pipeline stage executes.

> For the full GitLab project and RBAC setup, refer to `src/config/guides/P2_UI_Setup.pdf`.

---

## ML Model Training

The anomaly detection model is an **Isolation Forest** trained on Windows authentication event features extracted from Elasticsearch logs.

**Feature columns used:**

| Feature | Description |
|---------|-------------|
| `login_count` | Total login attempts in window |
| `unique_users` | Number of distinct users |
| `unique_source_ips` | Number of distinct source IPs |
| `machine_account_ratio` | Ratio of machine account logins |
| `ipv6_ratio` | Ratio of IPv6 source addresses |
| `failed_login_count` | Total failed login attempts |
| `hour_of_day` | Hour of the time window |
| `day_of_week` | Day of the week |

**To train and publish the model:**

> The log pipeline must be running and have collected data into `s3://zt-devsecops-logs/logs/` before training. `feature_extraction.py` reads directly from S3 — there is no data if Logstash has not yet shipped any logs.

```bash
cd src/ml
pip install -r requirements.txt
python train.py
```

The script reads historical Windows auth logs from S3 (`zt-devsecops-logs`), aggregates them into time-windowed feature vectors, trains the Isolation Forest + StandardScaler, and uploads the serialized model and metadata to S3:

- `s3://zt-devsecops-logs/model/auth_anomaly_detector.pkl`
- `s3://zt-devsecops-logs/model/auth_anomaly_metadata.json`

---

## AI Anomaly Detection Pipeline

### Image tag lifecycle

A key design decision: the `stable` label is **not a Docker image tag**. It is a value stored in AWS SSM Parameter Store. Every image pushed to ECR carries a `sha-<commit>` tag. Promotion to "stable" only happens after the AI monitoring window passes clean.

```
Dev / CI pushes image
        │  tag: sha-<commit>   (e.g. sha-abc1234)
        ▼
   Amazon ECR
        │
        │  EventBridge ECR Push Rule (matches tag prefix "sha-")
        ▼
   SSM AWS-RunShellScript on EC2 (tag:App = <app>)
        │  • docker pull sha-<commit>
        │  • docker stop/rm old container
        │  • docker run new container
        │  • ssm put-parameter  /{prefix}/{app}/pending-tag = sha-<commit>
        ▼
   App is running the new image
   pending-tag = sha-<commit>      ← not yet trusted
   stable-tag  = sha-<prev>        ← last known-good
```

At this point the new image is **live but not promoted**. Promotion only happens if the AI monitoring window comes back clean:

```
EventBridge Schedule (every N minutes)
        │
        ▼
Inference Lambda
        │
        ├── 1. Read Windows auth logs from S3 (last N-minute window)
        ├── 2. Load Isolation Forest + scaler from S3 (cached on warm start)
        ├── 3. Extract features (login counts, failed logins, IP ratios, etc.)
        ├── 4. Score against threshold
        │
        ├── CLEAN (score ≥ threshold)
        │       └── promote  pending-tag → stable-tag  in SSM
        │           /{prefix}/{app}/stable-tag = sha-<commit>
        │
        └── ANOMALY (score < threshold)
                ├── Invoke Rollback Lambda (async) for each app
                └── Publish alert to SNS topic (email)
```

### Rollback flow

When the Inference Lambda triggers a rollback, the Rollback Lambda (`src/IaC/modules/iam_users/lambda/index.py`) executes the following:

1. Read `/{prefix}/{app}/stable-tag` and `/{prefix}/{app}/port` from SSM Parameter Store.
2. Find the running EC2 instance by `tag:App = <app>`.
3. Send SSM `AWS-RunShellScript` to that instance:
   - Pull the stable image from ECR (`sha-<stable-tag>`)
   - Stop and remove the current container
   - Start the stable image container on the same port

> If `stable-tag` is still `none` (no clean window has passed yet since the first deploy), the rollback returns a 404 and no action is taken.

### SSM Parameter Store keys

| Parameter | Written by | Read by | Description |
|-----------|-----------|---------|-------------|
| `/{prefix}/{app}/port` | Terraform | Rollback Lambda | Container port |
| `/{prefix}/{app}/pending-tag` | EventBridge SSM deploy command | Inference Lambda | Tag of the last deployed image, not yet verified |
| `/{prefix}/{app}/stable-tag` | Inference Lambda (on clean window) | Rollback Lambda | Tag of the last verified-safe image |

All Lambda environment variables (S3 bucket, model keys, window duration, app list, SNS topic ARN, rollback Lambda ARN) are injected by Terraform at deploy time.

---

## Log Pipeline Configuration

Logs flow from all system components into the centralized ELK stack:

```
Windows AD / CA (Winlogbeat)  ──┐
GitLab Server (Filebeat)      ──┤──► Logstash (vm-elk-02 / EC2 public)
App Containers (Filebeat)     ──┘          │
                                           ▼
                                   Elasticsearch (vm-elk-01 / EC2 private SIEM)
                                           │
                                           ├── Kibana (dashboards + alerting)
                                           └── S3 (snapshot / long-term archive)
```

- Logstash listens on port `8080` (HTTP) for log ingestion from Filebeat and Winlogbeat agents.
- Elasticsearch and Kibana run on the private SIEM subnet (`10.0.3.0/24`) — not directly internet-accessible.
- Logstash runs on the public subnet (`10.0.1.0/24`) to accept on-premise log traffic.
- Setup scripts for each component are in `src/IaC/scripts/` and are provisioned automatically by Terraform.

For GitLab project setup and RBAC configuration, refer to: `src/config/guides/P2_UI_Setup.pdf`
