# Push Shared Documentation Updates

**Purpose:** Guide for agents to push local changes in `shared-docs/` back to the central repository.

---

## Prerequisites

Before using this prompt, ensure:

1. You have made changes to files in the `./shared-docs/` directory
2. Changes have been committed to the local repository
3. The `shared-docs` remote is configured (should already exist if setup script was used)

---

## Steps to Push Updates

### 1. Verify Remote Configuration

```bash
git remote -v | grep shared-docs
```

Expected output:
```
shared-docs    https://github.com/Saturday-Vinyl/saturday-vinyl-shared-docs.git (fetch)
shared-docs    https://github.com/Saturday-Vinyl/saturday-vinyl-shared-docs.git (push)
```

If the remote is missing, add it:
```bash
git remote add shared-docs https://github.com/Saturday-Vinyl/saturday-vinyl-shared-docs.git
```

### 2. Verify Your Changes

List modified files in shared-docs:
```bash
git diff --name-only HEAD~1 -- shared-docs/
```

Review what will be pushed:
```bash
git log --oneline -5 -- shared-docs/
```

### 3. Push to Central Repository

```bash
git subtree push --prefix=shared-docs shared-docs main
```

This extracts commits affecting `shared-docs/` and pushes them to the central repo's `main` branch.

---

## Common Issues

### "Updates were rejected because the remote contains work..."

The central repo has changes you don't have. Pull first:

```bash
git subtree pull --prefix=shared-docs shared-docs main --squash -m "Merge shared-docs updates"
```

Then retry the push.

### "fatal: bad revision 'shared-docs/main'"

The remote branch reference is missing. Fetch first:

```bash
git fetch shared-docs main
git subtree push --prefix=shared-docs shared-docs main
```

### Push is slow or times out

Subtree push can be slow on large repos. This is normal for first push. Subsequent pushes are faster.

---

## Best Practices

1. **Commit shared-docs changes separately** - Keep shared-docs commits atomic and well-described
2. **Pull before push** - Always pull latest changes before pushing to avoid conflicts
3. **Test locally first** - Ensure documentation renders correctly before pushing
4. **Use descriptive commit messages** - Other teams consume these docs; make changes clear

---

## Example Workflow

```bash
# 1. Edit the documentation
vim ./shared-docs/protocols/ble_provisioning_protocol.md

# 2. Stage and commit locally
git add ./shared-docs/
git commit -m "Update BLE protocol: add error codes for WiFi provisioning failures"

# 3. Pull latest from central repo (optional but recommended)
git subtree pull --prefix=shared-docs shared-docs main --squash -m "Merge shared-docs updates"

# 4. Push to central repo
git subtree push --prefix=shared-docs shared-docs main
```

---

## Verification

After pushing, verify the changes appear in the central repo:

```bash
# View recent commits in central repo
git ls-remote --refs shared-docs | head -5
```

Or check GitHub directly: https://github.com/Saturday-Vinyl/saturday-vinyl-shared-docs

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
