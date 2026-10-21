# Service Level Objective (SLO): Web Service

1. **Service:** web (shop frontend)
2. **SLI:** Successful HTTP requests divided by total HTTP requests over a rolling 30-day window.
3. **SLO:** 99% availability over 30 days.
4. **Error Budget:** 1% allowed failure (~7.2 hours of downtime per month).
5. **Policy:**
   - > 50% budget remaining: Ship features normally.
   - < 50% budget remaining: Restrict changes to low-risk updates; review incidents.
   - 0% budget remaining: Feature freeze; engineering focuses entirely on reliability until the budget recovers.
6. **Owner:** Iyanu (DevOps Engineer)
