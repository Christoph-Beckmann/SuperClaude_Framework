#!/bin/bash

# ----------------------------------------
# sync_upstream.sh
# Keeps your manual fork in sync with upstream/main
# ----------------------------------------

# === CONFIGURATION ===
BRANCH="main"  # Your local branch
UPSTREAM_BRANCH="master"  # Upstream default branch

# === Step 1: Fetch upstream changes ===
echo "📥 Fetching latest changes from upstream..."
git fetch upstream

# === Step 2: Checkout your local main branch ===
echo "🔄 Checking out your local $BRANCH branch..."
git checkout "$BRANCH"

# === Step 3: Rebase (or merge) on top of upstream ===
echo "🔁 Rebasing $BRANCH on upstream/$UPSTREAM_BRANCH..."
git rebase upstream/"$UPSTREAM_BRANCH"

# === Optional: Use merge instead (safer for shared forks) ===
# echo "🔀 Merging upstream/$UPSTREAM_BRANCH into $BRANCH..."
# git merge upstream/"$UPSTREAM_BRANCH"

# === Step 4: Push changes back to your GitHub fork ===
echo "📤 Pushing changes to origin/$BRANCH..."
git push origin "$BRANCH" --force   # ⚠️ Force needed after rebase

# === Done ===
echo "✅ Fork is now synced with upstream/$UPSTREAM_BRANCH."

