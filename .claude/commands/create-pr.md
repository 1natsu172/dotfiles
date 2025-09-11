---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(gh)
argument-hint: [language]
description: Create a GitHub pull request with language support (en/ja)
# model: claude-3-5-haiku-20241022
---

# How to Create a Pull Request Using GitHub CLI

Language support: Use `/create-pr [language]` where language can be `en` (default) or `ja`.

Based on the provided argument ($ARGUMENTS), generate PR content in the specified language:
- No argument or `en`: Generate English PR title and description
- `ja`: Generate Japanese PR title and description

This guide explains how to create pull requests using GitHub CLI in our project.

**Language Instructions**: When generating PR content, use the language specified by the first argument. If argument is `ja`, write PR titles and descriptions in Japanese. Otherwise, use English (default).

## Prerequisites

1. Install GitHub CLI if you haven't already:

   ```bash
   # macOS
   brew install gh

   # Windows
   winget install --id GitHub.cli

   # Linux
   # Follow instructions at https://github.com/cli/cli/blob/trunk/docs/install_linux.md
   ```

2. Authenticate with GitHub:
   ```bash
   gh auth login
   ```

## Creating a New Pull Request

1. First, prepare your PR description following the template in @.github/pull_request_template.md

2. Use the `gh pr create --draft` command to create a new pull request:

   ```bash
   # Basic command structure
   gh pr create --draft --title "feat(scope): Your descriptive title" --body "Your PR description" --base main 
   ```

   For more complex PR descriptions with proper formatting, use the `--body-file` option with the exact PR template structure:

   ```bash
   # Create PR with proper template structure
   gh pr create --draft --title "feat(scope): Your descriptive title" --body-file .github/pull_request_template.md --base main
   ```

## Best Practices

1. **Language**: Use the language specified by the command argument (`$ARGUMENTS`). Default to English if no language specified.

2. **PR Title Format**: Use conventional commit format without emojis

   - Use standard conventional commit prefixes (feat, fix, docs, style, refactor, test, chore)
   - Do not include emojis in the title
   - Examples:
     - `feat(supabase): Add staging remote configuration`
     - `fix(auth): Fix login redirect issue`
     - `docs(readme): Update installation instructions`

3. **Description Template**: Always use our PR template structure from @.github/pull_request_template.md:

4. **Template Accuracy**: Ensure your PR description precisely follows the template structure:

   - Don't modify or rename the PR-Agent sections (`pr_agent:summary` and `pr_agent:walkthrough`)
   - Keep all section headers exactly as they appear in the template
   - Don't add custom sections that aren't in the template

5. **Draft PRs**: Start as draft when the work is in progress
   - Use `--draft` flag in the command
   - Convert to ready for review when complete using `gh pr ready`

### Common Mistakes to Avoid

1. **Ignoring Language Argument**: Use the language specified in the command argument ($ARGUMENTS)
2. **Including Emojis**: Do not include emojis in PR titles or descriptions
3. **Incorrect Section Headers**: Always use the exact section headers from the template
4. **Adding Custom Sections**: Stick to the sections defined in the template
5. **Using Outdated Templates**: Always refer to the current @.github/pull_request_template.md file

### Missing Sections

Always include all template sections, even if some are marked as "N/A" or "None"

## Additional GitHub CLI PR Commands

Here are some additional useful GitHub CLI commands for managing PRs:

```bash
# List your open pull requests
gh pr list --author "@me"

# Check PR status
gh pr status

# View a specific PR
gh pr view <PR-NUMBER>

# Check out a PR branch locally
gh pr checkout <PR-NUMBER>

# Convert a draft PR to ready for review
gh pr ready <PR-NUMBER>

# Add reviewers to a PR
gh pr edit <PR-NUMBER> --add-reviewer username1,username2

# Merge a PR
gh pr merge <PR-NUMBER> --squash
```

## Using Templates for PR Creation

To simplify PR creation with consistent descriptions, you can create a template file:

1. Create a file named `pr-template.md` with your PR template
2. Use it when creating PRs:

```bash
gh pr create --draft --title "feat(scope): Your title" --body-file pr-template.md --base main
```

## Related Documentation

- [PR Template](.github/pull_request_template.md)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [GitHub CLI documentation](https://cli.github.com/manual/)
