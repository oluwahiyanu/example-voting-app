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
