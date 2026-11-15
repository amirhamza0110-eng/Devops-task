## Observability & Dashboards

The local monitoring stack is fully provisioned as code, utilizing Prometheus, Loki, Grafana, Grafana Alloy, cAdvisor, and Node Exporter. 

*(Note: As this was tested locally on Windows Docker Desktop (WSL2 backend), the host and container metrics captured by Node Exporter and cAdvisor represent the underlying WSL utility VM rather than a native Linux host. Full hardware metrics will be visible when deployed on a native Linux production server.)*

### Dashboard Screenshots
Below are the captures of the dashboards visualizing the generated traffic and metrics:

**1. Application Dashboard**
![Application Dashboard](docs/dashboard-application.png)

**2. Host Dashboard**
![Host Dashboard](docs/dashboard-host.png)

**3. Containers Dashboard**
![Containers Dashboard](docs/dashboard-containers.png)

### Troubleshooting Walkthrough
**Scenario:** *An error spike appears on the Application dashboard. How do you find the cause using these tools?*

1. **Identify the Scope:** I would first look at the **Application Dashboard** to identify the exact timeframe of the 5xx error spike and isolate which specific endpoint (e.g., `/boom`) is failing.
2. **Analyze Logs in Context:** Since Loki is integrated directly alongside the metrics, I would scroll down to the attached Logs panel and filter by `level="ERROR"` to read the structured JSON log payloads for the exact error trace.
3. **Check Resource Saturation:** If the logs indicate a timeout or crash, I would switch to the **Containers Dashboard** (cAdvisor data) to check if the application container was throttling on CPU or hitting its memory limit (potential OOMKilled). 
4. **Inspect the Host:** Finally, I would check the **Host Dashboard** (Node Exporter data) to rule out underlying infrastructure issues, such as a full disk or network saturation.

## Kubernetes Deployment & Rollback

The application is configured for Kubernetes deployment utilizing standard manifests, prioritizing zero-downtime rolling updates and declarative state management.

**Update & Rollback Test Evidence:**
After deploying version `1.0.1`, a rollback operation to `1.0.0` was executed successfully to demonstrate quick recovery capabilities during an incident.

```bash
$ kubectl -n devops-task rollout undo deploy/devops-task
deployment.apps/devops-task rolled back

$ kubectl -n devops-task rollout status deploy/devops-task
Waiting for deployment "devops-task" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "devops-task" rollout to finish: 1 old replicas are pending termination...
deployment "devops-task" successfully rolled out

## ⚙️ Linux Automation Script (System Health)

A robust bash script (`scripts/system_health.sh`) is included to monitor host CPU, Memory, Disk usage, Load Average, and top memory-consuming processes. It supports configurable thresholds, JSON output, proper exit codes for monitoring tools, and log rotation.

### Manual Execution
To test the script manually and view the structured JSON output:
```bash
chmod +x scripts/system_health.sh
./scripts/system_health.sh --json

{
  "timestamp": "2026-11-15T12:15:06Z",
  "host": "DESKTOP-AT8EGAS",
  "cpu_percent": 54,
  "mem_percent": 100,
  "load": { "1m": 0.52, "5m": 0.58, "15m": 0.59 },
  "disks": [
    { "mount": "/", "percent": 30 },
    { "mount": "/mnt/c", "percent": 30 },
    { "mount": "/mnt/e", "percent": 1 }
  ],
  "top_memory": [
    { "pid": 11, "command": "bash", "mem_percent": 0.0 },
    { "pid": 100, "command": "ps", "mem_percent": 0.0 }
  ],
  "status": 2,
  "warnings": [
    "[CRITICAL] Memory usage at 100% (>= 95%)"
  ]
}
Automation (Systemd / Cron)
For production use, the repository includes systemd service and timer files to run the script every 5 minutes automatically.

Bash
# Setup using Systemd
sudo cp scripts/systemd/system-health.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now system-health.timer

# Alternatively, a crontab example is provided:
crontab scripts/systemd/crontab.example