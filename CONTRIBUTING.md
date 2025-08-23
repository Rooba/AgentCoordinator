# Contributing to AgentCoordinator

Thank you for your interest in contributing to AgentCoordinator! This document provides guidelines for contributing to the project.

## 🤝 Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct. Please report unacceptable behavior to the project maintainers.

## 🚀 How to Contribute

### Reporting Bugs

1. **Check existing issues** first to see if the bug has already been reported
2. **Create a new issue** with a clear title and description
3. **Include reproduction steps** with specific details
4. **Provide system information** (Elixir version, OS, etc.)
5. **Add relevant logs** or error messages

### Suggesting Features

1. **Check existing feature requests** to avoid duplicates
2. **Create a new issue** with the `enhancement` label
3. **Describe the feature** and its use case clearly
4. **Explain why** this feature would be beneficial
5. **Provide examples** of how it would be used

### Development Setup

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/your-username/agent_coordinator.git
   cd agent_coordinator
   ```
3. **Install dependencies**:
   ```bash
   mix deps.get
   ```
4. **Start NATS server**:
   ```bash
   nats-server -js -p 4222 -m 8222
   ```
5. **Run tests** to ensure everything works:
   ```bash
   mix test
   ```

### Making Changes

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. **Make your changes** following our coding standards
3. **Add tests** for new functionality
4. **Run the test suite**:
   ```bash
   mix test
   ```
5. **Run code quality checks**:
   ```bash
   mix format
   mix credo
   mix dialyzer
   ```
6. **Commit your changes** with a descriptive message:
   ```bash
   git commit -m "Add feature: your feature description"
   ```
7. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```
8. **Create a Pull Request** on GitHub

## 📝 Coding Standards

### Elixir Style Guide

- Follow the [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)
- Use `mix format` to format your code
- Write clear, descriptive function and variable names
- Add `@doc` and `@spec` for public functions
- Follow the existing code patterns in the project

### Code Organization

- Keep modules focused and cohesive
- Use appropriate GenServer patterns for stateful processes
- Follow OTP principles and supervision tree design
- Organize code into logical namespaces

### Testing

- Write comprehensive tests for all new functionality
- Use descriptive test names that explain what is being tested
- Follow the existing test patterns and structure
- Ensure tests are fast and reliable
- Aim for good test coverage (check with `mix test --cover`)

### Documentation

- Update documentation for any API changes
- Add examples for new features
- Keep the README.md up to date
- Use clear, concise language
- Include code examples where helpful

## 🔧 Pull Request Guidelines

### Before Submitting

- [ ] Tests pass locally (`mix test`)
- [ ] Code is properly formatted (`mix format`)
- [ ] No linting errors (`mix credo`)
- [ ] Type checks pass (`mix dialyzer`)
- [ ] Documentation is updated
- [ ] CHANGELOG.md is updated (if applicable)

### Pull Request Description

Please include:

1. **Clear title** describing the change
2. **Description** of what the PR does
3. **Issue reference** if applicable (fixes #123)
4. **Testing instructions** for reviewers
5. **Breaking changes** if any
6. **Screenshots** if UI changes are involved

### Review Process

1. At least one maintainer will review your PR
2. Address any feedback or requested changes
3. Once approved, a maintainer will merge your PR
4. Your contribution will be credited in the release notes

## 🧪 Testing

### Running Tests

```bash
# Run all tests
mix test

# Run tests with coverage
mix test --cover

# Run specific test file
mix test test/agent_coordinator/mcp_server_test.exs

# Run tests in watch mode
mix test.watch
```

### Writing Tests

- Place test files in the `test/` directory
- Mirror the structure of the `lib/` directory
- Use descriptive `describe` blocks to group related tests
- Use `setup` blocks for common test setup
- Mock external dependencies appropriately

## 🚀 Release Process

1. Update version in `mix.exs`
2. Update `CHANGELOG.md` with new version details
3. Create and push a version tag
4. Create a GitHub release
5. Publish to Hex (maintainers only)

## 📞 Getting Help

- **GitHub Issues**: For bugs and feature requests
- **GitHub Discussions**: For questions and general discussion
- **Documentation**: Check the [online docs](https://hexdocs.pm/agent_coordinator)

## 🏷️ Issue Labels

- `bug`: Something isn't working
- `enhancement`: New feature or request
- `documentation`: Improvements or additions to documentation
- `good first issue`: Good for newcomers
- `help wanted`: Extra attention is needed
- `question`: Further information is requested

## 🎉 Recognition

Contributors will be:

- Listed in the project's contributors section
- Mentioned in release notes for significant contributions
- Given credit in any related blog posts or presentations

Thank you for contributing to AgentCoordinator! 🚀
