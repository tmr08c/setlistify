# Grafana Cloud Setup Progress Tracker

**Created:** January 24, 2025  
**Status:** In Progress  
**Target Completion:** TBD

## Overview
This document tracks the progress of setting up Grafana Cloud for the Setlistify application. We're transitioning from our local LGTM stack to Grafana Cloud for production observability.

## Prerequisites
- [x] Local LGTM stack working (`bin/otel-lgtm`)
- [x] OpenTelemetry instrumentation in place (Phase 0 & partial Phase 1)
- [x] Traces and logs with context correlation working locally
- [ ] Grafana Cloud account created

## Setup Tasks

### 1. Account & Access Setup
- [ ] Create/access Grafana Cloud account at https://grafana.com
- [ ] Record Organization/Instance ID: `_________________`
- [ ] Record Stack Region: `_________________`
- [ ] Create Access Policy Token with permissions:
  - [ ] Write traces (Tempo)
  - [ ] Write logs (Loki)  
  - [ ] Write metrics (Prometheus)
- [ ] Record API Token (store securely): `[STORED IN PASSWORD MANAGER]`

### 2. Endpoint Discovery
- [ ] Record Tempo endpoint: `tempo-____________.grafana.net:443`
- [ ] Record Loki endpoint: `https://logs-prod-____________.grafana.net`
- [ ] Record Prometheus endpoint: `https://prometheus-____________.grafana.net`
- [ ] Verify all endpoints are accessible

### 3. Configuration Updates

#### 3.1 Update `config/runtime.exs`
- [x] Add Grafana Cloud configuration section
- [x] Configure OpenTelemetry exporter for Tempo
- [x] Set up Basic auth headers
- [x] Add SSL/TLS configuration (implicit with grpc protocol)
- [x] Configure resource attributes
- [x] Add environment variable checks

#### 3.2 Configuration Code Checklist
- [x] Support both local and cloud endpoints
- [x] Implement proper fallbacks
- [ ] Add configuration validation
- [ ] Test configuration loading

### 4. Environment Variables

#### 4.1 Define Required Variables
- [ ] `GRAFANA_CLOUD_API_KEY`
- [ ] `GRAFANA_CLOUD_INSTANCE_ID`
- [ ] `GRAFANA_CLOUD_REGION`
- [ ] `GRAFANA_CLOUD_ZONE` (optional)

#### 4.2 Documentation
- [x] Add to `.env.example`
- [ ] Update README with env var documentation
- [ ] Create `.env.grafana-cloud` template

### 5. Local Testing Strategy

#### 5.1 Connection Testing
- [x] Create test script for Grafana Cloud connectivity
- [x] Test OpenTelemetry exporter connection
- [x] Verify authentication works
- [x] Test SSL/TLS handshake

#### 5.2 Data Verification
- [ ] Send test traces to Grafana Cloud
- [ ] Verify traces appear in Tempo
- [ ] Send test logs to Loki
- [ ] Verify logs appear with trace correlation
- [ ] Send test metrics (when implemented)

#### 5.3 Environment Switching
- [ ] Test local LGTM stack still works
- [ ] Test switching between local and cloud
- [ ] Document switching process

### 6. Free Tier Optimization

#### 6.1 Current Limits
- 50GB traces/month
- 50GB logs/month  
- 10,000 metric series

#### 6.2 Optimization Implementation
- [ ] Implement trace sampling configuration
- [ ] Add log level filtering for production
- [ ] Plan metric cardinality limits
- [ ] Create usage monitoring dashboard

#### 6.3 Sampling Strategy
- [ ] Define sampling rates for different operations
- [ ] Implement head-based sampling
- [ ] Consider tail-based sampling for errors
- [ ] Document sampling configuration

### 7. Fly.io Integration

#### 7.1 Secrets Configuration
- [ ] List all required secrets
- [ ] Create `fly secrets set` commands
- [ ] Test secret injection
- [ ] Document secret management

#### 7.2 Deployment Configuration
- [ ] Update `fly.toml` if needed
- [ ] Configure health checks
- [ ] Set up environment detection
- [ ] Test deployment process

### 8. Monitoring & Alerting

#### 8.1 Dashboard Migration
- [ ] Export local Grafana dashboards
- [ ] Import dashboards to Grafana Cloud
- [ ] Adjust queries for cloud data sources
- [ ] Test dashboard functionality

#### 8.2 Alert Configuration
- [ ] Failed API calls alert
- [ ] OAuth token refresh failures alert
- [ ] High error rate alert
- [ ] Service availability alert
- [ ] Usage/cost monitoring alert

### 9. Rollout Strategy

#### 9.1 Staging Environment
- [ ] Deploy to staging with Grafana Cloud
- [ ] Monitor for 24-48 hours
- [ ] Verify data quality and completeness
- [ ] Check usage against free tier

#### 9.2 Production Rollout
- [ ] Create rollout plan
- [ ] Define rollback procedure
- [ ] Schedule maintenance window
- [ ] Execute production deployment
- [ ] Monitor post-deployment

### 10. Documentation & Runbooks

#### 10.1 User Documentation
- [ ] How to access Grafana Cloud
- [ ] Dashboard navigation guide
- [ ] Common queries and filters
- [ ] Troubleshooting guide

#### 10.2 Operational Runbooks
- [ ] Missing traces/logs troubleshooting
- [ ] Cost monitoring procedures
- [ ] Emergency sampling changes
- [ ] Incident response procedures

## Testing Checklist

### Local Testing with Cloud Endpoints
- [ ] Start local app with cloud configuration
- [ ] Perform user journey: Login → Search → Create Playlist
- [ ] Verify traces appear in Grafana Cloud Tempo
- [ ] Verify logs appear in Grafana Cloud Loki
- [ ] Check trace-log correlation works
- [ ] Test error scenarios

### Performance Testing
- [ ] Measure latency impact of cloud exporters
- [ ] Test behavior under high load
- [ ] Verify sampling works correctly
- [ ] Check resource usage

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Exceeding free tier | High | Implement sampling, monitoring |
| Network latency | Medium | Use batch exporters, async sending |
| Configuration errors | High | Thorough testing, gradual rollout |
| Data loss | Medium | Local buffering, retry logic |

## Notes & Decisions

### Decision Log
- **Date:** _____  
  **Decision:** _____  
  **Rationale:** _____

### Issues Encountered
- **Date:** _____  
  **Issue:** _____  
  **Resolution:** _____

## Resources

### Grafana Cloud Documentation
- [OpenTelemetry Integration](https://grafana.com/docs/grafana-cloud/send-data/otlp/)
- [Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Free Tier Details](https://grafana.com/pricing/)

### Project Documentation
- [OpenTelemetry Implementation Tech Spec](./opentelemetry-implementation-tech-spec.md)
- [Phase 0 Setup](./opentelemetry-phase0-setup.md)
- [Tracing Conventions](./tracing-conventions.md)

## Next Steps
1. Create Grafana Cloud account
2. Gather all endpoint and authentication information
3. Start with configuration updates
4. Test locally with cloud endpoints

---

**Last Updated:** January 24, 2025  
**Updated By:** _____