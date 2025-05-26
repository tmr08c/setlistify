# Setlistify Scripts

This directory contains helpful scripts for development and operations.

## Scripts

### `bin/server`
Starts the Phoenix server with automatic PromEx port assignment.

**Features:**
- Automatically finds an available port for PromEx metrics (starting from 9568)
- Updates Prometheus targets if Docker stack is running
- Names instances based on git worktree names
- Exports `PROM_EX_PORT` environment variable

**Usage:**
```bash
# Start with automatic port assignment
bin/server

# Start with specific port
PROM_EX_PORT=9570 bin/server
```

### `bin/list-instances`
Shows all running Setlistify instances and their PromEx ports.

**Usage:**
```bash
bin/list-instances
```

**Output example:**
```
==> Running Setlistify instances:

  Port 9568: Elixir/Phoenix instance (PID: 12345)
    Working directory: /Users/you/setlistify
  Port 9569: Elixir/Phoenix instance (PID: 12346)
    Working directory: /Users/you/setlistify-feature-branch

==> Prometheus targets:
  - Instance: default -> host.docker.internal:9568
  - Instance: feature-branch -> host.docker.internal:9569

==> Phoenix main port status:
  Port 4000: In use
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