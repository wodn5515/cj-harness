---
name: work
description: 새 기능 작업을 시작할 때 사용한다. 먼저 기존 워크트리와 PR 상태를 확인하여 이어서 작업할지 새로 시작할지 판단한 후, 필요하면 stagingBranch (없으면 baseBranch) 기반으로 worktree 를 생성한다. 이후 Lead (메인 세션) 가 worker·lint·sfx 를 이름과 함께 spawn 한다.
argument-hint: "<브랜치명 또는 작업주제> [작업설명]"
---

# 작업 시작

이 스킬은 프로젝트 루트의 **`.claude/project.json`** 을 기반으로 동작한다. 아래 절차에 등장하는 `<base>`, `<staging>`, `<workTreeDir>`, `<featurePrefix>`, `<commands.test>` 등은 모두 `project.json` 에서 읽은 값으로 치환된다.

```!
cat .claude/project.json 2>/dev/null || echo "⚠️ .claude/project.json 없음 — 하네스 설치가 필요합니다 (~/.claude-harness/install.sh)"
```

기본 매핑:
- `<base>` = `git.baseBranch` (예: `main`, `master`)
- `<staging>` = `git.stagingBranch` (있으면 그 값, 없으면 `<base>`)
- `<workTreeDir>` = `git.workTreeDir` (예: `.worktrees`)
- `<featurePrefix>` = `git.branchPrefix.feature` (예: `feature/`)
- `<commands.test>` = `commands.test` (예: `npm test`)
- `<commands.lint>` = `commands.lint` (예: `npm run lint`)
- `<commands.build>` = `commands.build` (예: `npm run build`)
- `<commands.testE2e>` = `commands.testE2e` (있으면 그 값, 없으면 생략)
- `<decisionsDir>` = `paths.decisions` (예: `docs/decisions`)

## 0단계: 워크플로우 경로 판정 (필수)

`/work` 는 **정식 경로**와 **경량 경로** 두 종류로 갈라진다. Lead 가 작업 시작 시 자율 판단해 둘 중 하나 선택. 애매하면 정식.

### 정식 경로 — 다음 중 하나라도 해당하면
- 새 라우트 / 새 Server Action / 새 가드 분기 / 새 마이그레이션 추가
- 인증·인가·세션 흐름 변경
- 데이터 모델 / 스키마 / 검증 규칙 변경
- 비즈니스 룰 변경 (정렬·필터·매칭 등)
- 사용자 행동 흐름 변경 (페이지 동작·폼 제출 분기·에러 처리)
- 디자인 시스템 / UI 프리미티브 확장

→ **디자이너 게이트 (조건부) + TDD 게이트 (조건부) + 에이전트 spawn + peer 검증** 전체 적용.

### 경량 경로 — 다음을 **모두** 만족할 때만
1. 새 라우트 / Server Action / 새 가드 분기 / 새 마이그레이션 **없음**
2. 인증·인가·세션 흐름 **무변경**
3. 데이터 모델 / 검증 스키마 **무변경**
4. 변경 표면: 순수 유틸 함수 추가 또는 카피 / className / Badge variant 등 시각 표현만
5. `<commands.lint>` + `<commands.build>` 통과만으로 회귀 차단 충분 (TDD 의 회귀 net 가치가 비용 초과하지 않음)

→ 디자이너·TDD·에이전트 spawn·peer **모두 생략**. Lead 단독으로 Read/Edit/Write + lint + build + PR.

다음 단계부터는 **정식 경로** 기준 절차. 경량 경로면 3단계 (에이전트 세팅) 생략하고 4단계 (워크트리 정리) 로 진입.

## 1단계: 연속성 확인 (필수)

작업을 시작하기 전에 반드시 다음을 순서대로 확인한다.

### 기존 워크트리 확인
```!
git worktree list
```
```!
FP=$(jq -r '.git.branchPrefix.feature // "feature/"' .claude/project.json)
WD=$(jq -r '.git.workTreeDir // ".worktrees"' .claude/project.json)
ls -1 "$WD" 2>/dev/null | grep -E "^${FP//\//-}"
```

### 관련 PR 확인
```!
gh pr list --state all --limit 20
```

### 판단

| 상황 | 행동 |
|------|------|
| 같은 주제의 워크트리가 존재하고 PR 이 **열려있음** | 해당 워크트리 경로를 안내. 새로 만들지 않음 |
| 같은 주제의 PR 이 **머지됨** + 워크트리 존재 | 워크트리 정리 (`git worktree remove`) 후 새 워크트리 생성 |
| 같은 주제의 PR 이 **머지됨** + 워크트리 없음 | 후속 작업이면 새 워크트리 생성 (브랜치명 변경) |
| 같은 주제의 PR 이 **닫힘** | 사유 확인 후 새 워크트리/브랜치로 재작업 |
| 관련 워크트리/PR 없음 | 새 워크트리 생성 |

## 2단계: 워크트리 생성 (새 작업인 경우)

```!
git fetch origin
```

```bash
BASE=$(jq -r '.git.baseBranch // "main"' .claude/project.json)
STAGE=$(jq -r '.git.stagingBranch // empty' .claude/project.json); STAGE=${STAGE:-$BASE}
FP=$(jq -r '.git.branchPrefix.feature // "feature/"' .claude/project.json)
WD=$(jq -r '.git.workTreeDir // ".worktrees"' .claude/project.json)
FP_DIR=${FP//\//-}   # feature/ → feature-

mkdir -p "$WD"
git worktree add -b "${FP}$0" "${WD}/${FP_DIR}$0" "origin/${STAGE}"
```

> `<featurePrefix-base>` 는 prefix 의 `/` 을 `-` 로 치환한 dir 친화 이름 (예: `feature/` → `feature-`).

### gitignored 파일 심링크 (필수)

`project.json` 의 `git.symlinkFromMain` 배열에 있는 파일들을 메인 워킹트리에서 워크트리로 심링크한다. tracked 파일 (이미 git 이 처리) 은 심링크할 필요 없다.

```bash
FP=$(jq -r '.git.branchPrefix.feature // "feature/"' .claude/project.json)
WD=$(jq -r '.git.workTreeDir // ".worktrees"' .claude/project.json)
WORKTREE="${WD}/${FP//\//-}$0"
for f in $(jq -r '.git.symlinkFromMain[]' .claude/project.json 2>/dev/null); do
  # 디렉토리 보장
  mkdir -p "$WORKTREE/$(dirname "$f")"
  ln -sf "$(pwd)/$f" "$WORKTREE/$f"
done
```

## 2.4단계: 디자이너 게이트 (UI 비중이 큰 작업이면 단발 호출)

`project.json` 의 `gates.designer` 가 `true` 이고 작업 성격이 다음 중 하나면 Lead 가 **TDD 게이트보다 먼저** `designer` 를 단발 호출한다:
- 디자인 시스템 / 글로벌 토큰 / 글로벌 유틸 재설계
- 신규 페이지 레이아웃 첫 구현
- 신규 모달 UX (큰 폼 / 다단계 위저드)
- UI 프리미티브 셋 확장

```
Agent({
  subagent_type: "designer",
  description: "<프로젝트> UI 골격 구현",
  prompt: "워크트리: <절대경로>\n작업 주제: <한 줄>\n관련 PRD/결정: <PRD §X / decisions/...>\n구체 요청: <어떤 컴포넌트/페이지를>\n\n제약: 테스트 파일·마이그레이션 수정 금지. 프로젝트 CLAUDE.md 의 디자인 시스템 섹션과 글로벌 토큰 파일을 먼저 읽고, 그 안에서 컴포넌트 골격을 구현. 모바일 우선 반응형. 데이터 결합은 worker 몫이라 mock/props 로만. [ui] prefix 로 커밋하고 보고 후 종료."
})
```

`name` 없이 단발 호출한다 — 이름을 주지 않으면 재개 대상이 아닌 일회성 호출이 된다. designer 가 보고하면 **Lead 가 자율적으로** UI 톤·컴포넌트 골격을 채택할지 판단하고, 비자명한 결정을 `<decisionsDir>/<slug>.md` 에 기록한 뒤 2.5단계로 넘어간다. 사용자에게 묻지 않는다.

## 2.5단계: TDD 게이트 (사용자 행동 흐름이 바뀌는 작업이면 필수)

`project.json` 의 `gates.tdd` 가 `true` 이고 작업이 사용자 행동 흐름을 바꾸면 에이전트를 spawn 하기 **전에** Lead 가 `test-writer` 를 단발로 호출해 실패하는 E2E + 통합 + 단위 spec 을 먼저 잡는다. **사용자 승인 게이트 없음** — Lead 가 자율 판단으로 spec 을 채택하고 결정 로그를 남긴 뒤 3단계 에이전트 세팅으로 넘어간다.

### 작업 성격 판단

| 작업 성격 | test-writer 선호출 |
|-----------|---------------------|
| 새 라우트 / 기존 라우트 동작 변경 | **필수** |
| 폼 제출·검증 | **필수** |
| 세션·인증·권한 게이트 | **필수** |
| 비즈니스 룰 (만료·정렬·매칭·atomic 등) | **필수** |
| 데이터 모델 변경 (마이그레이션 포함) | **필수** (통합 테스트로 검증) |
| 사용자 흐름 / 페이지 동작 변경 | **필수** (E2E 우선) |
| 순수 스타일 리뉴얼 (토큰 조정 등) | 선택 — 기존 smoke 회귀만 |
| 문구/카피, 정적 텍스트 변경 | 불필요 |
| 내부 리팩토링 (외부 동작 동일) | 불필요 |
| 마이그레이션 단독, infra/CI 설정 | 불필요 |
| 문서·주석 변경 | 불필요 (`/meta` 대상) |

생략한 경우 Lead 가 한 줄로 사유를 결정 로그에 명시하고 3단계로 넘어간다 (예: "TDD 선작성 생략 — 사유: 스타일 리뉴얼만").

### test-writer 단발 호출 (필수 케이스)

```
Agent({
  subagent_type: "test-writer",
  description: "TDD 선작성 spec 작성",
  prompt: "워크트리: <절대경로>\n작업 주제: <한 줄 요약>\n사용자 시나리오: <어떤 페이지에서, 어떤 행동이, 어떤 결과로>\n인증 컨텍스트: <비로그인 / 인증된 사용자 / 관리자 등>\n관련 데이터 모델: <어떤 엔티티/테이블을 어떻게>\n기존 관련 spec: <경로 또는 '없음'>\n\n현재 코드 기준 빨갛게 실패하는 spec (E2E + 통합 + 단위 스켈레톤) 을 작성하고 project.json 의 commands 명령으로 실패를 확인한 뒤 보고해라. 구현은 절대 손대지 마라. 사용자 승인 요청 형식이 아니라 Lead 에게 보고하는 형식으로."
})
```

`name` 없이 단발로 호출한다 (test-writer 는 peer 검증 흐름의 멤버가 아니라 일회성 도우미 — 이름을 주지 않으므로 재개 대상도 아니다).

### Lead 자율 판단 게이트

test-writer 가 spec 과 실패 로그를 보고하면 **Lead 가 자율적으로 판단**한다 — 사용자에게 묻지 않는다.
- 시나리오·검증 포인트가 적절하면 채택 → 결정 로그 작성 → 3단계 에이전트 세팅
- 시나리오 수정이 필요하면 test-writer 를 재호출해 spec 갱신 → 결정 로그에 수정 사유 기록
- spec 이 너무 강하면 약화, 너무 약하면 강화 — 모두 Lead 판단

결정 로그는 `<decisionsDir>/<slug>.md` 로 그 작업 워크트리에 추가한다.

### 3단계 에이전트 spawn 시 worker 프롬프트에 포함할 사항 (TDD 게이트를 통과한 경우)

worker spawn 프롬프트의 요구사항 섹션에 다음을 명시한다:
- "선작성된 spec: `<paths.tests.e2e>/<경로>.spec.ts`, `<paths.tests.unit>/<경로>.test.ts` — 이 모든 테스트를 통과시키는 게 작업 목표"
- "통과를 위해 spec 자체를 약화시키지 마라. 약화가 필요하면 Lead 에 보고 — Lead 가 자율 판단해 spec 을 갱신"
- "README.md / CLAUDE.md 사실 영역 동기화 의무: 사용자 가시 기능·스택·사이트맵·데이터 모델이 변경되면 함께 갱신"

## 3단계: 에이전트 세팅 (Lead = 메인 세션이 수행)

워크트리가 준비되면 **Lead 가** 다음을 이 순서대로 실행한다.

> `project.json` 의 `gates.peerReview` 가 `false` 면 spawn 생략 — Lead 단독 워크플로우. 경량 경로와 동일하게 4단계로.

### 3-1. 팀 생성 단계는 없다

세션에는 **암묵적 팀이 하나** 있고 별도 생성 절차가 없다. `Agent` 호출에 `name` 을 주면 그 이름이 곧 통신 주소가 된다 (`SendMessage(to: "<이름>")`). 이름은 에이전트가 **완료된 뒤에도 유효**하며, 이름으로 메시지를 보내면 그 에이전트의 transcript 가 재개된다.

- 같은 이름을 나중 spawn 이 가져가면 **최신이 이긴다**. 한 워크트리 작업 안에서 `worker`/`lint`/`sfx` 이름을 재사용하지 않는다.
- `Agent` 는 **기본 백그라운드 실행**이다. Lead 는 spawn 후 턴을 마치고, 완료 알림이나 `SendMessage` 로 이어받는다.

### 3-2. 에이전트 3 명 병렬 spawn (한 메시지에 세 Agent 호출)

```
Agent({
  subagent_type: "worker",
  name: "worker",
  description: "<작업 주제 한 줄>",
  prompt: "작업 프롬프트. 반드시 포함:\n- 워크트리 경로: <절대경로>\n- 브랜치/베이스 정보 (feature/<slug> ← origin/<staging>)\n- 선작성된 spec 경로 목록 (있으면)\n- 테스트 파일 (paths.testGlobs) 수정 금지 — 약화 필요 시 Lead 에 보고\n- README.md / CLAUDE.md 사실 영역 동기화 의무\n- 구체적 요구사항·설계 결정·제약\n- 작업 완료 시 commands.test 통과 확인 후 lint 와 sfx 에게 SendMessage 로 검증 요청"
})

Agent({
  subagent_type: "lint-checker",
  name: "lint",
  description: "린트 검사 담당",
  prompt: "이 spawn 은 **이름 선점** 목적이다. 지금은 검사할 대상이 없으니 아무 작업도 하지 말고 '대기 준비 완료' 한 줄만 남기고 즉시 종료해라. 이후 worker 가 SendMessage 로 검증을 요청하면 네 transcript 가 그대로 재개된다. 그때 .claude/agents/lint-checker.md 의 절차대로 검사하고 결과를 worker 에게 SendMessage 로 회신해라."
})

Agent({
  subagent_type: "side-effect-checker",
  name: "sfx",
  description: "사이드이펙트 검사 담당",
  prompt: "이 spawn 은 **이름 선점** 목적이다. 지금은 검사할 대상이 없으니 아무 작업도 하지 말고 '대기 준비 완료' 한 줄만 남기고 즉시 종료해라. 이후 worker 가 SendMessage 로 검증을 요청하면 네 transcript 가 그대로 재개된다. 그때 .claude/agents/side-effect-checker.md 의 절차대로 검사하고 결과를 worker 에게 SendMessage 로 회신해라."
})
```

**lint·sfx 를 미리 spawn 하는 이유는 이름 등록 하나뿐이다.** 이름이 등록돼 있어야 worker 가 `SendMessage(to: "lint")` 로 깨울 수 있다. 두 에이전트는 spawn 직후 곧바로 완료되며, 그게 정상이다.

### 3-3. 작업 진행 (PR 생성까지)

worker 가 PR 생성 보고를 Lead 에게 SendMessage 로 보낼 때까지 대기.
중간에 사용자가 추가 지시를 주면 Lead 가 `SendMessage(to: "worker", ...)` 로 전달.

### 3-4. 리뷰 대기 (이름 유지)

worker 가 PR 생성 보고를 보내면:
- worker·lint·sfx 는 할 일이 없으므로 **완료 상태로 들어간다. 그게 정상이고, 되살릴 필요 없다.**
- 이름은 계속 유효하다. 리뷰 코멘트가 오면 `SendMessage(to: "worker")` 로 그 transcript 를 재개하면 되고, 작업 맥락은 그대로 남아 있다.
- Lead 는 사용자에게 PR URL 을 보고하고 리뷰 결과를 기다린다.
- **같은 이름으로 새 에이전트를 다시 spawn 하지 않는다** — 새로 spawn 하면 이름을 빼앗아 이전 맥락에 도달할 수 없게 된다.

### 3-5. 리뷰 코멘트 응대

리뷰 코멘트가 달리면 Lead 가 다음 중 하나로 진행한다:
1. Lead 가 `gh pr view <번호> --comments` 로 코멘트를 읽고 자율 판단으로 우선순위와 적용 방향을 정함 → 요약·우선순위와 함께 `SendMessage(to: "worker", ...)` 로 전달
2. 반영 방향이 비자명한 결정이면 결정 로그에 추가 (`<decisionsDir>/<slug>.md` 에 "## 리뷰 응대" 섹션 append)
3. worker 가 수정 → lint·sfx 재검증 → 추가 커밋 push → Lead 에 보고
4. 추가 라운드가 필요하면 3-5 반복

응대 사이클이 끝나고 사용자가 머지를 진행할 때까지 이름을 재사용하지 않는다.

### 3-6. 머지 후 정리

사용자가 PR 을 직접 머지한 사실을 확인한 후 (`gh pr view <번호> --json state` → `MERGED`):

**팀 종료 절차는 없다.** 에이전트는 이미 완료 상태이므로 별도로 거둬들일 대상이 아니고, `shutdown_request` 는 요청받지 않은 이상 먼저 보내지 않는다. 머지 후 정리는 4단계의 워크트리·브랜치 정리가 전부다.

예외 — 아직 **실행 중인** 백그라운드 에이전트가 남아 있으면 (긴 작업이 걸려 있거나 잘못 spawn 된 경우) 이름으로 중단한다:
```
TaskStop({task_id: "worker"})
```

## 4단계: 워크트리 정리 (머지 후)

PR 머지 후:
```bash
FP=$(jq -r '.git.branchPrefix.feature // "feature/"' .claude/project.json)
WD=$(jq -r '.git.workTreeDir // ".worktrees"' .claude/project.json)
git worktree remove "${WD}/${FP//\//-}$0"
git branch -d "${FP}$0"
```

---

## 부록: 결정 로그 작성 (Lead 의무)

작업 흐름 곳곳에서 Lead 가 비자명한 결정을 내릴 때마다 `<decisionsDir>/<slug>.md` 로 기록한다.

### 파일명 = slug (번호 없음)
서술적 kebab-case slug 로 짓는다 — **번호 없음** (예: `multi-device-push.md`). 본문 첫머리에 `- 날짜: YYYY-MM-DD` 로 순서를 남긴다 (번호 대신 날짜·git 히스토리가 순서).
- 순차 번호(NNN)는 병렬 세션이 같은 "다음 번호"를 동시 선점하는 충돌로 폐지 — 근거는 `AGENTS.md` §2-2.
- 기존 `NNN-*.md` 는 grandfather (리네임 금지, 그대로). 같은 slug 가 이미 있으면 더 구체적으로 (`-server`/`-app` 등).

### 작성 시점
- TDD 게이트에서 spec 채택/수정/거절 판단을 내린 직후
- 디자이너 결과 검토 후 톤·골격 채택 판단
- worker 가 spec 약화를 요청해 Lead 가 판단한 직후
- 데이터 모델·validation·엣지 케이스 처리 방침을 정한 직후
- 리뷰 코멘트 응대 방향이 비자명한 경우

### 작성 위치
그 작업의 워크트리에서 작업의 커밋 안에 포함시킨다. 별도 PR 로 분리하지 않는다. PR 본문에 "관련 결정 로그: `<decisionsDir>/<slug>.md`" 한 줄로 링크.

### 사용자 개입 처리
사용자가 결정에 대해 직접 의견을 주면 (예: "그렇게 말고 X 로 해줘") 결정 파일에 "## 사용자 개입 (<YYYY-MM-DD>)" 섹션을 append 하고 사용자 지시·변경된 결정을 기록한다. 기존 "결정" 을 통째로 덮어쓰지 않는다.
