# Setlistify Scripts

This directory contains helpful scripts for development and operations.

## Scripts

### `bin/server`
Starts the Phoenix server with automatic port assignment for both Phoenix and PromEx.

**Features:**
- Automatically finds available ports:
  - Phoenix web server (starting from 4000)
  - PromEx metrics server (starting from 9568)
- Updates Prometheus targets if Docker stack is running
- Names instances based on git worktree names
- Exports `PORT` and `PROM_EX_PORT` environment variables

**Usage:**
```bash
# Start with automatic port assignment
bin/server

# Start with specific Phoenix port
PORT=4001 bin/server

# Start with specific PromEx port
PROM_EX_PORT=9570 bin/server

# Start with both ports specified
PORT=4002 PROM_EX_PORT=9571 bin/server
```

### `bin/list-instances`
Shows all running Setlistify instances with their Phoenix and PromEx ports.

**Usage:**
```bash
bin/list-instances
```

**Output example:**
```
==> Running Setlistify instances:

Phoenix Web Servers:
  Phoenix port 4000: PID 12345
    Working directory: /Users/you/setlistify
  Phoenix port 4001: PID 12346
    Working directory: /Users/you/setlistify-feature-branch

PromEx Metrics Servers:
  PromEx port 9568: PID 12345
    Working directory: /Users/you/setlistify
    Phoenix port: 4000
  PromEx port 9569: PID 12346
    Working directory: /Users/you/setlistify-feature-branch
    Phoenix port: 4001

==> Prometheus targets:
  - Instance: default -> host.docker.internal:9568
  - Instance: feature-branch -> host.docker.internal:9569
```

### `bin/setup`
Prepares the development environment (called automatically by `bin/server`).

### `bin/init`
Initial project setup for first-time contributors.

## Multiple Instance Support

When running multiple instances (e.g., in different git worktrees):

1. Each instance automatically gets a unique PromEx port
2. Prometheus is automatically updated to scrape all instances
3. Instances are named after their worktree for easy identification

This allows you to:
- Run production and development instances side-by-side
- Test features in isolation
- Compare metrics across different versions