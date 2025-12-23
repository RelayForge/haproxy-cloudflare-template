# Deployment Options

This guide covers different deployment methods for HAProxy configuration management.

## Option 1: Self-Hosted Runners (Recommended)

Best for: Production environments with dedicated HA nodes.

### Architecture

```
GitHub Repository
       │
       ▼ (push to main)
GitHub Actions
       │
       ├──► Self-hosted Runner (ha01) ──► HAProxy (ha01)
       ├──► Self-hosted Runner (ha02) ──► HAProxy (ha02)
       └──► Self-hosted Runner (ha03) ──► HAProxy (ha03)
```

### Setup

#### 1. Install Runner on Each HA Node

```bash
# Create runner directory
mkdir -p ~/actions-runner && cd ~/actions-runner

# Download runner (check for latest version)
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz
```

#### 2. Configure Runner

Go to your repository → **Settings** → **Actions** → **Runners** → **New self-hosted runner**

```bash
# Configure with token from GitHub
./config.sh --url https://github.com/YOUR-ORG/YOUR-REPO \
  --token YOUR-TOKEN \
  --name ha01 \
  --labels self-hosted,haproxy,ha01 \
  --unattended
```

#### 3. Install as Service

```bash
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

#### 4. Required Sudo Permissions

Add to `/etc/sudoers.d/haproxy-deploy`:

```sudoers
# Allow runner user to manage HAProxy without password
runner-user ALL=(ALL) NOPASSWD: /usr/sbin/haproxy -c -f *
runner-user ALL=(ALL) NOPASSWD: /bin/cp * /etc/haproxy/*
runner-user ALL=(ALL) NOPASSWD: /bin/mkdir -p /etc/haproxy/backup
runner-user ALL=(ALL) NOPASSWD: /bin/systemctl reload haproxy
runner-user ALL=(ALL) NOPASSWD: /bin/systemctl restart haproxy
runner-user ALL=(ALL) NOPASSWD: /bin/systemctl status haproxy
```

### Workflow Configuration

```yaml
# .github/workflows/deploy.yml
jobs:
  deploy:
    runs-on:
      - self-hosted
      - haproxy
      - ${{ matrix.node }}

    strategy:
      max-parallel: 1  # Rolling deployment
      matrix:
        include:
          - node: ha01
          - node: ha02
          - node: ha03
```

---

## Option 2: GitHub-Hosted Runners + SSH

Best for: When you can't install runners on HA nodes.

### Architecture

```
GitHub Repository
       │
       ▼ (push to main)
GitHub Actions (ubuntu-latest)
       │
       └──► SSH ──► HA Nodes (ha01, ha02, ha03)
```

### Setup

#### 1. Generate SSH Key

```bash
ssh-keygen -t ed25519 -C "github-deploy" -f deploy_key -N ""
```

#### 2. Add Public Key to HA Nodes

```bash
# On each HA node
echo "ssh-ed25519 AAAA... github-deploy" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

#### 3. Add Secrets to GitHub

| Secret | Value |
|--------|-------|
| `SSH_PRIVATE_KEY` | Contents of `deploy_key` |
| `SSH_KNOWN_HOSTS` | Output of `ssh-keyscan ha01 ha02 ha03` |
| `HA01_HOST` | `192.0.2.11` or `ha01.example.com` |
| `HA02_HOST` | `192.0.2.12` or `ha02.example.com` |
| `HA03_HOST` | `192.0.2.13` or `ha03.example.com` |
| `SSH_USER` | Username for SSH (e.g., `deploy`) |

### Workflow Example

```yaml
name: Deploy HAProxy (SSH)

on:
  push:
    branches: [main]
    paths: ['haproxy/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    strategy:
      max-parallel: 1
      matrix:
        include:
          - node: ha01
            host_secret: HA01_HOST
          - node: ha02
            host_secret: HA02_HOST
          - node: ha03
            host_secret: HA03_HOST

    steps:
      - uses: actions/checkout@v4

      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          echo "${{ secrets.SSH_KNOWN_HOSTS }}" > ~/.ssh/known_hosts

      - name: Deploy to ${{ matrix.node }}
        run: |
          HOST="${{ secrets[matrix.host_secret] }}"
          USER="${{ secrets.SSH_USER }}"

          # Copy config
          scp haproxy/haproxy.cfg ${USER}@${HOST}:/tmp/haproxy.cfg

          # Apply
          ssh ${USER}@${HOST} 'bash -s' << 'EOF'
            set -euo pipefail
            sudo cp /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg
            sudo haproxy -c -f /etc/haproxy/haproxy.cfg
            sudo systemctl reload haproxy
          EOF
```

---

## Option 3: Ansible

Best for: Existing Ansible infrastructure, complex deployments.

### Directory Structure

```
ansible/
├── inventory/
│   └── hosts.yml
├── playbooks/
│   └── deploy-haproxy.yml
├── roles/
│   └── haproxy/
│       ├── tasks/
│       │   └── main.yml
│       └── handlers/
│           └── main.yml
└── ansible.cfg
```

### Inventory

```yaml
# ansible/inventory/hosts.yml
all:
  children:
    haproxy_nodes:
      hosts:
        ha01:
          ansible_host: 192.0.2.11
        ha02:
          ansible_host: 192.0.2.12
        ha03:
          ansible_host: 192.0.2.13
      vars:
        ansible_user: deploy
        ansible_become: yes
```

### Playbook

```yaml
# ansible/playbooks/deploy-haproxy.yml
---
- name: Deploy HAProxy Configuration
  hosts: haproxy_nodes
  serial: 1  # Rolling deployment

  tasks:
    - name: Backup current configuration
      copy:
        src: /etc/haproxy/haproxy.cfg
        dest: "/etc/haproxy/backup/haproxy.cfg.{{ ansible_date_time.iso8601_basic }}"
        remote_src: yes
      ignore_errors: yes

    - name: Copy new configuration
      copy:
        src: "{{ playbook_dir }}/../../haproxy/haproxy.cfg"
        dest: /etc/haproxy/haproxy.cfg
        validate: /usr/sbin/haproxy -c -f %s
      notify: Reload HAProxy

  handlers:
    - name: Reload HAProxy
      systemd:
        name: haproxy
        state: reloaded
```

### GitHub Actions Workflow

```yaml
name: Deploy HAProxy (Ansible)

on:
  push:
    branches: [main]
    paths: ['haproxy/**']

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          echo "${{ secrets.SSH_KNOWN_HOSTS }}" > ~/.ssh/known_hosts

      - name: Install Ansible
        run: pip install ansible

      - name: Run Ansible Playbook
        working-directory: ansible
        run: |
          ansible-playbook \
            -i inventory/hosts.yml \
            playbooks/deploy-haproxy.yml
```

---

## Option 4: Docker Deployment

Best for: Containerized infrastructure, testing.

See [docker/README.md](../docker/README.md) for detailed Docker setup.

### Quick Start

```bash
cd docker
cp ../haproxy/haproxy.cfg.example ../haproxy/haproxy.cfg
docker compose up -d
```

### GitHub Actions with Docker

```yaml
name: Deploy HAProxy (Docker)

on:
  push:
    branches: [main]
    paths: ['haproxy/**', 'docker/**']

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519

      - name: Deploy to HA nodes
        run: |
          for HOST in ${{ secrets.HA01_HOST }} ${{ secrets.HA02_HOST }} ${{ secrets.HA03_HOST }}; do
            ssh ${{ secrets.SSH_USER }}@${HOST} << 'EOF'
              cd /opt/haproxy
              git pull
              docker compose up -d --build --wait
            EOF
          done
```

---

## Option 5: Manual Deployment

Best for: Single node, infrequent changes, testing.

### Steps

1. **SSH to HA node:**
   ```bash
   ssh user@ha01
   ```

2. **Backup current config:**
   ```bash
   sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/backup/haproxy.cfg.$(date +%Y%m%d_%H%M%S)
   ```

3. **Copy new config:**
   ```bash
   sudo cp /path/to/new/haproxy.cfg /etc/haproxy/haproxy.cfg
   ```

4. **Validate:**
   ```bash
   sudo haproxy -c -f /etc/haproxy/haproxy.cfg
   ```

5. **Reload:**
   ```bash
   sudo systemctl reload haproxy
   ```

6. **Verify:**
   ```bash
   sudo systemctl status haproxy
   curl -I http://localhost/health
   ```

---

## Comparison

| Method | Setup Complexity | Security | Best For |
|--------|------------------|----------|----------|
| Self-hosted Runners | Medium | High | Production, dedicated nodes |
| GitHub + SSH | Low | Medium | No runner installation |
| Ansible | High | High | Existing Ansible infra |
| Docker | Low | Medium | Containerized environments |
| Manual | None | N/A | Testing, single node |

## Choosing a Method

**Use Self-hosted Runners if:**
- You have dedicated HA nodes
- You want minimal external dependencies
- You need maximum security

**Use GitHub + SSH if:**
- You can't install runners on HA nodes
- You have a bastion/jump host
- Simple setup is preferred

**Use Ansible if:**
- You already use Ansible for configuration management
- You have complex pre/post deployment tasks
- You want idempotent deployments

**Use Docker if:**
- You run containerized infrastructure
- You want easy testing and development
- You use Kubernetes or Docker Swarm

**Use Manual for:**
- One-off testing
- Emergency fixes
- Learning HAProxy
