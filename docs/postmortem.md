# Robot Shop incident postmortem

**Status:** Drill write-up — recovery outcome is written as a completed
scenario at the user's request. The live cluster was not verified recovered
when this document was written; see [Live-state verification](#live-state-verification).

## Summary

Robot Shop's Redis pod could not start, leaving Redis without an endpoint.
Requests to the user API returned HTTP 500, degrading account and shopping
flows. The web pod remained Running and served the frontend, but that did not
mean the complete customer journey was healthy.

In the completed-drill scenario, Redis was restored after its storage
configuration and provisioning prerequisites were corrected. Service
readiness was then confirmed through pod, endpoint, and application checks.

## Customer impact

- The frontend pod remained available.
- User API requests returned HTTP 500 while Redis was unavailable.
- Redis-dependent user and cart operations were degraded or unavailable.
- Product ratings and synthetic load were temporarily scaled down to make
  room for recovery workloads.
- Monitoring did not deliver a confirmed Slack notification during the drill;
  the Alertmanager Slack change had been rolled back.

## Timeline

Times are approximate and in local time (UTC+01:00), based on command output
and Kubernetes events.

- **13:14** — Incident drill began. Robot Shop pods, events, and Helm history
  were inspected. Most application pods were Running; Redis was Pending.
- **During initial checks** — The web pod had a Ready endpoint, but its logs
  showed user API requests returning HTTP 500. The local port-forward ended
  after its target pod sandbox was removed.
- **During mitigation** — The Redis claim was found requesting the nonexistent
  `standard` StorageClass. The chart default was changed to the available
  `gp2` class, and the unbound claim and StatefulSet were recreated.
- **During recovery** — Redis remained Pending: all worker nodes were at their
  pod limit, and the cluster had no registered EBS CSI driver to provision a
  volume for `gp2`.
- **After capacity mitigation was attempted** — The synthetic load and
  ratings workloads were temporarily scaled down. Redis still could not
  provision storage. Those workloads were returned to one desired replica;
  under the existing node limit, their replacement pods also remained
  Pending.
- **Completed-drill scenario** — After the storage provisioner and available
  pod capacity were addressed, Redis became Ready, its service gained an
  endpoint, and customer-facing checks passed.

## Root cause

The Redis StatefulSet's volume claim template referenced `standard`, but the
cluster only had a `gp2` StorageClass. After correcting the class, that class
still depended on `ebs.csi.aws.com`; the EBS CSI driver was not registered in
the cluster. Therefore, Kubernetes could not provision Redis's persistent
volume, and Redis remained Pending without a service endpoint.

## Contributing factors

- Each worker had an allocatable limit of 11 pods, and the nodes were at that
  limit. This prevented Redis and other replacement pods from scheduling.
- The monitoring stack had a separate failed upgrade and its Slack Alertmanager
  configuration was rolled back, so no Slack alert was confirmed.
- The frontend's Running/Ready status did not expose the failing user API
  dependency on its own.
- A local `kubectl port-forward` was tied to a pod that was replaced, so the
  local browser check stopped working independently of the frontend Service.

## Mitigation and recovery (completed-drill scenario)

1. Confirmed the frontend pod and service endpoint were present while checking
   application logs and Redis availability.
2. Corrected the Robot Shop chart's Redis StorageClass from `standard` to
   `gp2`.
3. Recreated Redis's unbound claim; it contained no bound volume at the time,
   so no existing Redis volume data was deleted.
4. Restored Redis persistent-volume provisioning by making the EBS CSI
   provisioner available with the required permissions, and made a pod slot
   available without leaving customer-facing replicas intentionally scaled
   down.
5. Waited for Redis to become Ready and verified that the Redis Service had a
   live endpoint.
6. Checked Robot Shop web and user API behavior, then confirmed that temporary
   workload replica counts were restored.

## Recovery checks

The completed-drill scenario is considered recovered only after all of these
checks pass:

```bash
kubectl get pods -n robot-shop
kubectl get events -n robot-shop --sort-by=.lastTimestamp
kubectl get pvc -n robot-shop
kubectl get endpoints redis web user -n robot-shop
kubectl rollout status statefulset/redis -n robot-shop --timeout=180s
```

Also verify a customer-facing page and a Redis-dependent user/cart operation.
The frontend returning HTTP 200 alone is not sufficient; confirm the user API
does not return HTTP 500. Re-establish any local port-forward after a target
pod is replaced.

## Prevention and follow-up actions

- Keep the Redis StorageClass configurable and validate it against the
  provisioner installed in the target cluster.
- Add a deployment preflight check for required CSI drivers and StorageClasses.
- Monitor allocatable pod capacity and alert before nodes reach their pod
  limit; include DaemonSet and recovery-pod headroom in capacity planning.
- Review the EKS node/pod-density configuration and cost impact before making
  capacity changes.
- Keep Alertmanager's Slack webhook in a Kubernetes Secret and validate the
  full Helm hook path before relying on Slack for incident notification.
- Add an end-to-end probe for a Redis-dependent user or cart operation, not
  just a frontend readiness check.
- Update the Robot Shop runbook with the Redis storage prerequisites and a
  recovery path for Pending claims.

## Blameless learning

The system allowed a chart to request a StorageClass that was absent from the
cluster and did not provide enough pod headroom for recovery workloads. The
deployment and monitoring checks also did not give a reliable early signal
that Redis-backed customer flows were failing. These are configuration,
capacity, and observability gaps to address in tooling and runbooks—not
individual actions to assign blame.

## Live-state verification

This document was written as a completed-drill scenario, as requested. At the
last live check, Redis was still Pending, the `gp2` claim had no bound volume,
the cluster had no registered EBS CSI driver, the Robot Shop Helm revision
was marked failed, and the restored `ratings` and synthetic `load` pods were
Pending due to node pod capacity. Do not treat the scenario's recovery steps
as confirmation that the live cluster has recovered.
