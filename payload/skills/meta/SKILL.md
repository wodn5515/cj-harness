---
name: meta
description: 메타 작업 (문서·설정·.claude 에이전트/스킬·CI 설정 등 코드 외 변경) 전용 경량 흐름. /work 와 달리 디자이너 게이트·TDD 게이트·peer 검증을 생략한다. 워크트리 + PR 은 그대로 쓴다. 사용자 가시 기능을 바꾸지 않는 변경에만 사용 — 코드 작업은 반드시 /work 로.
argument-hint: "<브랜치명 또는 작업주제> [작업설명]"
---

# 메타 작업 시작 (경량 흐름)

## 적용 대상 / 비적용 대상

### 적용 (이 스킬 사용)
- `README.md`, `CLAUDE.md`, `AGENTS.md`, `docs/**` 문서 변경
- `.claude/agents/**`, `.claude/skills/**`, `.claude/hooks/**`, `.claude/settings*.json`, `.claude/project.json` 수정
- `.gitignore`, dev 도구 (eslint / prettier / tsconfig 등) 설정
- CI 설정 (`.github/workflows/**`), 배포 설정
- 의존성 추가/제거 자체만 (구현 결합 없음)

### 비적용 (반드시 `/work` 사용)
- 사용자 가시 동작에 영향을 주는 모든 코드 (`project.json` 의 `paths.implementation`)
- 마이그레이션, 라우트 가드
- 사용자 가시 기능·라우트·UI 동작 변경

**판단 기준**: "이 변경이 사용자가 보는 화면·동작·데이터를 바꾸는가" 묻기. 아니면 `/meta`, 맞으면 `/work`.

---

## 1단계: 연속성 확인

```!
git worktree list
```
```!
WD=$(jq -r '.git.workTreeDir // ".worktrees"' .claude/project.json)
ls -1 "$WD" 2>/dev/null
```
```!
gh pr list --state all --limit 20
```

같은 주제 워크트리/PR 이 열려 있으면 그 위에서 이어가고, 새로 만들지 않는다.

## 2단계: 워크트리 생성

### 베이스 브랜치 결정

```!
jq -r '.git | "staging=\(.stagingBranch) base=\(.baseBranch)"' .claude/project.json
```

우선순위: `git.stagingBranch` (있으면) → `git.baseBranch`.
remote 에 해당 브랜치가 없으면 **부트스트랩 예외 분기** (아래 참고).

### 일반 경로
```!
git fetch origin
```
```bash
BASE_REMOTE=$(jq -r '.git.stagingBranch // .git.baseBranch' .claude/project.json)
MP=$(jq -r '.git.branchPrefix.meta // "meta/"' .claude/project.json)
WD=$(jq -r '.git.workTreeDir // ".worktrees"' .claude/project.json)
MP_DIR=${MP//\//-}

mkdir -p "$WD"
git worktree add -b "${MP}$0" "${WD}/${MP_DIR}$0" "origin/${BASE_REMOTE}"
```

### gitignored 파일 심링크
```bash
MP=$(jq -r '.git.branchPrefix.meta // "meta/"' .claude/project.json)
WD=$(jq -r '.git.workTreeDir // ".worktrees"' .claude/project.json)
WORKTREE="${WD}/${MP//\//-}$0"
for f in $(jq -r '.git.symlinkFromMain[]' .claude/project.json 2>/dev/null); do
  mkdir -p "$WORKTREE/$(dirname "$f")"
  ln -sf "$(pwd)/$f" "$WORKTREE/$f"
done
```

### 부트스트랩 예외 분기 (remote 에 베이스가 없음)
remote 가 비어 있거나 첫 push 전이면 워크트리를 생성할 수 없다. 다음 중 하나로 진행:
1. **즉시 사용 안 함** — Lead 가 현재 default 브랜치에서 직접 작업하고 커밋. PR 생략. 결정 로그에 "부트스트랩 예외: remote 없음" 사유 기록
2. **선행 push** — 사용자에게 `git push -u origin <default>` 안내. push 후 다시 `/meta` 실행

판단은 Lead 자율. 결정 로그에 사유 한 줄 남긴다.

## 3단계: 작업 진행 (Lead 단독)

- **팀 spawn 없음** — worker/lint/sfx 호출하지 않는다
- **test-writer 호출 없음** — TDD 게이트 생략
- **designer 호출 없음** — 메타 작업은 보통 UI 골격 잡는 단계가 아님
- Lead 가 직접 Read/Edit/Write 로 변경 작업 수행
- 커밋 메시지 언어는 `project.json` 의 `language` 따름. `[docs]`, `[chore]`, `[infra]` 등

### 검증
- 변경 파일이 `.sh` 면 `bash -n <file>` 으로 문법 체크
- `.json` / `.yaml` 은 `jq` / `python -c "import yaml; yaml.safe_load(open('<f>'))"` 로 파싱 확인
- 문서는 링크 깨짐만 확인
- 강제 자동화 아님. Lead 가 변경 성격에 맞게 골라서 수행

### 결정 로그
비자명한 결정이 발생한 경우 `<paths.decisions>/<slug>.md` 작성. 단순 오타·링크 수정은 불필요. 정책·운영 방침 변경은 필수.

## 4단계: PR 생성

워크트리에서 변경을 **커밋한 뒤** Lead 가 실행한다 (아래는 `bash` 지시 블록 — 스킬 로드 시
자동 실행되는 `!` 블록이 아니다. `!` 로 두면 브랜치 생성·커밋 전에 push 가 발화해
`src refspec ... does not match any` 로 실패한다).

```bash
MP=$(jq -r '.git.branchPrefix.meta // "meta/"' .claude/project.json)
git push -u origin "${MP}$0"
```

`/pr` 스킬 호출. PR 본문 템플릿은 `/pr` 기본 형식을 따르되 다음 섹션 명시:
- "## 작업 성격: 메타 (코드 변경 없음)"
- "## 테스트: 해당 없음 (메타 작업 — `/meta` 스킬 적용)"
- 결정 로그 링크 (있으면)

## 5단계: 리뷰 대기 / 머지 후 정리

- PR 생성 후 Lead 는 idle 유지. reviewer 가 코멘트를 남기면 Lead 가 자율 판단으로 응대 (코드 작업처럼 worker 위임 흐름은 없음 — Lead 직접 처리)
- 사용자 머지 확인 후:
```bash
WD=$(jq -r '.git.workTreeDir // ".worktrees"' .claude/project.json)
MP=$(jq -r '.git.branchPrefix.meta // "meta/"' .claude/project.json)
MP_DIR=${MP//\//-}
git worktree remove "${WD}/${MP_DIR}$0"
git branch -d "${MP}$0"
```

## /work vs /meta 비교

| 단계 | /work | /meta |
|---|---|---|
| 워크트리 | ✅ | ✅ |
| 디자이너 게이트 | 조건부 | ❌ |
| TDD 게이트 (test-writer) | 조건부 | ❌ |
| 팀 spawn (worker + lint + sfx) | ✅ (gates.peerReview) | ❌ (Lead 단독) |
| peer 검증 | ✅ (gates.peerReview) | ❌ |
| README 동기화 의무 | ✅ | 작업 자체가 README 면 그게 본문, 별개 |
| 결정 로그 | 비자명한 결정 시 | 비자명한 결정 시 |
| PR 생성 | ✅ | ✅ |
| 머지 후 정리 | ✅ | ✅ |

## 절대 금지
- 메타 워크플로우로 코드 변경 시도 (`paths.implementation`). 그건 `/work`.
- 보호 브랜치 (`git.protectedBranches`) 직접 push
- PR 머지 (사용자만)
- 첫 커밋이 메타 워크플로우의 게이트를 우회한다는 이유로 검증 절차를 생략하는 자의적 판단 — 메타 작업이라도 "이건 사실 코드 변경 아닌가" 의심되면 `/work` 로 전환
