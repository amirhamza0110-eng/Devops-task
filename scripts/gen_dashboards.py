#!/usr/bin/env python3
"""Generates Grafana dashboard JSON into monitoring/grafana/dashboards/ (committed output)."""
import json
import pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "monitoring/grafana/dashboards"
PROM = {"type": "prometheus", "uid": "prometheus"}
LOKI = {"type": "loki", "uid": "loki"}


def ts(pid, title, x, y, w, targets, unit="short"):
    return {"id": pid, "type": "timeseries", "title": title, "datasource": PROM,
            "gridPos": {"x": x, "y": y, "w": w, "h": 8}, "fieldConfig": {"defaults": {"unit": unit}, "overrides": []},
            "targets": [{"expr": e, "legendFormat": leg, "refId": chr(65 + i), "datasource": PROM}
                        for i, (e, leg) in enumerate(targets)]}


def logs(pid, title, x, y, w, expr):
    return {"id": pid, "type": "logs", "title": title, "datasource": LOKI,
            "gridPos": {"x": x, "y": y, "w": w, "h": 10},
            "options": {"showTime": True, "wrapLogMessage": True, "sortOrder": "Descending"},
            "targets": [{"expr": expr, "refId": "A", "datasource": LOKI}]}


def dash(uid, title, panels):
    return {"uid": uid, "title": title, "schemaVersion": 39, "version": 1, "refresh": "10s",
            "time": {"from": "now-30m", "to": "now"}, "tags": ["devops-task"], "panels": panels}


def q(p):
    return f'histogram_quantile({p}, sum by (le) (rate(http_request_duration_seconds_bucket{{job="app"}}[5m])))'
app = dash("app", "Application", [
    ts(1, "Request rate (req/s)", 0, 0, 8, [('sum(rate(http_requests_total{job="app"}[1m]))', "total"),
       ('sum by (path) (rate(http_requests_total{job="app"}[1m]))', "{{path}}")], "reqps"),
    ts(2, "Error rate (5xx ratio)", 8, 0, 8, [('sum(rate(http_errors_total{job="app"}[1m])) / clamp_min(sum(rate(http_requests_total{job="app"}[1m])), 1e-9)', "5xx ratio")], "percentunit"),
    ts(3, "Latency p50/p95/p99", 16, 0, 8, [(q(0.5), "p50"), (q(0.95), "p95"), (q(0.99), "p99")], "s"),
    logs(4, "App logs (errors) - same time range", 0, 8, 12, '{service="app", level="error"}'),
    logs(5, "App logs (all)", 12, 8, 12, '{service="app"}'),
])
host = dash("host", "Host", [
    ts(1, "CPU usage %", 0, 0, 12, [('100 - avg(rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100', "cpu")], "percent"),
    ts(2, "Memory usage %", 12, 0, 12, [('(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100', "mem")], "percent"),
    ts(3, "Disk usage % by mountpoint", 0, 8, 12, [('100 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay|squashfs"} * 100', "{{mountpoint}}")], "percent"),
    ts(4, "Network throughput", 12, 8, 12, [('sum by (device) (rate(node_network_receive_bytes_total{device!="lo"}[1m]))', "rx {{device}}"),
       ('sum by (device) (rate(node_network_transmit_bytes_total{device!="lo"}[1m]))', "tx {{device}}")], "Bps"),
])
cont = dash("containers", "Containers", [
    ts(1, "CPU per container (cores)", 0, 0, 12, [('sum by (name) (rate(container_cpu_usage_seconds_total{name!=""}[1m]))', "{{name}}")], "short"),
    ts(2, "Memory working set per container", 12, 0, 12, [('container_memory_working_set_bytes{name!=""}', "{{name}}")], "bytes"),
    ts(3, "Memory usage vs limit (%)", 0, 8, 24, [('container_memory_working_set_bytes{name!=""} / (container_spec_memory_limit_bytes{name!=""} > 0) * 100', "{{name}}")], "percent"),
])
OUT.mkdir(parents=True, exist_ok=True)
for name, d in [("application", app), ("host", host), ("containers", cont)]:
    (OUT / f"{name}.json").write_text(json.dumps(d, indent=2))
    print("wrote", name)
