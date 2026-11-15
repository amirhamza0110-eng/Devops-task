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
