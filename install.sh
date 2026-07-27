#!/bin/bash
# cj-harness 설치 스크립트
#
# 사용법:
#   ~/cj-harness/install.sh                  # 현재 디렉토리에 설치 (복사, 인터랙티브)
#   ~/cj-harness/install.sh <target-dir>     # 대상 디렉토리에 설치
#   ~/cj-harness/install.sh --symlink        # 심링크로 설치 (하네스 업데이트 자동 반영)
#   ~/cj-harness/install.sh --update         # agents/skills/hooks 만 갱신 (settings·project.json 보존)
#   ~/cj-harness/install.sh -y               # 비대화형, ENV 또는 기본값 적용
#   ~/cj-harness/install.sh --help
#
# 비대화형 모드 (-y / --non-interactive) ENV 변수:
#   HARNESS_NAME           프로젝트 이름 (기본: 디렉토리명)
#   HARNESS_LANG           ko / en (기본: ko)
#   HARNESS_BASE_BRANCH    base 브랜치 (기본: origin/HEAD 추정 → main)
#   HARNESS_STAGING_BRANCH staging 브랜치 (빈 문자열 또는 미설정 → null)
#   HARNESS_TEST_CMD       commands.test (기본: "npm test", "none" 입력 시 null)
#   HARNESS_LINT_CMD       commands.lint (기본: "npm run lint", "none" 시 null)
#   HARNESS_BUILD_CMD      commands.build (기본: "npm run build", "none" 시 null)
#   HARNESS_E2E_CMD        commands.testE2e (기본: 비어있음 → null)
#   HARNESS_GATES_DESIGNER true / false (기본: true)
#   HARNESS_GATES_TDD      true / false (기본: true)
#   HARNESS_GATES_PEER     true / false (기본: true)
#
# 소스 → 타겟 매핑 (전부 payload/ 에서 읽어 대상의 .claude/ 또는 루트로 복사):
#   payload/agents/*.md         → <target>/.claude/agents/*.md
#   payload/skills/*/           → <target>/.claude/skills/*/
#   payload/hooks/*.sh          → <target>/.claude/hooks/*.sh
#   payload/settings.json       → <target>/.claude/settings.json   (없을 때만)
#   payload/project.example.json → <target>/.claude/project.json   (없을 때만 — 인터랙티브 또는 -y 자동)
#   payload/AGENTS.md           → <target>/AGENTS.md               (없을 때만)
#   payload/CLAUDE.md           → <target>/CLAUDE.md               (없을 때만)

set -e

HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$(pwd)"
MODE="copy"
UPDATE_ONLY=false
INTERACTIVE=true

while [ $# -gt 0 ]; do
  case "$1" in
    --symlink) MODE="symlink"; shift ;;
    --copy) MODE="copy"; shift ;;
    --update) UPDATE_ONLY=true; shift ;;
    -y|--non-interactive|--yes) INTERACTIVE=false; shift ;;
    --help|-h)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    -*)
      echo "❌ 알 수 없는 옵션: $1" >&2
      exit 1
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

if [ ! -d "$TARGET" ]; then
  echo "❌ 대상 디렉토리 없음: $TARGET" >&2
  exit 1
fi

cd "$TARGET"

# 안전 체크: git 저장소인가?
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ "$INTERACTIVE" = "true" ]; then
    echo "⚠️  $TARGET 은 git 저장소가 아닙니다."
    read -p "그래도 설치할까요? (y/N) " yn
    [ "$yn" != "y" ] && exit 0
  else
    echo "⚠️  $TARGET 은 git 저장소가 아닙니다 — 그대로 진행 (비대화형 모드)"
  fi
fi

echo "📦 cj-harness 설치 → $TARGET (mode: $MODE, interactive: $INTERACTIVE)"
echo ""

mkdir -p .claude/agents .claude/skills .claude/hooks

install_file() {
  local src="$1"
  local dst="$2"
  if [ "$MODE" = "symlink" ]; then
    rm -rf "$dst"
    ln -s "$src" "$dst"
    echo "  🔗 $dst → $src"
  else
    rm -rf "$dst"
    cp -R "$src" "$dst"
    echo "  📄 $dst"
  fi
}

# agents
echo "▶ agents/"
for f in "$HARNESS_DIR/payload/agents"/*.md; do
  base=$(basename "$f")
  install_file "$f" ".claude/agents/$base"
done

# skills (디렉토리 단위)
echo "▶ skills/"
for d in "$HARNESS_DIR/payload/skills"/*/; do
  base=$(basename "$d")
  install_file "$d" ".claude/skills/$base"
done

# hooks
echo "▶ hooks/"
for f in "$HARNESS_DIR/payload/hooks"/*.sh; do
  base=$(basename "$f")
  install_file "$f" ".claude/hooks/$base"
  chmod +x ".claude/hooks/$base"
done

if [ "$UPDATE_ONLY" = "true" ]; then
  echo ""
  echo "✅ 업데이트 완료 (agents/skills/hooks 만)."
  echo "settings.json 과 project.json 은 건드리지 않았습니다."
  exit 0
fi

# settings.json (없을 때만)
echo "▶ settings.json"
if [ -f ".claude/settings.json" ]; then
  echo "  ⏭  .claude/settings.json 이미 존재 — 건드리지 않음"
else
  cp "$HARNESS_DIR/payload/settings.json" ".claude/settings.json"
  echo "  📄 .claude/settings.json"
fi

# project.json (없으면 생성)
echo "▶ project.json"
if [ -f ".claude/project.json" ]; then
  echo "  ⏭  .claude/project.json 이미 존재 — 건드리지 않음"
else
  # 자동 추정 (default)
  DEFAULT_NAME=$(basename "$TARGET")
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@refs/remotes/origin/@@')
  [ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH=$(git branch --show-current 2>/dev/null)
  [ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"

  # ENV 변수 우선, 없으면 default
  NAME="${HARNESS_NAME:-$DEFAULT_NAME}"
  LANG="${HARNESS_LANG:-ko}"
  BASE_BRANCH="${HARNESS_BASE_BRANCH:-$DEFAULT_BRANCH}"
  STAGING_BRANCH="${HARNESS_STAGING_BRANCH:-}"
  TEST_CMD="${HARNESS_TEST_CMD-npm test}"
  LINT_CMD="${HARNESS_LINT_CMD-npm run lint}"
  BUILD_CMD="${HARNESS_BUILD_CMD-npm run build}"
  E2E_CMD="${HARNESS_E2E_CMD-}"
  GATES_DESIGNER="${HARNESS_GATES_DESIGNER:-true}"
  GATES_TDD="${HARNESS_GATES_TDD:-true}"
  GATES_PEER="${HARNESS_GATES_PEER:-true}"

  if [ "$INTERACTIVE" = "true" ]; then
    echo "  📝 .claude/project.json 인터랙티브 생성..."
    echo ""

    read -p "  프로젝트 이름 [$NAME]: " input
    NAME="${input:-$NAME}"

    read -p "  언어 (ko/en) [$LANG]: " input
    LANG="${input:-$LANG}"

    read -p "  baseBranch (prod) [$BASE_BRANCH]: " input
    BASE_BRANCH="${input:-$BASE_BRANCH}"

    if [ -z "$STAGING_BRANCH" ]; then
      read -p "  stagingBranch 사용? (없으면 그냥 enter) [없음]: " STAGING_BRANCH
    fi

    read -p "  test 명령 [${TEST_CMD:-none}]: " input
    TEST_CMD="${input:-$TEST_CMD}"
    [ "$TEST_CMD" = "none" ] && TEST_CMD=""

    read -p "  lint 명령 [${LINT_CMD:-none}]: " input
    LINT_CMD="${input:-$LINT_CMD}"
    [ "$LINT_CMD" = "none" ] && LINT_CMD=""

    read -p "  build 명령 [${BUILD_CMD:-none}]: " input
    BUILD_CMD="${input:-$BUILD_CMD}"
    [ "$BUILD_CMD" = "none" ] && BUILD_CMD=""

    if [ -z "$E2E_CMD" ]; then
      read -p "  E2E 테스트 명령 [없음]: " E2E_CMD
    fi
  else
    echo "  📝 .claude/project.json 비대화형 생성 (ENV / default)..."
    [ "$TEST_CMD" = "none" ] && TEST_CMD=""
    [ "$LINT_CMD" = "none" ] && LINT_CMD=""
    [ "$BUILD_CMD" = "none" ] && BUILD_CMD=""
  fi

  # protectedBranches 배열 구성
  PROTECTED="\"$BASE_BRANCH\""
  if [ -n "$STAGING_BRANCH" ]; then
    PROTECTED="$PROTECTED, \"$STAGING_BRANCH\""
    STAGING_JSON="\"$STAGING_BRANCH\""
  else
    STAGING_JSON="null"
  fi

  # null 처리
  json_or_null() {
    if [ -z "$1" ]; then echo "null"; else printf '"%s"' "$1"; fi
  }

  cat > .claude/project.json <<EOF
{
  "name": "$NAME",
  "language": "$LANG",

  "git": {
    "baseBranch": "$BASE_BRANCH",
    "stagingBranch": $STAGING_JSON,
    "protectedBranches": [$PROTECTED],
    "workTreeDir": ".worktrees",
    "branchPrefix": {
      "feature": "feature/",
      "hotfix": "hotfix/",
      "meta": "meta/"
    },
    "symlinkFromMain": [
      ".claude/settings.local.json"
    ]
  },

  "paths": {
    "docs": "docs",
    "decisions": "docs/decisions",
    "prd": null,
    "implementation": ["src/**", "app/**", "components/**", "lib/**"],
    "tests": {
      "unit": "tests/unit",
      "integration": "tests/integration",
      "e2e": "e2e/tests"
    },
    "testGlobs": ["tests/**", "e2e/**", "vitest.config.*", "playwright.config.*"]
  },

  "commands": {
    "test": $(json_or_null "$TEST_CMD"),
    "testUnit": null,
    "testIntegration": null,
    "testE2e": $(json_or_null "$E2E_CMD"),
    "lint": $(json_or_null "$LINT_CMD"),
    "typecheck": null,
    "build": $(json_or_null "$BUILD_CMD")
  },

  "gates": {
    "designer": $GATES_DESIGNER,
    "tdd": $GATES_TDD,
    "peerReview": $GATES_PEER
  },

  "pr": {
    "titleMaxChars": 70,
    "mergeStrategy": "squash"
  },

  "hooks": {
    "aws": {
      "requireReadOnlyProfile": false
    }
  }
}
EOF
  # JSON 문법 검증
  if command -v jq >/dev/null 2>&1; then
    if ! jq empty .claude/project.json 2>/dev/null; then
      echo "  ❌ project.json JSON 문법 오류 — 수동 검토 필요" >&2
      exit 1
    fi
  fi
  echo "  ✅ .claude/project.json 생성"
fi

# AGENTS.md (없을 때만)
echo "▶ AGENTS.md"
if [ -f "AGENTS.md" ]; then
  echo "  ⏭  AGENTS.md 이미 존재 — 건드리지 않음"
else
  cp "$HARNESS_DIR/payload/AGENTS.md" "AGENTS.md"
  echo "  📄 AGENTS.md (페이로드 복사 — 필요하면 프로젝트 컨텍스트로 다듬으세요)"
fi

# CLAUDE.md (없을 때만)
echo "▶ CLAUDE.md"
if [ -f "CLAUDE.md" ]; then
  echo "  ⏭  CLAUDE.md 이미 존재 — 건드리지 않음"
else
  cp "$HARNESS_DIR/payload/CLAUDE.md" "CLAUDE.md"
  echo "  📄 CLAUDE.md (페이로드 복사 — 프로젝트 컨텍스트를 채워주세요)"
fi

echo ""
echo "✅ 하네스 설치 완료!"
echo ""
echo "다음 단계:"
echo "  1. .claude/project.json 검토 — 브랜치명·테스트 명령 맞는지"
echo "  2. CLAUDE.md 채우기 — 프로젝트 컨텍스트 (도메인, 데이터 모델, 디자인 시스템 등)"
echo "  3. AGENTS.md 검토 — 협업 규약. 보통 그대로 두면 됨"
echo "  4. .gitignore 에 다음 추가 권장:"
echo "       .claude/settings.local.json"
echo "       .worktrees/"
echo "  5. (선택) 에이전트 팀 실험 플래그 — Claude Code 2.1.220 기준 없어도 동작합니다."
echo "     구버전 호환이 필요할 때만:"
echo "       echo '{\"env\": {\"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS\": \"1\"}}' > .claude/settings.local.json"
echo ""
