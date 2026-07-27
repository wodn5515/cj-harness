# 에이전트 팀 API 변경 대응 — 이름 기반 재개 모델로 전환

- 날짜: 2026-07-27
- 결정자: Lead (자율 판단)
- 범위: `payload/**` (AGENTS.md, skills/work, skills/followup, agents/*), `install.sh`, `README.md`, `INSTALL-AI.md`

## 배경

하네스 페이로드는 `TeamCreate` → 팀원 spawn → idle 대기 → `shutdown_request` → `TeamDelete` 라는 구버전 에이전트 팀 API 를 전제로 작성돼 있었다. 실제 프로젝트(taktik)에서 `/work` 를 실행하다 막히는 것이 발견돼 조사했다.

## 실측 (Claude Code 2.1.220)

이 저장소에서 직접 확인한 사실만 적는다. **어느 버전부터 바뀐 동작인지는 특정하지 않는다.**

1. `TeamCreate` / `TeamDelete` 툴이 **존재하지 않는다.** 툴 검색 결과 팀 관련으로 노출되는 것은 `TaskStop` 뿐.
2. `Agent({subagent_type, name: "probe", ...})` 로 spawn → `SendMessage({to: "probe"})` 로 **완료된 에이전트의 transcript 가 재개**된다. 반환 메시지: `Agent "probe" had no active task; resumed from transcript in the background`.
3. 이름 해석은 실제 등록 기반이다. `alpha` / `beta` 두 에이전트를 띄우고 `to: "beta"` 로 보냈을 때 `resumedAgentId` 가 beta 의 agentId 와 일치했다 (단일 에이전트 fallback 매칭이 아님).
4. `SendMessage` 툴 설명에 "names keep working after an agent completes (a send resumes it from its transcript)" 로 명시돼 있다.
5. `Agent` 는 기본 백그라운드 실행. `shutdown_request` 계열은 legacy 로 분류되고 originate 금지로 문서화돼 있다.
6. **환경 플래그 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` 는 위 동작의 전제가 아니다.** 위 1~3 은 이 저장소 세션에서 플래그가 **미설정**인 상태로 확인했다.
   - 다만 플래그가 설정된 세션에서는 `Agent` 툴 스키마에 `name` 과 `team_name`(deprecated 표기)이 노출되고, 미설정 세션에서는 스키마에 나타나지 않았다 (동작은 함). 즉 플래그는 **기능 스위치가 아니라 노출 스위치**로 보인다 — 이건 두 세션 관측의 비교이므로 추정으로 표기한다.

## 결정

### 1. lint·sfx 선(先) spawn 구조는 유지한다. 단 목적을 "대기" 에서 **"이름 선점"** 으로 재정의

새 모델에서 할 일 없는 에이전트는 idle 로 머물지 않고 완료된다. 따라서 "대기 상태로 세워둔다" 는 서술은 사실과 다르다.

검토한 대안:
- **(A) 선 spawn 폐지, worker 가 검증 시점에 직접 spawn** — worker 의 nested `Agent` 호출 금지 규칙(AGENTS.md §9-3)과 충돌하고, 라운드마다 새 에이전트가 생겨 재검증 맥락이 누적되지 않는다.
- **(B) 구조 유지 + 문서만 정정** ← **채택**

채택 사유: worker 가 `SendMessage(to: "lint")` 로 깨우려면 그 이름이 **미리 등록돼 있어야** 한다. 선 spawn 은 이 등록을 위한 것이고, 그 외의 목적은 없다. 이렇게 두면 peer 검증 흐름과 권한 경계(worker 는 spawn 하지 않는다)가 그대로 유지되며, 실측 2·3 에 따라 재개도 정상 동작한다.

부수 규칙: **한 작업 안에서 `worker`/`lint`/`sfx` 이름을 재사용하지 않는다.** 같은 이름은 최신 spawn 이 이기므로, 재사용하면 이전 맥락(리뷰 응대 대상)에 도달할 수 없게 된다. AGENTS.md §9-3 의 nested spawn 금지 근거도 "peer 가 살아있음" → "이름을 뺏으면 맥락이 끊김" 으로 교체했다.

### 2. 팀 종료 절차는 대체하지 않고 **삭제**한다

`TeamDelete` 는 존재하지 않고 `shutdown_request` 는 originate 금지다. 그리고 애초에 거둬들일 대상이 없다 — 에이전트는 이미 완료 상태다.

따라서 `/work` 3-6 과 `/followup` B-1 에서 종료 시퀀스를 걷어내고, 머지 후 정리는 **워크트리·브랜치 정리만** 남겼다. `TaskStop({task_id: "<이름>"})` 은 **아직 실행 중인** 백그라운드 에이전트가 남은 예외 상황의 수단으로만 남긴다 (정규 절차 아님).

### 3. 환경 플래그는 "필수" 에서 "선택(구버전 호환용)" 으로 강등

실측 6 에 따라 없어도 동작한다. 다만 켜서 해로울 것이 없고 구버전 호환 여지가 있어 **제거하지 않고 강등**만 했다. `install.sh` / `README.md` / `INSTALL-AI.md` 세 곳의 문구를 "필수 스텝" → "(선택)" 으로 바꿨다.

### 4. 구버전 절차는 각주로 남기지 않는다

페이로드는 새로 설치되는 프로젝트의 에이전트가 **그대로 따라 실행하는 지시문**이다. 폐기된 `TeamCreate` 절차를 각주로 남기면 에이전트가 분기 판단을 시도할 여지가 생긴다. 이력은 이 결정 로그와 git 히스토리에 남기고, 페이로드는 새 API 기준으로만 서술한다.

## 이미 설치된 프로젝트 반영

`.claude/skills/`·`agents/`·`hooks/` 는 표준 업데이트 경로(README "업데이트" 섹션)로 반영된다. 그러나 **`AGENTS.md` 는 업데이트가 덮어쓰지 않는 보존 대상**이므로, 이번 변경의 §4 (협업 모드 동작) · §5-1 · §8 · §9-3 · §11 은 각 프로젝트에서 **수동 백포트**해야 한다. README 업데이트 섹션에 이 경고를 추가했다. taktik 이 여기에 해당한다.
