# Grafana Cloud Trace Verification Guide

## Quick Links
- **Your Grafana Instance**: https://1267850.grafana.net
- **Tempo (Traces)**: https://1267850.grafana.net/explore?orgId=1&left=%5B%22now-1h%22,%22now%22,%22Tempo%22,%7B%7D%5D

## Steps to Verify Traces

### 1. Generate Test Traces
In your running app (http://localhost:4400):
1. **Search for an artist** (e.g., "Radiohead")
2. **Click on a setlist**
3. **Create a playlist** (if logged in with Spotify)

### 2. Check Grafana Cloud
1. Go to your Grafana instance: https://1267850.grafana.net
2. Navigate to **Explore** (compass icon in left sidebar)
3. Select **Tempo** as the data source (top dropdown)
4. In the query builder:
   - Service Name: `setlistify`
   - You can also search by trace ID from your logs

### 3. What to Look For

#### Successful Connection Indicators:
- ✅ Traces appear within 1-2 minutes
- ✅ Service name shows as "setlistify"
- ✅ Spans show your instrumented operations (e.g., `Setlistify.Spotify.API.search_for_track`)
- ✅ Resource attributes include your region (us-east-2)

#### If No Traces Appear:
1. Check server logs for any connection errors
2. Look for "OTLP exporter successfully initialized" in startup logs
3. Verify environment variables are loaded correctly
4. Check if traces are being created locally first

### 4. Useful Queries

**Find all traces from your service:**
```
{service.name="setlistify"}
```

**Find traces with errors:**
```
{service.name="setlistify" && status.code=2}
```

**Find traces for Spotify operations:**
```
{service.name="setlistify" && name=~".*[Ss]potify.*"}
```

### 5. Debugging Tips

If traces aren't appearing:
1. **Check the logs** - Look for lines with `trace_id` and `span_id`
2. **Verify local traces first** - Use the local LGTM stack to ensure traces are being generated
3. **Check authentication** - Look for any 401/403 errors in server logs
4. **Network issues** - Ensure your network allows outbound connections to *.grafana.net:443

## Next Steps

Once traces are verified:
1. Set up dashboards for trace visualization
2. Configure alerts for error traces
3. Add log correlation (Phase 2)
4. Add metrics collection (Phase 3)