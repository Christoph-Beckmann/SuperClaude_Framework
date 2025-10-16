#!/bin/bash

# ========================================
# sync_upstream.sh - Reliable Fork Sync Script
# ========================================
# Keeps your fork in sync with upstream/master
# with enhanced error handling and safety features
# ========================================

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# === CONFIGURATION ===
BRANCH="main"                # Your local branch
UPSTREAM_BRANCH="master"      # Upstream default branch
UPSTREAM_REPO="https://github.com/SuperClaude-Org/SuperClaude_Framework.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === Helper Functions ===
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository!"
        exit 1
    fi
}

check_clean_working_directory() {
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        log_warning "Working directory has uncommitted changes"
        read -p "Do you want to stash them? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Stashing local changes..."
            git stash push -m "sync_upstream: Auto-stash at $(date)"
            echo "STASHED=1" > /tmp/sync_upstream_state
        else
            log_error "Please commit or stash your changes first"
            exit 1
        fi
    else
        echo "STASHED=0" > /tmp/sync_upstream_state
    fi
}

setup_upstream() {
    # Check if upstream exists
    if ! git remote | grep -q "^upstream$"; then
        log_info "Adding upstream remote..."
        git remote add upstream "$UPSTREAM_REPO"
    fi

    # Verify upstream URL
    CURRENT_UPSTREAM=$(git remote get-url upstream 2>/dev/null || echo "")
    if [ "$CURRENT_UPSTREAM" != "$UPSTREAM_REPO" ]; then
        log_warning "Updating upstream URL from $CURRENT_UPSTREAM to $UPSTREAM_REPO"
        git remote set-url upstream "$UPSTREAM_REPO"
    fi

    log_info "Remote repositories:"
    git remote -v
}

create_backup() {
    BACKUP_BRANCH="backup-$(date +%Y%m%d-%H%M%S)"
    log_info "Creating backup branch: $BACKUP_BRANCH"
    git branch "$BACKUP_BRANCH" "$BRANCH" 2>/dev/null || {
        log_warning "Backup branch creation failed, but continuing..."
    }
    echo "$BACKUP_BRANCH" > /tmp/sync_upstream_backup
}

sync_with_upstream() {
    local sync_method="${1:-smart}"

    log_info "Fetching latest changes from all remotes..."
    git fetch --all --prune || {
        log_error "Failed to fetch from remotes"
        exit 1
    }

    # Check if we're behind upstream
    LOCAL_COMMIT=$(git rev-parse "$BRANCH")
    UPSTREAM_COMMIT=$(git rev-parse "upstream/$UPSTREAM_BRANCH")

    if [ "$LOCAL_COMMIT" = "$UPSTREAM_COMMIT" ]; then
        log_success "Already up-to-date with upstream/$UPSTREAM_BRANCH"
        return 0
    fi

    # Show what will be synced
    log_info "Commits to be synced:"
    git log --oneline "$BRANCH..upstream/$UPSTREAM_BRANCH" | head -10

    COMMIT_COUNT=$(git rev-list --count "$BRANCH..upstream/$UPSTREAM_BRANCH")
    log_info "Total commits to sync: $COMMIT_COUNT"

    # Ensure we're on the right branch
    log_info "Checking out $BRANCH..."
    git checkout "$BRANCH"

    case "$sync_method" in
        "smart")
            log_info "Using smart sync (rebase with merge fallback)..."
            if git rebase "upstream/$UPSTREAM_BRANCH"; then
                log_success "Rebase successful!"
                return 0
            else
                log_warning "Rebase failed, attempting merge..."
                git rebase --abort 2>/dev/null || true

                if git merge "upstream/$UPSTREAM_BRANCH" --no-edit; then
                    log_success "Merge successful!"
                    return 0
                else
                    log_error "Both rebase and merge failed!"
                    return 1
                fi
            fi
            ;;

        "rebase")
            log_info "Rebasing $BRANCH on upstream/$UPSTREAM_BRANCH..."
            if git rebase "upstream/$UPSTREAM_BRANCH"; then
                log_success "Rebase successful!"
                return 0
            else
                log_error "Rebase failed! Run 'git rebase --abort' to cancel"
                return 1
            fi
            ;;

        "merge")
            log_info "Merging upstream/$UPSTREAM_BRANCH into $BRANCH..."
            if git merge "upstream/$UPSTREAM_BRANCH" --no-edit; then
                log_success "Merge successful!"
                return 0
            else
                log_error "Merge failed!"
                return 1
            fi
            ;;

        *)
            log_error "Unknown sync method: $sync_method"
            return 1
            ;;
    esac
}

push_to_origin() {
    log_info "Pushing changes to origin/$BRANCH..."

    # Check for unpushed commits first
    UNPUSHED=$(git rev-list HEAD --not --remotes=origin | wc -l)
    if [ "$UNPUSHED" -gt 0 ]; then
        log_warning "$UNPUSHED unpushed commits detected"
    fi

    # Try push with lease first (safer)
    if git push origin "$BRANCH" --force-with-lease; then
        log_success "Successfully pushed to origin/$BRANCH"
        return 0
    else
        log_warning "Force-with-lease failed, trying regular push..."
        if git push origin "$BRANCH"; then
            log_success "Successfully pushed to origin/$BRANCH"
            return 0
        else
            log_warning "Regular push failed, may need force push"
            read -p "Force push to origin? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if git push origin "$BRANCH" --force; then
                    log_success "Force pushed to origin/$BRANCH"
                    return 0
                fi
            fi
            log_error "Failed to push changes"
            return 1
        fi
    fi
}

restore_stash() {
    if [ -f /tmp/sync_upstream_state ]; then
        source /tmp/sync_upstream_state
        if [ "$STASHED" = "1" ]; then
            log_info "Restoring stashed changes..."
            git stash pop || log_warning "Failed to restore stash - check 'git stash list'"
        fi
        rm -f /tmp/sync_upstream_state
    fi
}

show_recovery_instructions() {
    if [ -f /tmp/sync_upstream_backup ]; then
        BACKUP_BRANCH=$(cat /tmp/sync_upstream_backup)
        echo
        log_warning "If you need to recover, use these commands:"
        echo "  git checkout $BACKUP_BRANCH"
        echo "  git branch -D $BRANCH"
        echo "  git branch -m $BRANCH"
        echo "  git push origin $BRANCH --force"
        rm -f /tmp/sync_upstream_backup
    fi
}

cleanup() {
    restore_stash
    show_recovery_instructions
}

# === Main Script ===
main() {
    trap cleanup EXIT

    echo "========================================="
    echo "   Fork Sync Script - Enhanced Version"
    echo "========================================="

    # Parse arguments
    SYNC_METHOD="${1:-smart}"

    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "Usage: $0 [sync-method]"
        echo ""
        echo "Sync methods:"
        echo "  smart   - Try rebase, fall back to merge if conflicts (default)"
        echo "  rebase  - Use rebase only"
        echo "  merge   - Use merge only"
        echo ""
        echo "Example: $0 smart"
        exit 0
    fi

    # Pre-flight checks
    check_git_repo
    check_clean_working_directory
    setup_upstream

    # Create backup before making changes
    create_backup

    # Perform sync
    if sync_with_upstream "$SYNC_METHOD"; then
        # Push changes if sync was successful
        if push_to_origin; then
            log_success "Fork is now synced with upstream/$UPSTREAM_BRANCH!"
        else
            log_warning "Sync completed locally but push failed"
            log_info "Your local branch is synced. Try pushing manually later."
        fi
    else
        log_error "Sync failed! Your backup branch is: $(cat /tmp/sync_upstream_backup 2>/dev/null || echo 'unknown')"
        exit 1
    fi
}

# Run main function
main "$@"