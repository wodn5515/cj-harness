#!/bin/bash
# AWS MCP 호출 시 --profile read-only 강제 (claude-harness)
# exit 0: 허용, exit 2: 차단 (stderr 메시지 표시)
#
# 활성화 조건: 프로젝트 .claude/project.json 의 hooks.aws.requireReadOnlyProfile 가 true.
# 기본값은 false — AWS 안 쓰는 프로젝트에서 이 훅이 우연히 트리거돼도 통과.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.cli_command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# 프로젝트 설정 확인
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
REQUIRE=false
if [ -n "$CWD" ] && [ -d "$CWD" ] && command -v jq >/dev/null 2>&1; then
  TOPLEVEL=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$TOPLEVEL" ] && [ -f "$TOPLEVEL/.claude/project.json" ]; then
    REQUIRE=$(jq -r '.hooks.aws.requireReadOnlyProfile // false' "$TOPLEVEL/.claude/project.json" 2>/dev/null)
  fi
fi

if [ "$REQUIRE" != "true" ]; then
  exit 0
fi

# cli_command 가 배열인 경우 각 요소 검사
IS_ARRAY=$(echo "$INPUT" | jq -r '.tool_input.cli_command | if type == "array" then "yes" else "no" end' 2>/dev/null)

if [ "$IS_ARRAY" = "yes" ]; then
  BAD_CMD=$(echo "$INPUT" | jq -r '.tool_input.cli_command[] | select(contains("--profile read-only") | not)')
  if [ -n "$BAD_CMD" ]; then
    echo "🔴 차단: AWS MCP 호출 시 반드시 '--profile read-only' 를 사용해야 합니다." >&2
    exit 2
  fi
else
  if ! echo "$COMMAND" | grep -q '\-\-profile read-only'; then
    echo "🔴 차단: AWS MCP 호출 시 반드시 '--profile read-only' 를 사용해야 합니다." >&2
    exit 2
  fi
fi

exit 0
