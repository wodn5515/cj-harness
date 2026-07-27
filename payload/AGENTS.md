# AGENTS.md — 에이전트 운영 규칙

> 이 파일은 OpenAI 가 제안하고 Claude Code / Cursor 등이 호환 읽는 **에이전트 협업 표준 문서**다.
> 프로젝트 컨텍스트 (컨셉 / 스택 / 데이터 모델 / 디자인) 는 [`CLAUDE.md`](./CLAUDE.md) 에 있다.
> 사람이 읽기 위한 게 아니라 **에이전트가 작업 시작 전 반드시 참조**하기 위한 운영 매뉴얼이다.
>
> 이 파일은 [claude-harness](https://github.com/<user>/claude-harness) 의 일반 템플릿을 복사한 것으로, 프로젝트 고유 정책이 더 있으면 같은 파일에 섹션 추가해도 된다 (분리 권장은 아님 — 한 곳에서 보는 게 운영하기 쉬움).

---

## 0. 단일 진실 원천 — `.claude/project.json`

브랜치명·테스트 명령·디렉토리 구조 등 프로젝트별로 달라지는 모든 값은 **`.claude/project.json`** 에 정의된다. 모든 에이전트와 스킬은 이 파일을 읽어 동작한다.

핵심 키 (자세한 스키마는 `~/.claude-harness/templates/project.schema.json`):

| 키 | 의미 |
|---|---|
| `git.baseBranch` | prod 머지 대상 (예: `main`, `master`) |
| `git.stagingBranch` | feature 머지 대상 — `null` 이면 staging 단계 없음 |
| `git.protectedBranches` | 직접 push 금지 브랜치 — 훅이 참조 |
| `git.workTreeDir` | 워크트리 부모 디렉토리 |
| `git.branchPrefix.{feature,hotfix,meta}` | 브랜치 prefix |
| `paths.implementation` | worker 가 수정 가능한 코드 경로 |
| `paths.testGlobs` | test-writer 전용 경로 (worker 는 읽기만) |
| `paths.decisions` | 결정 로그 디렉토리 |
| `commands.test / testE2e / lint / typecheck / build` | 테스트·빌드 명령 |
| `gates.designer / tdd / peerReview` | 게이트 활성화 여부 |

`project.json` 이 없으면 작업을 중단하고 사용자에게 하네스 설치를 안내한다.

## 1. 에이전트 목록

| 이름 | 역할 | 모델 | 테스트 파일 권한 | 구현 파일 권한 |
|---|---|---|---|---|
| **`worker`** | 구현 코드 작성 (feature/bugfix/refactor) | inherit | **읽기 전용** | 읽기·쓰기 |
| **`test-writer`** | 모든 레이어 테스트 작성 (단위/통합/E2E) | inherit | 읽기·쓰기 | **읽기 전용** |
| `lint` (`lint-checker`) | 린트·포매팅·스타일 검사 | haiku | 읽기 전용 | 읽기 전용 |
| `sfx` (`side-effect-checker`) | 사이드이펙트·로직·보안 검사 | inherit | 읽기 전용 | 읽기 전용 |
| `designer` | UI/UX 디자인 시스템 + UI 컴포넌트 골격 — **§5-4 조건 시에만 단발 호출** | inherit | 읽기 전용 | 읽기·쓰기 (UI 영역만) |
| `reviewer` | PR 코드 리뷰 (별도 세션) | inherit | 읽기 전용 | 읽기 전용 |

권한은 시스템 강제가 아닌 **운영 규약**이다. 어겼을 때 peer 검증 단계 (lint/sfx) 에서 차단된다.

## 2. Lead 자율 판단 + 결정 로그 (핵심 원칙)

이 협업 모델은 **사용자 승인 게이트가 없다**. 작업 중 발생하는 모든 비자명한 판단은 **Lead (메인 세션) 에이전트가 자율적으로 결정**하고, 그 즉시 `<paths.decisions>/<slug>.md` 에 결정 로그를 남긴다.

### 2-1. Lead 의 권한과 책임

- 프로젝트 PRD · 기존 결정 로그 · `CLAUDE.md` 를 근거로 **자율 판단**한다
- 모호하면 **합리적 기본값**을 선택하고 로그에 사유를 적는다 (사용자에게 묻지 않음)
- spec 약화, 데이터 모델 변경, 마이그레이션 전략, validation 규칙, 엣지 케이스 처리 등 모두 Lead 가 결정
- 사용자가 명시적으로 끼어들 때만 (예: "그건 다르게 해줘") 결정을 수정하고 로그에 "사용자 개입" 섹션을 append

### 2-2. 결정 로그 작성 의무

- 비자명한 결정이 생긴 **그 작업의 커밋 안에** `<paths.decisions>/<slug>.md` 를 추가한다 (별도 PR 금지)
- **파일명 = 서술적 kebab-case slug, 번호 없음** (예: `multi-device-push.md`). 본문 첫머리에 `- 날짜: YYYY-MM-DD` 를 적어 시간순을 남긴다 — 번호 대신 날짜·git 히스토리가 순서. 같은 slug 가 이미 있으면 더 구체적으로(`-server`/`-app`/`-v2` 등) 짓는다.
  - **순차 번호(NNN) 폐지 사유**: 병렬 세션이 동시에 같은 "다음 번호"를 선점해 충돌이 반복됨(번호 예약/리넘버 churn). slug 는 서술적이라 동시 작성해도 충돌하지 않는다.
  - **기존 `NNN-<slug>.md` 는 grandfather** — 리네임하지 않고 그대로 둔다. 디렉토리는 구(`NNN-`)·신(slug) 혼재가 정상. 구 결정 참조는 "decision NNN" 유지, 신규는 slug 로 참조("decision: <slug>").
- 템플릿: 날짜 / 배경 / 결정 / 근거 / 거절된 대안 / 후속 영향
- PR 본문에 "관련 결정 로그: `<paths.decisions>/<slug>.md`" 한 줄로 링크

### 2-3. 기록할 결정의 예

- TDD 게이트에서 작성한 spec 시나리오와 검증 포인트
- worker 가 spec 통과가 어렵다고 보고했을 때 Lead 의 약화/유지 판단
- 디자이너 호출 여부와 그 결과 톤
- 데이터 모델 변경 (테이블 / 컬럼 / 마이그레이션)
- 인가·세션·토큰 정책 변경
- 도메인 비즈니스 룰 변경 (만료·정렬·매칭 알고리즘 등)

### 2-4. 기록하지 않는 결정

- 단순 버그 수정, 명백한 오타/스타일 교정
- PRD / 이전 결정 로그에 이미 명시된 사항의 단순 적용
- 코드 변경의 무엇/어떻게 (PR 본문이 표현)

## 3. 테스트와 구현의 분리 (핵심 원칙)

이 협업 모델은 **TDD 선작성 + 에이전트 분리**다.

### 3-1. 분리 원칙

- **`test-writer`** 는 테스트 파일만 다룬다 — `project.json` 의 `paths.testGlobs` 만 쓰기. `paths.implementation` 은 **읽기만**.
- **`worker`** 는 구현 파일만 다룬다 — `paths.testGlobs` 는 **읽기만**. 테스트 spec 을 통과시키기 위해 테스트를 수정하는 것은 금지.
- 두 에이전트는 PR 안에서 **별개의 커밋**으로 작업한다 (commit prefix: `[test]` = test-writer, `[feat]`/`[fix]` 등 = worker).

### 3-2. 작업 라운드

```
[라운드 1] test-writer 선작성
  ├── E2E spec (paths.tests.e2e)
  ├── 통합 테스트 (paths.tests.integration) — server action / DB 인접
  └── 단위 테스트 스켈레톤 (paths.tests.unit) — 함수 시그니처/계약 기반
  ↓
  commands.test + commands.testE2e
  → 새 테스트 모두 빨갛게 실패해야 함
  ↓
[Lead 검토] spec 시나리오와 검증 포인트를 Lead 가 판단 → 채택 결정을
            <paths.decisions>/<slug>.md 에 기록
  ↓
[라운드 2] worker 구현
  ├── 구현 코드 작성
  ├── 모든 선작성 테스트가 초록으로 통과
  └── peer 검증 (lint + sfx, gates.peerReview = true 일 때)
  ↓
[라운드 3] test-writer 단위 테스트 보강 (선택)
  ├── worker 구현 구조를 보고 누락된 엣지 케이스/분기 커버리지 추가
  └── 새 테스트도 빨갛게 실패 → worker 가 보완 → 초록
  ↓
[PR 생성] worker 가 /pr 스킬로
```

### 3-3. spec 약화는 Lead 가 결정

worker 가 구현 중 "이 spec 은 통과 불가능하거나 의도와 맞지 않다" 고 판단하면 `SendMessage` 로 Lead 에 보고한다. **Lead 가 자율적으로** spec 유지/약화/강화를 판단하고:
- 결정을 `<paths.decisions>/<slug>.md` 에 추가
- 약화/수정이면 `test-writer` 단발 재호출로 spec 갱신
- worker 재진입

worker 가 임의로 테스트를 수정하거나 spec 을 우회하는 구현을 하면 안 된다.

## 4. 협업 모드 동작

### 4-0. 실행 모델 (전제)

> 아래는 Claude Code **2.1.220 에서 실측 확인**한 동작이다. 어느 버전부터 이 형태인지는 특정하지 않는다.

- **팀 생성·삭제 단계가 없다.** 세션당 암묵적 팀이 하나 있고 `TeamCreate` / `TeamDelete` 툴은 존재하지 않는다. `Agent` 의 `team_name` 파라미터도 deprecated (무시됨).
- **이름이 곧 주소다.** `Agent({subagent_type, name: "worker", ...})` 로 spawn 하면 `SendMessage(to: "worker")` 로 통신한다.
- **완료는 소멸이 아니다.** 할 일이 없는 에이전트는 idle 로 머무는 게 아니라 **완료**된다. 그래도 이름은 유효하며, 이름으로 메시지를 보내면 그 **transcript 가 재개**되어 이전 맥락을 그대로 이어간다.
- **같은 이름은 최신이 이긴다.** 한 작업 안에서 이름을 재사용하면 이전 에이전트에 도달할 수 없게 된다.
- `Agent` 는 **기본 백그라운드 실행**. 동기 실행이 필요하면 `run_in_background: false`.
- **`shutdown_request` 를 먼저 보내지 않는다.** legacy 프로토콜로 분류돼 있고, 요청받지 않은 이상 originate 금지다. 실행 중인 백그라운드 에이전트를 멈춰야 하면 `TaskStop({task_id: "<이름>"})`.

### 4-1. 표준 구성

Lead (메인 세션) 가 다음 3 명을 이름과 함께 spawn:
- `worker` — 구현
- `lint` — 린트 검사
- `sfx` — 사이드이펙트 검사

`lint` 와 `sfx` 를 미리 spawn 하는 목적은 **이름 등록 하나뿐**이다. 이름이 있어야 worker 가 나중에 깨울 수 있다. 두 에이전트는 spawn 직후 곧바로 완료되며 그게 정상 동작이다.

`test-writer` 는 **peer 검증 흐름의 멤버가 아니다**. Lead 가 이름 없이 단발 (`Agent` 호출 한 번) 로 호출해 spec 을 잡고, Lead 가 검토한 뒤 결정 로그를 남긴다.

`gates.peerReview = false` 면 spawn 자체를 생략 — Lead 단독 모드. 1 인 빠른 토이 / 매우 단순한 변경만 하는 프로젝트가 여기 해당.

### 4-2. 메시지 규약

- 통신은 **`SendMessage(to: "<이름>")`** 으로만. agentId 는 이름이 없거나 이름을 뺏긴 경우에만.
- 이름: `worker`, `lint`, `sfx`. Lead 에게 보낼 때는 incoming message 의 발신자 이름을 그대로 쓴다.
- **plain text 출력은 다른 에이전트에게 전달되지 않는다.** 반드시 `SendMessage` 호출.
- `summary` 는 5~10 단어, 본문엔 커밋 SHA · 워크트리 경로 · 요점 포함.

### 4-3. peer 검증 흐름

worker 가 구현 + 커밋 후:
1. `commands.test` 직접 실행해 통과 확인 (선작성 spec 포함 회귀 없음)
2. 같은 턴에 `lint` · `sfx` 에게 병렬 `SendMessage` 로 검증 요청
3. 두 호출을 보낸 뒤 턴을 마친다. 회신은 다음 턴에 자동으로 들어온다
4. 🔴 must 이슈 있으면 수정 → 새 커밋 → 재검증
5. 🔴 모두 해소되면 `/pr` 스킬로 PR 생성

## 5. 표준 작업 흐름 (Lead 시점)

### 5-1. 작업 시작 — `/work <브랜치명>`

[`./.claude/skills/work/SKILL.md`](./.claude/skills/work/SKILL.md) 참고. 요약:

1. **연속성 확인** — `git worktree list`, `gh pr list --state all` 으로 같은 주제 PR/워크트리 있는지 확인
2. **워크트리 생성** — `origin/<stagingBranch>` (없으면 `<baseBranch>`) 기반. gitignored 파일은 `git.symlinkFromMain` 에 따라 심링크
3. **디자이너 게이트** — §5-4 조건 충족 시 `designer` 단발 호출 → UI 구현 커밋 → Lead 가 결과 검토 + 결정 로그 작성 → 종료
4. **TDD 게이트** — 작업이 사용자 행동 흐름을 바꾸면 `test-writer` 단발 호출 → 선작성 spec → Lead 가 spec 채택 판단 + 결정 로그 작성
5. **에이전트 세팅** — worker + lint + sfx 를 이름과 함께 병렬 spawn (`gates.peerReview = true` 일 때). 팀 생성 단계 없음
6. **작업 진행** — worker 가 구현 → 문서 동기화 판단 → peer 검증 → `/pr`
7. **리뷰 대기** — 에이전트는 완료 상태로 들어가지만 이름은 유효. reviewer 가 코멘트 달면 `SendMessage(to: "worker")` 로 재개해 응대
8. **머지 후 정리** — 사용자가 머지하면 `git worktree remove` + 브랜치 삭제. 별도 종료 절차 없음

### 5-2. TDD 선작성 강제 케이스

| 작업 성격 | test-writer 선호출 |
|---|---|
| 새 라우트 / 기존 라우트 동작 변경 | **필수** |
| 폼 제출 / 검증 | **필수** |
| 세션·인증·권한 게이트 | **필수** |
| 비즈니스 룰 (만료·정렬·매칭·atomic) | **필수** |
| 데이터 모델 변경 (마이그레이션 포함) | **필수** (통합 테스트로 검증) |
| 사용자 행동 흐름 변경 | **필수** (E2E 우선) |
| 순수 스타일 리뉴얼 | 선택 — 기존 smoke 회귀만 |
| 문구/카피, 정적 텍스트 변경 | 불필요 |
| 내부 리팩토링 (외부 동작 동일) | 불필요 |
| 마이그레이션 단독, infra/CI 설정 | 불필요 |
| 문서·주석 변경 | 불필요 (`/meta` 대상) |

생략 시 Lead 가 PR 본문에 "TDD 선작성 생략 — 사유: …" 한 줄로 명시.

### 5-3. test-writer 단발 호출 템플릿

```
Agent({
  subagent_type: "test-writer",
  description: "TDD 선작성 spec 작성",
  prompt: `
워크트리: <절대경로>
작업 주제: <한 줄 요약>
사용자 시나리오: <어떤 페이지에서 어떤 행동이 어떤 결과로>
인증 컨텍스트: <비로그인 / 인증된 사용자 / 관리자 등>
관련 데이터 모델: <어떤 엔티티/테이블을 어떻게>
기존 관련 spec: <경로 또는 '없음'>

요구사항:
- 모든 레이어 테스트 (E2E + 통합 + 단위 스켈레톤) 를 현재 코드 기준 빨갛게 실패하도록 작성
- project.json 의 commands 명령으로 새 파일만 지정해 실패 로그 확보
- 구현 코드 (paths.implementation 전체) 절대 수정 금지
- 보고 형식: spec 경로, 검증 포인트, 실패 로그 요약 (사용자 승인 요청 X — Lead 가 판단)
  `
})
```

`name` 없이 단발로 호출한다 (이름을 주지 않으면 재개 대상이 아닌 일회성 호출). 보고를 받으면 Lead 가 spec 을 검토하고 채택/수정/거절 판단을 내린 뒤 `<paths.decisions>/<slug>.md` 에 결정 로그를 추가.

### 5-4. 디자이너 게이트 (선택)

`gates.designer = true` 이고 작업 성격이 UI 비중이 큰 경우에만 Lead 가 `designer` 를 **단발로** 호출.

| 작업 성격 | designer 단발 호출 |
|---|---|
| 신규 페이지 레이아웃 첫 구현 | **필수** |
| 신규 모달 UX (큰 폼 / 다단계 위저드) | **필수** |
| 디자인 시스템 변경 (글로벌 토큰 / 글로벌 유틸 재설계) | **필수** |
| 단순 데이터 페칭 / CRUD 추가, 로직 변경 | 불필요 |
| 스타일 마이크로 조정 | 불필요 |
| 마이그레이션, API 라우트 신규 | 불필요 |

호출 흐름:
1. Lead 가 `Agent(subagent_type: "designer", ...)` 로 단발 호출 (`name` 없음 — 재개 대상 아님)
2. designer 가 UI 컴포넌트 구현 + 커밋 (`[ui]` prefix)
3. designer 종료 → Lead 가 결과 검토 + 디자인 톤 채택 결정을 `<paths.decisions>/<slug>.md` 에 기록
4. **이후 §5-1 의 4 단계 (TDD 게이트) 로 진입** — test-writer 가 designer 가 만든 UI 위에 테스트 선작성
5. 팀 spawn → worker 가 데이터 페칭 · 서버 액션 · 이벤트 핸들러 등 결합

designer 는 **UI 구현만** 한다. 데이터 로직 · 테스트는 worker / test-writer 가 후속 라운드에서 담당.

### 5-5. 문서 동기화 책임 매트릭스 (코드 변경 시)

| 문서 / 섹션 | 누가 갱신 | 갱신 시점 |
|---|---|---|
| `README.md` 전체 | **worker** | 같은 PR 안에서 |
| `CLAUDE.md` 사실 영역 (스택 / 디렉토리 / 데이터 모델 / 사이트맵 / 환경 변수) | **worker** | 코드 변경의 직접 결과면 |
| `CLAUDE.md` 정책 영역 (컨셉 / 디자인 / 코딩 컨벤션 / 워크플로우 / 결정 로그 운영 / 금지) | Lead (`/meta`) | 정책 변경 — 별도 PR |
| `AGENTS.md` 전체 | Lead (`/meta`) | 운영 규칙 그 자체 |
| `.claude/**` (에이전트·스킬·훅·settings) | Lead (`/meta`) | 운영 도구 |

원칙:
- 코드 변경의 **사실적 결과** (테이블·라우트·환경변수·스택·폴더 구조) 는 `/work` 안에서 worker 가 함께 갱신
- **운영 정책/규칙** (누가·어떻게 일하느냐, 어떤 게 금지냐, 어떤 톤이냐) 은 Lead 가 `/meta` 로 별도 PR

판단 한 줄: **"이 문서 갱신이 코드 diff 없이 단독으로 의미가 있는가?"** — 단독 의미 있으면 `/meta`, 코드와 짝이어야 의미 있으면 `/work` 안에서 worker 가.

### 5-6. 에이전트 spawn 시 worker 프롬프트 필수 포함

```
- 워크트리 경로: <절대경로>
- 브랜치/베이스: <featurePrefix><slug> ← origin/<stagingBranch 또는 baseBranch>
- 선작성된 spec: <e2e/...spec.ts, unit/...test.ts 목록>
  → 이 모든 테스트를 통과시켜라
  → spec 자체를 약화하지 마라 (필요 시 Lead 에 보고 — Lead 가 자율 판단해 spec 갱신)
- 테스트 파일 (paths.testGlobs) 절대 수정 금지. 읽기만 허용.
- 문서 동기화 의무 (peer 검증 직전 점검):
  · README.md — 사용자 가시 기능·스택·사이트맵·데이터 모델 변경 시 갱신
  · CLAUDE.md 사실 영역 — 코드 변경의 직접 결과면 같은 PR 에서 갱신
  · CLAUDE.md 정책 영역 / AGENTS.md 전체 는 절대 손대지 마라
- 구체적 요구사항·설계 결정·제약
- 작업 완료 시 commands.test 통과 확인 → lint·sfx 에 SendMessage 로 peer 검증 요청
```

## 6. 슬래시 스킬 목록 + 워크플로우 분기

### 6-1. 작업 성격에 따른 스킬 선택

작업 시작 시 Lead 가 자율 판단으로 둘 중 하나 선택:

| 작업 성격 | 스킬 | 이유 |
|---|---|---|
| 사용자 가시 기능·라우트·UI 동작 변경 (가드·인가·데이터 모델 영향 있음) | **`/work` 정식** | TDD 게이트 + 팀 (worker·lint·sfx) + peer 검증 |
| 데이터 모델·마이그레이션·서버 액션·DB 쿼리 | **`/work` 정식** | 통합 테스트 필요 |
| **경량 변경** — 순수 유틸 함수 추가 + 카피·스타일·variant 분기 등 시각 표현 위주 | **`/work` 경량** | 회귀 위험 좁음, TDD net 가치보다 절차 비용이 큼 |
| 문서 (README·CLAUDE·AGENTS·docs/**), 결정 로그 추가 | **`/meta`** | 사용자 가시 동작 영향 없음 |
| `.claude/` 에이전트·스킬·훅·settings·project.json 수정 | **`/meta`** | 운영 도구 변경 |
| `.gitignore`, dev 도구 설정, CI 워크플로우 | **`/meta`** | 인프라성 변경 |
| 의존성 추가/제거 자체만 (구현 결합 없음) | **`/meta`** | 결합되는 구현은 후속 `/work` |
| 긴급 수정 (`baseBranch` 베이스) | **`/hotfix`** | staging 우회 |

판단 기준 한 줄: **"이 변경이 사용자가 보는 화면·동작·데이터를 바꾸는가"** — 그러면 `/work` (정식 또는 경량), 아니면 `/meta`. 애매하면 정식 `/work` 가 안전.

**경량 경로 판정** — 다음을 **모두** 만족할 때만:
1. 새 라우트 / Server Action / 새 가드 분기 / 새 마이그레이션 **없음**
2. 인증·인가·세션 흐름 **무변경**
3. 데이터 모델 / 검증 스키마 **무변경**
4. 변경 표면: 순수 유틸 함수 추가 또는 카피·className·variant 등 시각 표현만
5. `commands.lint` + `commands.build` 통과만으로 충분히 회귀 차단 가능

위 5 개 중 하나라도 의심스러우면 **정식 경로**로 — TDD/peer 검증 net 가치가 비용 초과.

### 6-2. 전체 스킬

| 스킬 | 시점 | 용도 |
|---|---|---|
| [`/work`](./.claude/skills/work/SKILL.md) | 새 기능·코드 작업 시작 | 워크트리 + 디자이너·TDD 게이트 + 에이전트 세팅 |
| [`/meta`](./.claude/skills/meta/SKILL.md) | 메타 작업 (문서·설정·.claude) | 워크트리 + PR (게이트·팀·peer 생략, Lead 단독) |
| [`/hotfix`](./.claude/skills/hotfix/SKILL.md) | 긴급 수정 | `baseBranch` 베이스 워크트리 |
| [`/pr`](./.claude/skills/pr/SKILL.md) | 구현 완료 후 | PR 생성 (템플릿 적용) |
| [`/review`](./.claude/skills/review/SKILL.md) | PR 리뷰 시 | reviewer 가 GitHub 코멘트 |
| [`/sync`](./.claude/skills/sync/SKILL.md) | hotfix 머지 후 (stagingBranch 있는 프로젝트) | `baseBranch → stagingBranch` 동기화 PR |
| [`/deploy`](./.claude/skills/deploy/SKILL.md) | 배포 시 (stagingBranch 있는 프로젝트) | `stagingBranch → baseBranch` release PR |
| [`/followup`](./.claude/skills/followup/SKILL.md) | PR 상태 점검 | OPEN (코멘트/컨플릭트), MERGED (정리), CLOSED 분기 처리 |
| [`/prd-interview`](./.claude/skills/prd-interview/SKILL.md) | 신규 기능 기획 | brownfield 인터뷰 → `<paths.docs>/features/<slug>.md` |

## 7. PR 정책

- **base**: feature/meta → `stagingBranch` (있으면, 없으면 `baseBranch`), hotfix → `baseBranch`
- **제목**: `project.json` 의 `language` 따름, `pr.titleMaxChars` (기본 70) 이내
- **본문 템플릿**: `/pr` 스킬 참고
- PR 머지는 **사용자만** 수행
- 머지 정책: `pr.mergeStrategy` (기본 squash). rebase·force push 금지

## 8. 커뮤니케이션 규칙

- **Lead → worker** : `SendMessage(to: "worker")`. 코멘트 응대 시 우선순위 (🔴/🟡/🟢) 포함
- **worker → lint/sfx** : 같은 턴에 병렬 호출. 본문엔 커밋 SHA + 워크트리 경로 + 변경 파일 목록
- **lint/sfx → worker** : 보고 형식 그대로 (`## 린트/포매팅 검사 결과` 또는 `## 사이드이펙트 검사 결과` 헤더)
- **worker → Lead** : PR 생성 후 완료 보고, 리뷰 라운드 완료 시마다 보고
- **머지 후** : 별도 종료 메시지 없음. `shutdown_request` 를 먼저 보내지 않는다 (§4-0). 워크트리·브랜치 정리로 끝

## 9. 금지 사항

### 9-1. 공통 (모든 에이전트)

- 보호 브랜치 (`git.protectedBranches`) 에 직접 push (훅 차단)
- force push (`--force`, `-f`, `+refs/*`)
- `git reset --hard`, 보호 브랜치에서 `git merge` 직접 수행 (훅 차단)
- PR 머지 (사용자만)
- 머지된 브랜치에 추가 push
- 열린 PR 있는데 같은 주제로 새 PR 생성
- AWS MCP 호출 시 `--profile read-only` 누락 (훅 활성화 시 차단)
- **비자명한 결정을 내리고도 `<paths.decisions>/<slug>.md` 미작성**
- **사용자에게 결정 승인을 구해 작업이 멈춤** (§2 원칙: Lead 자율 판단)

### 9-2. Lead 한정

- 비자명한 결정의 결정 로그 누락
- 동일 결정을 매번 사용자에게 묻는 행위 (PRD / 이전 로그 / 기본값으로 자율 판단할 것)
- 사용자 가시 기능·스택·사이트맵·데이터 모델이 바뀌었는데 worker 에게 README.md / CLAUDE.md 사실 영역 동기화 요청 누락
- CLAUDE.md 정책 영역 / AGENTS.md / `.claude/**` 변경을 `/work` 안에 끼워 넣는 것 — 반드시 `/meta` 로 별도 PR

### 9-3. worker 한정

- 테스트 파일 (`paths.testGlobs`) 수정
- peer 검증 (lint+sfx) 생략하고 PR 생성 (`gates.peerReview = true` 일 때)
- nested `Agent` 호출로 lint/sfx 를 직접 spawn 시도 — Lead 가 이미 그 이름을 등록해 뒀다. 새로 spawn 하면 이름을 뺏어 이전 검증 맥락이 끊긴다. 반드시 `SendMessage` 로 깨울 것
- 리뷰 응대가 남았는데 `.claude` 밖에서 이름을 재사용하는 등 이름 선점을 깨뜨리는 행위
- 사용자 가시 기능·스택·사이트맵·데이터 모델 변경 시 README.md 동기화 누락
- CLAUDE.md 사실 영역 동기화 누락
- AGENTS.md 전체 또는 CLAUDE.md 정책 영역 임의 수정 — Lead 가 `/meta` 로 별도 처리
- `.claude/**` 임의 수정 — Lead `/meta` 영역

### 9-4. test-writer 한정

- 구현 파일 (`paths.implementation`) 수정
- 통과해버리는 spec 작성 (작성한 spec 은 현재 코드 기준 **반드시 빨갛게 실패**)
- 마이그레이션 작성·실행
- PR 생성·커밋 (Lead 나 worker 가 수행)
- "사용자 승인 요청" 형식의 보고 (Lead 에게 보고하고 Lead 가 판단)

### 9-5. lint / sfx 한정

- 코드 수정 (보고만)
- 기존 코드의 문제 보고 (이번 변경분만 검사)
- 이전 결과 재사용 (재검증 요청 시 최신 커밋 기준으로 다시)

### 9-6. reviewer 한정

- 코드 수정 (`Edit`/`Write` 도구 비활성)
- PR 승인/머지 (사용자가 직접)

## 10. 훅 (자동 검증)

`.claude/hooks/` 디렉토리. `PreToolUse` 로 동작.

- **`validate-git.sh`** — `git push` / `git merge` / `git reset --hard` / `gh pr merge` 검사. 보호 브랜치 목록은 `git.protectedBranches` 에서 동적으로 읽음
- **`validate-aws.sh`** — `hooks.aws.requireReadOnlyProfile = true` 일 때만 활성. AWS MCP 호출 시 `--profile read-only` 강제

훅이 실패하면 명령은 실행되지 않는다. 메시지를 보고 명령을 조정해야 한다 — **훅을 우회·비활성하지 말 것**.

## 11. 트러블슈팅

| 상황 | 대응 |
|---|---|
| worker 가 spec 을 약화하고 싶어함 | Lead 에 보고 → Lead 자율 판단 → 결정 로그 작성 → test-writer 단발 재호출로 spec 수정 (사용자에게 묻지 않음) |
| lint/sfx 가 회신 안 옴 | 같은 메시지를 재발송하지 말 것. 완료 상태는 정상이며 이름으로 보내면 재개된다. `SendMessage` 반환값의 `resumedAgentId` 로 실제 재개 여부를 확인하고, 이름 자체가 미등록이면 (spawn 실패) Lead 가 그때 spawn |
| 머지 컨플릭트 | `/followup <PR번호>` → A-0-conflict 분기. **merge commit 으로만 해소** (rebase 금지) |
| 워크트리에 settings 누락 | `git.symlinkFromMain` 에 정의된 파일을 다시 심링크 |
| 결정 근거가 PRD 에 없음 | Lead 가 PRD · 기존 로그 · 기본값을 종합해 자율 판단. 결정 로그에 "PRD 에 명시 없음, Lead 기본값 선택" 명시 |
| `.claude/project.json` 없음 | 하네스 설치가 필요. `~/.claude-harness/install.sh` 실행 후 재시도 |

## 12. 참고

- [`CLAUDE.md`](./CLAUDE.md) — 프로젝트 컨텍스트
- `.claude/project.json` — 프로젝트 설정 (브랜치·테스트 명령·경로 등)
- `<paths.decisions>/` — 결정 로그
- `.claude/agents/` — 각 에이전트 정의 (하네스 표준)
- `.claude/skills/` — 슬래시 스킬 정의 (하네스 표준)
- `.claude/hooks/` — 자동 검증 훅 (하네스 표준)
