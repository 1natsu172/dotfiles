---
allowed-tools: Bash(git), Bash(gh)
argument-hint: [language]
description: Create a GitHub pull request with language support (en/ja)
---

# Create Pull Request

This command creates a GitHub pull request using git analysis and PR best practices.

## Skills Used

This command leverages two Skills for optimal efficiency:
- **git-analysis**: Analyzes branch changes, commits, and merge base
- **github-pr-best-practices**: Applies conventional commits and PR formatting standards

## Instructions

### Step 1: Analyze Branch Changes

Use the `git-analysis` Skill to gather branch information:

1. Run git analysis commands in parallel:
   - Check current status: `git status`
   - Check staged changes: `git diff --cached`
   - Check unstaged changes: `git diff`

2. Get branch divergence information:
   - Determine default branch
   - Find merge base
   - List all commits from merge base to HEAD
   - Get file change statistics

**Important**: Analyze ALL commits from the merge base, not just the latest commit.

You can use the helper scripts:
```bash
bash @~/.claude/skills/git-analysis/scripts/get_branch_diff.sh
bash @~/.claude/skills/git-analysis/scripts/get_commit_history.sh
```

### Step 2: Draft PR Content

Use the `github-pr-best-practices` Skill to format PR content:

1. **Language Selection**:
   - Use `$ARGUMENTS` to determine language
   - Default: English (`en`)
   - Supported: `en`, `ja`

2. **PR Title**:
   - Follow conventional commit format
   - No emojis
   - Format: `<type>(<scope>): <description>`
   - Examples: `feat(auth): add OAuth2 support`, `fix(api): resolve timeout issue`

3. **PR Description Structure**:
   ```markdown
   ## Summary
   - Brief description (1-3 bullet points)
   - Focus on what and why

   ## Test plan
   - [ ] Test case 1
   - [ ] Test case 2
   - [ ] Verify no regressions

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   ```

4. **Template Integration**:
   - Check if `.github/pull_request_template.md` exists
   - If exists, follow its structure exactly
   - Don't modify section headers or add custom sections

### Step 3: Create Pull Request

Execute the PR creation:

```bash
gh pr create --draft --title "the pr title" --body "$(cat <<'EOF'
## Summary
<1-3 bullet points in selected language>

## Test plan
<checklist in selected language>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Important Notes**:
- Use HEREDOC format (`cat <<'EOF'`) for multi-line body
- Always use `--draft` flag
- Do NOT manually push - `gh pr create` handles it automatically
- Return the PR URL to the user

### Step 4: Return PR URL

Display the PR URL to the user for easy access.

## Language Examples

### English (en)
```markdown
## Summary
- Add user authentication with OAuth2
- Implement token refresh mechanism

## Test plan
- [ ] Test OAuth2 login flow
- [ ] Test token refresh
```

### Japanese (ja)
```markdown
## 概要
- OAuth2によるユーザー認証を追加
- トークンリフレッシュ機能を実装

## テスト計画
- [ ] OAuth2ログインフローのテスト
- [ ] トークンリフレッシュのテスト
```

## Common Mistakes to Avoid

Refer to the `github-pr-best-practices` Skill for:
- Conventional commit format errors
- Emoji usage (not allowed)
- Vague descriptions
- Language mixing
- Manual push before gh pr create
- Ignoring ALL commits (must analyze from merge base)

## Quick Reference

```bash
# This command handles the entire flow:
# 1. Analyzes git branch state
# 2. Formats PR following best practices
# 3. Creates draft PR with proper structure
# 4. Returns PR URL

# Usage:
/create-pr          # English PR
/create-pr en       # English PR (explicit)
/create-pr ja       # Japanese PR
```
