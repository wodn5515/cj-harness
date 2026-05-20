# CLAUDE.md — <프로젝트명> 컨텍스트

> 이 파일은 Claude Code (및 AGENTS.md 호환 도구) 에 **프로젝트 컨텍스트**를 제공한다.
> 에이전트 운영 규칙 (누가, 어떤 순서로, 어떻게 협업하는지) 은 [`AGENTS.md`](./AGENTS.md) 와 [`.claude/project.json`](./.claude/project.json) 에 있다.
>
> 이 파일은 **사실 영역**과 **정책 영역**으로 나뉜다 — worker 가 어디까지 손댈 수 있는지 경계가 다르다.
> - **사실 영역** (§3 / §4 / §6 / §7 / §11) — worker 가 코드 변경의 직접 결과로 같은 PR 에서 갱신
> - **정책 영역** (§1 / §2 / §5 / §8 / §9 / §10 / §12 / §13 / §14) — Lead 가 `/meta` 흐름으로만 갱신 (worker 금지)

---

## 1. 프로젝트 한 줄 요약 (정책 영역)

**<프로젝트명>** — <한 줄 컨셉>

전체 스펙은 [`docs/PRD.md`](./docs/PRD.md) (있으면), 결정 로그는 [`docs/decisions/`](./docs/decisions/).

## 2. 핵심 가치 & 톤 (정책 영역)

- <가치 1>
- <가치 2>
- <비고: 사용자 / 운영자 / 외부 액터 등 어떤 청중이 있는지>

Non-goal (의도적 제외, V1):
- <뺀 것 1>
- <뺀 것 2>

## 3. 기술 스택 (사실 영역 — worker 가 같은 PR 에서 갱신)

| 항목 | 선택 |
|---|---|
| 프레임워크 | <Next.js 16 / Django 5 / FastAPI / ...> |
| 언어 | <TypeScript strict / Python 3.12 / ...> |
| DB | <PostgreSQL + Supabase / SQLite / ...> |
| 스타일링 | <Tailwind 4 / styled-components / ...> |
| 테스트 | <Vitest + RTL + Playwright / pytest / ...> |
| 배포 | <Vercel / Fly.io / AWS / ...> |

선택 근거는 [`docs/PRD.md`](./docs/PRD.md) 또는 결정 로그 참고.

## 4. 디렉토리 구조 (사실 영역)

```
<project-root>/
├── .claude/             # 하네스 (agents·skills·hooks + project.json)
├── docs/
│   ├── PRD.md
│   └── decisions/       # 결정 로그 NNN-<slug>.md
├── <src 또는 app/>      # 구현 코드
├── <components/>        # UI 컴포넌트 (있으면)
├── <lib/>               # 유틸·도메인 헬퍼 (있으면)
├── tests/               # 단위·통합 테스트
├── e2e/                 # E2E 테스트
├── CLAUDE.md
└── AGENTS.md
```

## 5. 디자인 시스템 (정책 영역)

> UI 가 없는 프로젝트면 이 섹션은 "해당 없음" 으로 두고 `.claude/project.json` 의 `gates.designer` 를 `false` 로.

### 디자인 토큰
<프로젝트의 글로벌 토큰 — Tailwind @theme / theme.ts / _variables.scss 등 정의 위치와 핵심 값>

### UI 프리미티브
<components/ui 위치 / 어떤 컴포넌트 셋이 있는지>

### 청중별 톤 분리 (있으면)
<운영자 vs 사용자, admin vs public 같은 톤 분리 규칙>

### 반응형 정책
- 모바일 우선 기준 폭: <360px / ...>
- 브레이크포인트: <Tailwind sm/md/lg 기본 / 커스텀>

## 6. 데이터 모델 (사실 영역)

| 테이블/엔티티 | 역할 | 핵심 규칙 |
|---|---|---|
| `<entity1>` | <설명> | <PK, UNIQUE, ON DELETE CASCADE 등> |
| `<entity2>` | <설명> | <...> |

마이그레이션 위치: `<supabase/migrations/ 또는 prisma/migrations/ 등>`.

## 7. 라우팅 / 사이트맵 (사실 영역)

| URL | 인증 | 비고 |
|---|---|---|
| `/` | <비로그인 / 인증 / 관리자> | <설명> |
| `/<route>` | <...> | <...> |

> API / CLI 프로젝트면 사이트맵 대신 "API 엔드포인트" 또는 "CLI 명령 목록" 으로 대체.

## 8. 코딩 컨벤션 (정책 영역)

- <TypeScript strict / Python type hint 의무 / ...>
- 네이밍 — <PascalCase / snake_case / camelCase 사용처>
- 주석 언어 — <한국어 / English>
- 커밋 메시지 — `.claude/project.json` 의 `language` 따름. 한국어 템플릿:
  ```
  [타입] 제목

  - 변경사항 1
  - 변경사항 2
  ```
  타입: `feat` / `fix` / `hotfix` / `refactor` / `infra` / `docs` / `chore` / `ui` / `test`

## 9. 테스트 정책 (정책 영역)

**테스트 코드와 구현 코드는 서로 다른 에이전트가 작성한다** — 자세한 흐름은 [`AGENTS.md`](./AGENTS.md) §3 / `.claude/project.json` 의 `paths.testGlobs`. 여기서는 원칙만:

- **`test-writer`** 가 모든 테스트 파일 (`paths.testGlobs`) 작성·수정
- **`worker`** 는 구현 파일만 다룬다 — 테스트는 **읽기만**, 수정 금지
- 테스트는 **선작성 → 빨갛게 실패 확인 → Lead 자율 채택 → 구현으로 초록 전환** 순서

테스트 도구 매핑은 `.claude/project.json` 의 `commands` 와 `paths.tests` 에서 확인.

## 10. 워크플로우 분기 (정책 영역)

| 변경 대상 | 스킬 | 흐름 |
|---|---|---|
| **위험 영역**: 가드 / 인가 / 마이그레이션 / 새 라우트 / 비즈니스 룰 / 데이터 모델 | **`/work` 정식** | 워크트리 → 디자이너·TDD 게이트 → 팀 spawn → peer 검증 → PR |
| **경량 영역**: 순수 유틸 함수 + 사용자 가시 카피·스타일·variant 분기 등 시각 변경 위주 | **`/work` 경량** | 워크트리 → Lead 단독 → lint + build → PR |
| 메타 (docs, CLAUDE.md 정책 영역, .claude/**, .gitignore, CI) | **`/meta`** | 워크트리 → Lead 단독 → PR |
| 긴급 수정 (`baseBranch` 베이스) | **`/hotfix`** | staging 우회 |
| 배포 PR (stagingBranch 있는 경우) | **`/deploy`** | release PR 자동 작성 |

자세한 분기 표는 [`AGENTS.md`](./AGENTS.md) §6.

## 11. 환경 변수 (사실 영역)

```env
# <설명>
<ENV_NAME>=<예시값>

# <설명>
<ANOTHER_ENV>=<예시값>
```

## 12. 결정 로그 운영 (정책 영역)

작업 중 발생하는 모든 비자명한 판단은 **Lead 에이전트가 자율적으로 결정**하고 그 즉시 `<paths.decisions>/<NNN>-<slug>.md` 로 기록한다. 사용자에게 매번 물어 승인을 받는 흐름이 아니다.

자세한 형식은 [`AGENTS.md`](./AGENTS.md) §2.

## 13. 금지 사항 (정책 영역, 요약)

- 보호 브랜치 (`.claude/project.json` 의 `git.protectedBranches`) 직접 push (훅 차단)
- force push, `git reset --hard` 직접 수행 (훅 차단)
- 보호 브랜치에서 `git merge` 직접 수행 (훅 차단)
- PR 머지 (사용자만 수행)
- 머지된 브랜치에 추가 push
- 열린 PR 이 있는데 같은 주제로 새 PR 생성
- worker 가 테스트 파일 (`paths.testGlobs`) 수정
- test-writer 가 구현 파일 (`paths.implementation`) 수정
- peer 검증 생략하고 PR 생성 (`gates.peerReview = true` 일 때)
- **비자명한 결정을 내리고도 결정 로그 미작성**
- **사용자 가시 기능·스택·사이트맵·데이터 모델이 바뀌었는데 같은 PR 에서 README.md / CLAUDE.md 사실 영역 미동기화**
- **worker 가 이 파일의 정책 영역 또는 `AGENTS.md` 를 임의 수정** — Lead 가 `/meta` 로 별도 PR

## 14. 참고 (정책 영역)

- [`README.md`](./README.md) — 서비스 소개 + 빠른 시작
- [`docs/PRD.md`](./docs/PRD.md) — 제품 스펙 (있으면)
- [`docs/decisions/`](./docs/decisions/) — 결정 로그
- [`AGENTS.md`](./AGENTS.md) — 에이전트 운영 규칙
- [`.claude/project.json`](./.claude/project.json) — 프로젝트 설정 (브랜치·테스트 명령·경로 등)
- [`.claude/skills/`](./.claude/skills/) — 슬래시 스킬 정의
- [`.claude/agents/`](./.claude/agents/) — 에이전트 정의
