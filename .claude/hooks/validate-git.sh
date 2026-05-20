#!/bin/bash
# git 명령어 검증 스크립트 (claude-harness)
# exit 0: 허용, exit 2: 차단 (stderr 메시지 표시)
#
# 보호 브랜치 목록은 프로젝트 .claude/project.json 의 git.protectedBranches 배열에서 읽는다.
# 파일이 없거나 jq 가 없으면 안전 기본값 ["main", "master", "stage"] 를 사용한다.
#
# 안전 기본값: 판별 불가한 엣지 케이스는 통과시킨다. 훅 자체의 오탐으로
# 정당한 push 가 막히는 것보다, 드물게 한 번 통과되는 편이 낫다.
#
# ----------------------------------------------------------------------
# 차단 규칙 (정탐 / 오탐 해소)
# ----------------------------------------------------------------------
# [정탐: 차단돼야 함]
#   git push origin <protected>
#   git push origin HEAD:<protected>
#   git push --force origin <branch>
#   git push -f origin feature/foo          # -f short option
#   git push -fu origin feature/foo         # -f 결합 플래그
#   git push -u origin <protected>
#   git push origin +<protected>            # force-refspec 접두사
#   git push origin refs/heads/<protected>  # 풀 ref
#   git push origin HEAD:refs/heads/<protected>
#   git push --force --force-with-lease ... # force 혼용 (우회 방지)
#   git push --force-with-lease --force ... # force 혼용 역순
#   (cwd 가 protected 브랜치인 worktree 에서) git push / git push origin
#
# [오탐 해소: 통과해야 함]
#   git push -u origin feature/stage-new-ui-enabled
#   git push origin feature/stage-cleanup
#   git push origin main-old-branch
#   git push origin feature/mainline
#   git push origin feature/foo:feature/foo                    # dst 가 feature
#   git push --force-with-lease origin feature/foo             # lease 단독
#   git push --force-with-lease=<ref>:<sha> origin feature/foo # lease expected-sha
#   git push --force-with-lease --force-if-includes ...        # lease + if-includes
# ----------------------------------------------------------------------

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

# ----------------------------------------------------------------------
# 보호 브랜치 목록 결정 (project.json → 기본값 fallback)
# ----------------------------------------------------------------------
# project.json 위치: cwd 의 git toplevel/.claude/project.json
#  - 워크트리에서 호출되면 워크트리의 project.json (보통 메인 것과 동일)
#  - jq 미설치, 파일 없음, 파싱 실패 → 모두 안전 기본값 사용
PROTECTED_DEFAULT=("main" "master" "stage")
PROTECTED_BRANCHES=()

resolve_protected_branches() {
  local toplevel=""
  if [ -n "$CWD" ] && [ -d "$CWD" ]; then
    toplevel=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
  fi
  if [ -z "$toplevel" ]; then
    PROTECTED_BRANCHES=("${PROTECTED_DEFAULT[@]}")
    return
  fi

  local cfg="$toplevel/.claude/project.json"
  if [ ! -f "$cfg" ] || ! command -v jq >/dev/null 2>&1; then
    PROTECTED_BRANCHES=("${PROTECTED_DEFAULT[@]}")
    return
  fi

  # jq 로 git.protectedBranches 배열을 한 줄씩 추출
  local parsed
  parsed=$(jq -r '.git.protectedBranches // [] | .[]' "$cfg" 2>/dev/null)
  if [ -z "$parsed" ]; then
    PROTECTED_BRANCHES=("${PROTECTED_DEFAULT[@]}")
    return
  fi
  while IFS= read -r line; do
    [ -n "$line" ] && PROTECTED_BRANCHES+=("$line")
  done <<< "$parsed"
}

resolve_protected_branches

is_protected() {
  local b="$1"
  for p in "${PROTECTED_BRANCHES[@]}"; do
    [ "$b" = "$p" ] && return 0
  done
  return 1
}

# ----------------------------------------------------------------------
# force push 차단
# ----------------------------------------------------------------------
# 방침:
#   - --force, -f → 차단
#   - --force-with-lease, --force-with-lease=<...>, --force-if-includes → 허용
#   - --force 와 --force-with-lease 가 함께 지정된 경우도 차단 (우회 소지)
if echo "$COMMAND" | grep -qE '\bgit[[:space:]]+push\b'; then
  PUSH_ARGS=$(echo "$COMMAND" | sed -E 's/^.*git[[:space:]]+push([[:space:]]+|$)//')
  IS_FORCE=0
  # --force 정확 일치 (다음 문자가 없거나 공백 — --force-with-lease, --force-if-includes 제외)
  if echo " $PUSH_ARGS " | grep -qE '[[:space:]]--force([[:space:]]|$)'; then
    IS_FORCE=1
  fi
  # -f short option (단독 또는 다른 short option 과 결합된 -fu 등)
  if echo " $PUSH_ARGS " | grep -qE '[[:space:]]-[A-Za-z]*f[A-Za-z]*([[:space:]]|$)'; then
    IS_FORCE=1
  fi
  if [ "$IS_FORCE" -eq 1 ]; then
    echo "🔴 차단: force push 는 허용되지 않습니다." >&2
    exit 2
  fi
fi

# ----------------------------------------------------------------------
# git merge 차단: 현재 브랜치가 보호 브랜치인 경우에만 차단
# ----------------------------------------------------------------------
# 의도: 보호 브랜치에 우회 머지 (PR 미경유) 를 막음.
# 작업 브랜치 (feature/* / hotfix/* / meta/*) 에서 origin/<base> 를 흡수해
# conflict 를 해소하는 정상 동기화는 허용. push 자체가 아래 로직에서 막히므로.
if echo "$COMMAND" | grep -qE 'git\s+merge\b'; then
  CURRENT_BRANCH=""
  if [ -n "$CWD" ] && [ -d "$CWD" ]; then
    CURRENT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
  fi
  if [ -n "$CURRENT_BRANCH" ] && is_protected "$CURRENT_BRANCH"; then
    echo "🔴 차단: 보호 브랜치 ($CURRENT_BRANCH) 에서 git merge 는 허용되지 않습니다. PR 을 통해서만 머지하세요." >&2
    exit 2
  fi
fi

# git reset --hard 차단
if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
  echo "🔴 차단: git reset --hard 는 허용되지 않습니다." >&2
  exit 2
fi

# PR 머지 차단 (gh pr merge)
if echo "$COMMAND" | grep -qE 'gh\s+pr\s+merge'; then
  echo "🔴 차단: PR 머지는 사용자가 직접 수행해야 합니다." >&2
  exit 2
fi

# ----------------------------------------------------------------------
# push 대상 브랜치 기반 차단 (보호 브랜치 직접 push, 머지된 PR 브랜치 push)
# ----------------------------------------------------------------------
if echo "$COMMAND" | grep -qE '\bgit[[:space:]]+push\b'; then
  # 1) push 명령어에서 브랜치명을 추출 (최우선)
  #    cwd 폴백은 명령어에 브랜치가 없거나 HEAD 만 적힌 경우에만.
  BRANCH=""
  KNOWN_FLAGS='(-u|--set-upstream|--follow-tags|--tags|--atomic|--dry-run|-n|--force-with-lease[^ ]*|--force|-f|-q|--quiet|-v|--verbose|--no-verify|--progress|--no-progress|--prune|--push-option=[^ ]*|--signed=[^ ]*|--recurse-submodules=[^ ]*|--ipv4|-4|--ipv6|-6|--thin|--no-thin|--mirror|--all)'
  ARGS=$(echo "$COMMAND" \
    | sed -E 's/^.*git[[:space:]]+push([[:space:]]+|$)//' \
    | sed -E "s/(^| )${KNOWN_FLAGS}( |$)/ /g")
  if echo "$ARGS" | grep -qE '^[[:space:]]*git[[:space:]]+push([[:space:]]|$)'; then
    ARGS=""
  fi
  REFSPEC=$(echo "$ARGS" | awk '{print $NF}')
  REFSPEC_ORIG="$REFSPEC"
  case "$REFSPEC" in
    *:*) REFSPEC="${REFSPEC##*:}" ;;
  esac
  REFSPEC="${REFSPEC#+}"
  REFSPEC="${REFSPEC#refs/heads/}"
  TOKEN_COUNT=$(echo "$ARGS" | wc -w | tr -d ' ')
  if [ "${TOKEN_COUNT:-0}" -ge 2 ] && [ -n "$REFSPEC" ] && echo "$REFSPEC" | grep -qE '^[A-Za-z0-9._/][A-Za-z0-9._/-]*$'; then
    BRANCH="$REFSPEC"
  fi

  # 2) 명령어에 브랜치 없거나 HEAD 만 적힌 경우 cwd 기반으로 판정
  if [ -z "$BRANCH" ] || [ "$REFSPEC_ORIG" = "HEAD" ]; then
    if [ -n "$CWD" ] && [ -d "$CWD" ]; then
      BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
    fi
  fi

  # 3) 보호 브랜치면 차단 (정확 일치 비교 — substring 매칭 금지)
  if [ -n "$BRANCH" ] && is_protected "$BRANCH"; then
    echo "🔴 차단: 보호 브랜치 '$BRANCH' 에 push 할 수 없습니다. PR 을 통해서만 머지하세요." >&2
    exit 2
  fi

  # 4) 보호 브랜치가 아니면 머지된 PR 여부 확인
  if [ -n "$BRANCH" ] && command -v gh >/dev/null 2>&1; then
    MERGED_PR=$(gh pr list --head "$BRANCH" --state merged --json number --jq '.[0].number // empty' 2>/dev/null)
    if [ -n "$MERGED_PR" ]; then
      echo "🔴 차단: 브랜치 '$BRANCH' 의 PR #$MERGED_PR 은 이미 머지되었습니다. 새 브랜치를 생성하세요." >&2
      exit 2
    fi
  fi
  # 브랜치 판별 실패 시 조용히 통과 (안전 기본값)
fi

exit 0
