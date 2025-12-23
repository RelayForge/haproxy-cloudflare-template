# Contributing to HAProxy CloudFlare Template

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test your changes
6. Commit with a descriptive message
7. Push to your fork
8. Open a Pull Request

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR-USERNAME/haproxy-cloudflare-template.git
cd haproxy-cloudflare-template

# Create example config files for testing
cp cloudflare/active-node.example.yml cloudflare/active-node.yml
cp cloudflare/dns-records.example.yml cloudflare/dns-records.yml
cp haproxy/haproxy.cfg.example haproxy/haproxy.cfg
```

## Code Style

### Shell Scripts

- Use `set -euo pipefail` at the start of all bash scripts
- Use `shellcheck` to validate scripts
- Include helpful comments for complex logic
- Use meaningful variable names

### YAML Files

- Use 2-space indentation
- Include comments explaining configuration options
- Use lowercase for keys

### GitHub Actions

- Use composite actions for reusable logic
- Pin action versions to specific tags
- Include descriptive `name` fields

## Testing

### HAProxy Configuration

```bash
# Validate syntax
haproxy -c -f haproxy/haproxy.cfg.example
```

### Shell Scripts

```bash
# Check syntax
bash -n scripts/*.sh

# Run shellcheck
shellcheck scripts/*.sh
```

### Workflows

Test workflow changes by:
1. Creating a branch
2. Modifying the workflow trigger to include your branch
3. Pushing changes
4. Verifying the workflow runs successfully

## Pull Request Guidelines

### Before Submitting

- [ ] Test your changes locally
- [ ] Update documentation if needed
- [ ] Update example files if adding new configuration options
- [ ] Run linters (shellcheck, yamllint)

### PR Title Format

Use conventional commit style:
- `feat: Add new feature`
- `fix: Fix bug in script`
- `docs: Update documentation`
- `chore: Update dependencies`

### PR Description

Include:
- What the PR does
- Why it's needed
- How to test it
- Any breaking changes

## Reporting Issues

When reporting issues, please include:
- Description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, HAProxy version, etc.)
- Relevant log output

## Feature Requests

Feature requests are welcome! Please:
- Check if the feature already exists
- Describe the use case
- Explain why it would be useful to others

## Questions

For questions:
- Check existing documentation
- Search closed issues
- Open a new issue with the "question" label

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
