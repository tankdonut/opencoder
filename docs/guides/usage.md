# OpenCode Harness - Usage Guide

This guide covers how to effectively use OpenCode Harness in different environments and workflows.

## Basic Usage

### Host Environment

After running `./scripts/local-setup.sh`, OpenCode is available globally with the harness configuration installed:

```bash
# Basic OpenCode commands
opencode --version
opencode --help
opencode  # Start interactive TUI

# Start OpenCode with harness configuration
opencode
```

The harness configuration includes these OpenCode plugins:

- `@tarquinen/opencode-dcp@3.1.11`
- `cc-safety-net@0.9.0`
- `oh-my-openagent@4.0.0`

### Container Environment

The container comes with OpenCode pre-configured and ready to use:

```bash
# Check installation
podman run -it --rm opencode-harness opencode --version

# Interactive session
podman run -it --rm opencode-harness

# Run specific commands
podman run --rm opencode-harness opencode --help
```

## Development Workflows

### Project Development

Mount your project directory to work on existing codebases:

```bash
# Mount current directory as workspace
podman run -it --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  opencode-harness bash

# Direct command execution
podman run --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  opencode-harness opencode --version
```

### Multi-Agent Orchestration

The harness includes oh-my-openagent for sophisticated multi-agent workflows:

```bash
# Start orchestration session
opencode

# Available agents (examples):
# - Sisyphus: Main orchestrator
# - Hephaestus: Deep autonomous worker
# - Prometheus: Strategic planner
# - Oracle: Architecture consultant
# - Librarian: Documentation and research
```

### Skills and Commands

Access production-ready skills and commands:

```bash
# Skills are loaded automatically from plugins

# Use specific skills in your workflow
# - TDD workflows
# - Git operations
# - Browser automation (Playwright)
# - Debugging methodologies
```

## Container Usage Patterns

### Development Environment

**Interactive development:**

```bash
# Start development container
podman run -it --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  --name opencode-dev \
  opencode-harness bash

# Inside container
opencode --version
ls -la /workspace
```

**Persistent containers:**

```bash
# Create persistent container for long-running work
podman run -dit \
  -v $(pwd):/workspace \
  -w /workspace \
  --name my-opencode-env \
  opencode-harness

# Attach to existing container
podman exec -it my-opencode-env bash

# Stop when done
podman stop my-opencode-env
podman rm my-opencode-env
```

### CI/CD Integration

**GitHub Actions example:**

```yaml
name: OpenCode Check
on: [push, pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Check OpenCode version
        run: |
          podman pull ghcr.io/tankdonut/opencode-harness:latest
          podman run --rm \
            -v ${{ github.workspace }}:/workspace \
            -w /workspace \
            ghcr.io/tankdonut/opencode-harness:latest \
            opencode --version
```

**GitLab CI example:**

```yaml
check-opencode:
  stage: test
  image: ghcr.io/tankdonut/opencode-harness:latest
  script:
    - opencode --version
  only:
    - merge_requests
    - main
```

### Team Collaboration

**Consistent environments:**

```bash
# Team members use same container version
podman pull ghcr.io/tankdonut/opencode-harness:v1.0.0

# Shared configuration via mounted configs
podman run -it --rm \
  -v $(pwd):/workspace \
  -v ~/team-opencode-config:/config \
  -w /workspace \
  opencode-harness
```

**Workspace mount:**

```bash
# Mount a project workspace with the harness configuration
podman run -it --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  opencode-harness
```

## Plugin Management

### Updating Plugins

The harness uses git submodules for plugin management:

```bash
# Update all plugins to latest
git submodule update --remote --recursive

# Update specific plugin
cd build/modules/everything-claude-code
git pull origin main
cd ../../..
git add build/modules/everything-claude-code
git commit -m "update: everything-claude-code plugin"

# Container rebuild needed after plugin updates
./scripts/build.sh
```

### Plugin Configuration

**Main configuration file:** `build/.opencode/opencode.json`

```json
{
    "$schema": "https://opencode.ai/config.json",
    "plugin": [
        "@tarquinen/opencode-dcp@3.1.11",
        "cc-safety-net@0.9.0",
        "oh-my-openagent@4.0.0"
    ]
}
```

**Container-specific configuration:** `build/etc/opencode/opencode.jsonc`

- Used for container-specific optimizations
- Supports comments and trailing commas

### Adding Custom Plugins

```bash
# Add new plugin as submodule
git submodule add https://github.com/example/opencode-plugin.git build/modules/my-plugin

# Update the harness OpenCode configuration
jq '.plugin += ["my-plugin"]' build/.opencode/opencode.json > tmp.json && mv tmp.json build/.opencode/opencode.json

# Rebuild container if using container deployment
./scripts/build.sh
```

## Advanced Usage

### Custom Skills Development

Custom skills can be developed following the patterns in the plugin submodules under `build/modules/`.

### Environment Variables

Environment variables for OpenCode are configured by the tool itself. Refer to the OpenCode documentation for available options.

### Debugging and Logging

**Access container logs:**

```bash
# View container logs
podman logs my-opencode-container

# Follow logs in real-time
podman logs -f my-opencode-container
```

## Performance Optimization

### Container Performance

**Resource limits:**

```bash
# Limit container resources
podman run -it --rm \
  --memory=4g \
  --cpus=2 \
  -v $(pwd):/workspace \
  opencode-harness
```

**Volume optimization:**

```bash
# Use bind mounts for better performance
podman run -it --rm \
  --mount type=bind,source=$(pwd),target=/workspace \
  -w /workspace \
  opencode-harness
```

### Caching Strategies

**Container layer caching:**

```bash
# Build with tag
./scripts/build.sh --tag opencode-harness
```

**Plugin caching:**

```bash
# Cache plugin installations
# Plugins are cached as git submodules
# No additional caching needed for most use cases
```

## Best Practices

### Security

1. **Container security:**
   - Containers run as non-root user (UID 1000)
   - No secrets baked into images
   - Minimal attack surface

2. **Host security:**
   - Keep OpenCode and plugins updated
   - Review plugin permissions
   - Use project-specific configurations

### Maintenance

1. **Regular updates:**

   ```bash
   # Update harness
   git pull origin main
   git submodule update --remote --recursive

    # Rebuild container
    ./scripts/build.sh
   ```

2. **Cleanup:**

   ```bash
   # Clean up old containers
   podman system prune -a

   # Clean up unused images
   podman image prune -a
   ```

### Troubleshooting

**Common issues and solutions:**

1. **Plugin loading failures:**

   ```bash
   # Verify submodules are initialized
   git submodule status

   # Reinitialize if needed
   git submodule update --init --recursive
   ```

2. **Container permission issues:**

   ```bash
   # Fix workspace permissions
   chown -R 1000:1000 /path/to/workspace
   ```

3. **Memory/resource issues:**

   ```bash
   # Monitor container resource usage
   podman stats my-container

   # Increase limits if needed
   podman run --memory=8g --cpus=4 ...
   ```

## Getting Help

- **Documentation**: Check [DEVELOPMENT.md](../../DEVELOPMENT.md) for development-specific usage
- **Issues**: Report problems on [GitHub Issues](https://github.com/tankdonut/opencode-harness/issues)
- **Community**: Join discussions for user support and tips
