# 🚀 DevOps Exam - ECS Producer/Consumer Microservices

[![AWS](https://img.shields.io/badge/AWS-Cloud-orange)](https://aws.amazon.com)
[![Terraform](https://img.shields.io/badge/Terraform-IaC-purple)](https://www.terraform.io)
[![ECS](https://img.shields.io/badge/ECS-Container-blue)](https://aws.amazon.com/ecs)
[![GitHub Actions](https://img.shields.io/badge/GitHub-Actions-black)](https://github.com/features/actions)

An exam-ready, event-driven microservices architecture on AWS ECS with automated CI/CD pipelines.

---

## 📋 Quick Setup

### 1️⃣ Configure GitHub Secrets

Add AWS credentials to your repository secrets:

- 🔗 **[Go to GitHub Secrets](https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions)** (replace with your repo URL)
- Click **"New repository secret"**
- Add:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`

> 💡 **Don't have AWS credentials?**  
> Create them at: [AWS IAM Console](https://console.aws.amazon.com/iam/home#/security_credentials)

### 2️⃣ Bootstrap Infrastructure (One-Time)

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
# Get ALB DNS from outputs (or copy from workflow output)
ALB_DNS=$(terraform -chdir=infra output -raw alb_url | sed 's|http://||')

# Get API token from SSM
TOKEN=$(aws ssm get-parameter \
  --name "/candidate-2/auth_token" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

# Call API
curl -X POST "http://$ALB_DNS/" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "email_subject": "Hello",
      "email_sender": "sender@example.com",
      "email_timestream": 1712851200,
      "email_content": "Body text"
    },
    "token": "'"${TOKEN}"'"
  }'
```

---

## 📊 Grafana Dashboard

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

> **Note:** The CloudWatch plugin can throw UI errors in Safari. Use **Firefox** or **Chrome** when viewing Grafana.

---
