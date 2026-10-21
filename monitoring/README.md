# Robot Shop monitoring

The `monitoring` namespace must already have the `kube-prometheus-stack`
release installed as `monitoring`. Apply the Robot Shop scrape configuration,
HTTP/TCP probes, exporter, and Grafana dashboard from the repository root:

```powershell
kubectl apply -k .\monitoring
```

The ServiceMonitor scrapes `/metrics` from the Cart and Payment services.
Blackbox Exporter probes the web and service health endpoints, plus TCP
connectivity to the database and message-broker services. The dashboard is
provisioned automatically in Grafana as **Robot Shop Monitoring**.

Open Grafana locally with:

```powershell
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

Then browse to <http://localhost:3000> and open the **Robot Shop Monitoring**
dashboard.

The application images currently expose business metrics for Cart and Payment,
but do not expose general HTTP request counters or latency histograms. Blackbox
probe duration is synthetic endpoint latency, not per-request application
latency. Add application instrumentation and rebuild/deploy the relevant
images to graph true request rates, HTTP errors, and latency distributions.

Redis is currently Pending because its PVC requests the unavailable `standard`
StorageClass. The Redis TCP probe will remain down until the storage
configuration is corrected and Redis becomes Ready.

## OpenTelemetry traces

The Collector is installed as a single low-resource Deployment and forwards
OTLP traces to the Jaeger service. To install or update it:

```powershell
helm upgrade --install otel open-telemetry/opentelemetry-collector `
  --version 0.176.1 `
  --namespace monitoring `
  --values .\monitoring\otel-values.yaml
```

Instrumented applications in the cluster can send OTLP gRPC traces to
`otel-opentelemetry-collector.monitoring.svc.cluster.local:4317` or OTLP/HTTP
to `http://otel-opentelemetry-collector.monitoring.svc.cluster.local:4318`.
This Collector does not collect node/container logs or application metrics;
it adds one pod on existing cluster capacity and does not provision an AWS
node. Telemetry will appear in Jaeger only after applications are configured
to emit OTLP traces.

## Slack alert notifications

`values.yaml` configures Alertmanager to send alerts to the `#alerts` Slack
channel. Store the Slack Incoming Webhook URL in the `monitoring` namespace as
the `url` key of the `slack-webhook` Secret; never put the URL in this file or
commit it to Git. Alertmanager mounts this Secret at the file path configured
by `api_url_file`.

After updating the Secret with a rotated webhook, apply the values with:

```powershell
helm upgrade monitoring prometheus-community/kube-prometheus-stack `
  --version 92.11.0 `
  --namespace monitoring `
  --values .\monitoring\values.yaml
```

The default route sends alerts to Slack, except the `Watchdog` alert, which is
silenced by routing it to the `null` receiver.

## Grafana datasource defaults

Prometheus is the default Grafana datasource in kube-prometheus-stack. If the
Loki chart also marks Loki as default, recent Grafana versions can fail to
start because more than one datasource is marked as the default. Upgrade the
existing Loki release while preserving its other values:

```powershell
helm upgrade loki grafana/loki-stack `
  --version 2.10.3 `
  --namespace monitoring `
  --reuse-values `
  --values .\monitoring\loki-stack-values.yaml
```
