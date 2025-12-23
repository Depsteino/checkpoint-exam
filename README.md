# 🚀 DevOps Exam - ECS Producer/Consumer Microservices

[![AWS](https://img.shields.io/badge/AWS-Cloud-orange)](https://aws.amazon.com)
[![Terraform](https://img.shields.io/badge/Terraform-IaC-purple)](https://www.terraform.io)
[![ECS](https://img.shields.io/badge/ECS-Container-blue)](https://aws.amazon.com/ecs)
[![GitHub Actions](https://img.shields.io/badge/GitHub-Actions-black)](https://github.com/features/actions)

Exam submission implementing a two‑service, event‑driven system on AWS ECS: an ALB‑fronted API validates payloads and publishes to SQS, and a worker consumes from SQS into S3. Infrastructure is provisioned via Terraform with CI/CD pipelines for build and deploy, plus monitoring via Grafana.

| Service | Demo URL | Description | Notes |
|---|---|---|---|
| Microservice 1 API (Health) | http://candidate-2-alb-1452912344.us-east-1.elb.amazonaws.com/health | REST API for Microservice 1; it awaits curl requests and publishes validated payloads to SQS. | Deployed for demo purposes only. If infra is destroyed, this link will not be available. You can redeploy using this repo. |
| Grafana | http://candidate-2-alb-1452912344.us-east-1.elb.amazonaws.com/grafana | Monitoring UI for Microservice 1/2 logs and metrics. | Deployed for demo purposes only. If infra is destroyed, this link will not be available. You can redeploy using this repo. |

---

## 📋 Quick Setup

### 1️⃣ Configure GitHub Secrets

Add AWS credentials to your repository secrets:

- 🔗 **[Go to GitHub Secrets](https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions)** (replace with your repo URL)
- Click **"New repository secret"**
- Add:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`

### 2️⃣ Bootstrap Infrastructure (One-Time)

Note: If the default Terraform state S3 bucket name is already taken, set the `TF_STATE_BUCKET` repository variable to a unique bucket name, then rerun the Bootstrap workflow.

- 🔗 **[Run Bootstrap Workflow](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/bootstrap.yaml)**
- Click **"Run workflow"** → Use defaults → **"Run workflow"**


### 3️⃣ Deploy Infrastructure

- 🔗 **[Run Infrastructure Workflow](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/infra.yaml)**
- Click **"Run workflow"**
- Set `action` to: **`apply`**
- Click **"Run workflow"**


### 4️⃣ Deploy Services

Push to `main` branch:
- CI workflow builds and pushes Docker images to ECR
- CD workflow deploys to ECS automatically

Or run manually:
- 🔗 **[CI Workflow](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/ci.yaml)** - Build images
- 🔗 **[CD Workflow](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/cd.yaml)** - Deploy to ECS

---

## 🧪 Test the API (simple)

1) Get **Terraform outputs** from the Infra workflow (ALB URL, Grafana URL, SSM param names).
2) Make sure your **AWS CLI is configured locally** for the same account/region.
3) Fetch the SSM token and run curl:

```bash
# ALB URL from outputs, if you deployed a new infra, the alb url will differ, make sure to adjust the ALB_URL value below.
ALB_URL=http://candidate-2-alb-1452912344.us-east-1.elb.amazonaws.com

# Get API token from SSM
TOKEN=$(aws ssm get-parameter \
  --name "/candidate-2/auth_token" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

# Call API
curl -X POST "$ALB_URL/" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "email_subject": "Hello Checkpoint!",
      "email_sender": "sender@example.com",
      "email_timestream": 1712851200,
      "email_content": "Happy New Year!"
    },
    "token": "'"${TOKEN}"'"
  }'
```

---

## 📊 Grafana Dashboard

> **Note:** The CloudWatch plugin can throw UI errors in Safari. Use **Firefox** or **Chrome** when viewing Grafana.

**URL:** `http://<ALB_DNS>/grafana/`

**Login:**
- Username: `admin`
- Password:
  ```bash
  aws ssm get-parameter \
    --name "/candidate-2/grafana_admin_password" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text
  ```

---
