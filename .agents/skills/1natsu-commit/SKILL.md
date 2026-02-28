---
name: 1natsu-commit
description: Use when creating git commits, writing commit messages, or staging changes. Provides best practices for conventional commits, atomic commits, and clear commit messages that work across any coding agent.
---

# Git Commit Best Practices

Guidelines for creating clean, meaningful git commits.

## When to Use

- Creating a git commit
- Writing or reviewing commit messages
- Deciding how to stage and group changes

## Commit Message Format

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Purpose |
|------|---------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no logic change |
| `refactor` | Code restructuring, no behavior change |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `build` | Build system or dependencies |
| `ci` | CI/CD configuration |
| `chore` | Maintenance tasks |
| `revert` | Reverting a previous commit |

### Scope (Optional)

Indicates the affected area:

```
feat(auth): add OAuth2 login
fix(api): handle timeout on large payloads
docs(readme): update installation steps
```

### Description Rules

- Use imperative mood: "add" not "added" or "adds"
- No capitalization of first letter
- No period at the end
- Keep under 50 characters when possible

## Atomic Commits

Each commit should represent **one logical change**:

- Separate refactoring from feature work
- Separate formatting changes from logic changes
- Separate dependency updates from code changes
- Each commit should leave the codebase in a working state

### Staging Strategy

- Use `git add <specific-files>` instead of `git add .` or `git add -A`
- Review staged changes with `git diff --staged` before committing
- Avoid committing generated files, secrets, or environment files

## Commit Body

Use the body for context when the description alone is not enough:

```
fix(parser): handle nested quotes in CSV fields

The parser was splitting on all commas, including those inside
quoted strings. Added state tracking for quote depth to correctly
identify field boundaries.
```

**Body guidelines:**
- Separate from description with a blank line
- Explain **what** and **why**, not **how**
- Wrap at 72 characters per line

## Footer

Use for breaking changes and issue references:

```
feat(api): change authentication endpoint

BREAKING CHANGE: /auth/login now requires email instead of username

Refs: #123
```

## Common Mistakes to Avoid

1. **Vague messages**: "fix bug", "update code", "WIP"
2. **Too many changes**: mixing unrelated changes in one commit
3. **Committing secrets**: `.env`, API keys, credentials
4. **Giant commits**: hundreds of lines across many files
5. **Wrong tense**: "fixed" instead of "fix", "added" instead of "add"

## Examples

**Good commits:**

```
feat(auth): add two-factor authentication support
fix(cart): prevent duplicate items on rapid click
refactor(db): extract query builder into separate module
test(auth): add integration tests for password reset
docs(api): document rate limiting headers
chore(deps): update typescript to 5.4
```

**Bad commits:**

```
update stuff
fix
WIP
asdf
Merge branch 'main' into feature (unnecessary merge commits)
```
