#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. upstream 리모트가 없으면 추가
if ! git remote get-url upstream &>/dev/null; then
  echo "Adding upstream remote..."
  git remote add upstream https://github.com/nolabs-ai/nono-packs.git
fi

# 2. UPSTREAM_BRANCH 검증
if [[ -z "${UPSTREAM_BRANCH:-}" ]]; then
  echo "Error: UPSTREAM_BRANCH is not set" >&2
  exit 1
fi

if [[ "$UPSTREAM_BRANCH" == "master" || "$UPSTREAM_BRANCH" == "empty" ]]; then
  echo "Error: UPSTREAM_BRANCH cannot be 'master' or 'empty'" >&2
  exit 1
fi

if ! git fetch --depth 1 upstream "$UPSTREAM_BRANCH"; then
  echo "Error: Branch '$UPSTREAM_BRANCH' does not exist on upstream remote" >&2
  exit 1
fi

# 3. 로컬 브랜치 생성
if git fetch origin "$UPSTREAM_BRANCH" 2>/dev/null; then
  echo "Creating local branch '$UPSTREAM_BRANCH' from origin..."
  git branch "$UPSTREAM_BRANCH" "origin/$UPSTREAM_BRANCH"
else
  echo "Creating local branch '$UPSTREAM_BRANCH' from empty..."
  git fetch origin empty
  git branch "$UPSTREAM_BRANCH" origin/empty
fi

# 4. sanitize.sh를 임시 파일로 복사 (checkout하면 사라지므로)
SANITIZE_TMP="$(mktemp)"
cp "$SCRIPT_DIR/sanitize.sh" "$SANITIZE_TMP"
trap 'rm -f "$SANITIZE_TMP"' EXIT

# 5. upstream tree 스냅샷으로 교체 (merge commit 없이)
echo "Syncing $UPSTREAM_BRANCH to upstream/$UPSTREAM_BRANCH via read-tree..."
git checkout "$UPSTREAM_BRANCH"
git restore --source="upstream/$UPSTREAM_BRANCH" --worktree :/

# 6. sanitize.sh 실행
echo "Running sanitize.sh..."
bash "$SANITIZE_TMP"

# 7. 변경사항이 있으면 새 커밋 생성
git add -A
if ! git diff --cached --quiet; then
  UPSTREAM_SHA=$(git rev-parse "upstream/$UPSTREAM_BRANCH")
  git commit -m "sync $UPSTREAM_BRANCH $UPSTREAM_SHA"
else
  echo "Already up to date"
fi
