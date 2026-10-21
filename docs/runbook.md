# Runbook: RobotShopWebDown

## Meaning
The `web` frontend service has zero available replicas running. Customers cannot access the shop.

## Quick Checks
- Run `kubectl get pods -n robot-shop`
- Check recent logs in Loki via Grafana.

## Mitigation
- Restart deployment: `kubectl rollout restart deployment/web -n robot-shop`
- Scale replicas up: `kubectl scale deployment web -n robot-shop --replicas=2`
- Rollback bad release if needed.
