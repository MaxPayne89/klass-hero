# Changelog

All notable changes to the Klass Hero project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.59.2](https://github.com/MaxPayne89/klass-hero/compare/v0.59.1...v0.59.2) (2026-07-19)


### Bug Fixes

* single-source PubSub topics; fix dead attendance subscriptions ([#1108](https://github.com/MaxPayne89/klass-hero/issues/1108)) ([#1120](https://github.com/MaxPayne89/klass-hero/issues/1120)) ([e55af2c](https://github.com/MaxPayne89/klass-hero/commit/e55af2c111f42be46117b72d940677e8ee7c2800))


### Code Refactoring

* delete orphaned session-note integration events ([#1107](https://github.com/MaxPayne89/klass-hero/issues/1107)) ([#1119](https://github.com/MaxPayne89/klass-hero/issues/1119)) ([87f7682](https://github.com/MaxPayne89/klass-hero/commit/87f7682c8b4bc9c26755006180f6d0fe9c363e7c))

## [0.59.1](https://github.com/MaxPayne89/klass-hero/compare/v0.59.0...v0.59.1) (2026-07-18)


### Performance Improvements

* cut fixed per-request cost on dashboard + admin; fix dead sessions tile ([#1112](https://github.com/MaxPayne89/klass-hero/issues/1112)) ([2e4a043](https://github.com/MaxPayne89/klass-hero/commit/2e4a04313dd868301f1549c5e30d3ba2dbf4531c))

## [0.59.0](https://github.com/MaxPayne89/klass-hero/compare/v0.58.1...v0.59.0) (2026-07-18)


### Features

* default login method to password instead of magic link ([#1110](https://github.com/MaxPayne89/klass-hero/issues/1110)) ([8fb76ef](https://github.com/MaxPayne89/klass-hero/commit/8fb76ef52eefd5aa9ccfc00a02c2fc3e69564f57))


### Code Refactoring

* rename BehavioralNote to SessionNote ([#1106](https://github.com/MaxPayne89/klass-hero/issues/1106)) ([f1147d6](https://github.com/MaxPayne89/klass-hero/commit/f1147d68a59c2fe27678bef6ac7b4984b03f0c13)), closes [#924](https://github.com/MaxPayne89/klass-hero/issues/924)

## [0.58.1](https://github.com/MaxPayne89/klass-hero/compare/v0.58.0...v0.58.1) (2026-07-17)


### Performance Improvements

* consolidate provider pending-enrollments into one join ([#1103](https://github.com/MaxPayne89/klass-hero/issues/1103)) ([5213849](https://github.com/MaxPayne89/klass-hero/commit/52138490b985ec347c4ec79df899e67853ef5290))


### Code Refactoring

* extract emit_domain_event LiveView test helper ([#1104](https://github.com/MaxPayne89/klass-hero/issues/1104)) ([58477ce](https://github.com/MaxPayne89/klass-hero/commit/58477ce7117ea4c8a0287fb69dce7c99f4a30409)), closes [#869](https://github.com/MaxPayne89/klass-hero/issues/869)

## [0.58.0](https://github.com/MaxPayne89/klass-hero/compare/v0.57.0...v0.58.0) (2026-07-15)


### Features

* enforce one submission surface per vetting step in the domain ([#1099](https://github.com/MaxPayne89/klass-hero/issues/1099)) ([ca80225](https://github.com/MaxPayne89/klass-hero/commit/ca802251aaaa5180ff95519a409da3a9c8223410)), closes [#1091](https://github.com/MaxPayne89/klass-hero/issues/1091)

## [0.57.0](https://github.com/MaxPayne89/klass-hero/compare/v0.56.1...v0.57.0) (2026-07-15)


### Features

* add prod-watch proactive prod-issue loop ([#1092](https://github.com/MaxPayne89/klass-hero/issues/1092)) ([d06d238](https://github.com/MaxPayne89/klass-hero/commit/d06d238f565e1375081dafd279ee9c9f23f02086))
* capture all traces (sampling 1.0) and add Fly host-metrics runbook ([#1090](https://github.com/MaxPayne89/klass-hero/issues/1090)) ([667eb98](https://github.com/MaxPayne89/klass-hero/commit/667eb9886af60efcc3981f7d525854e9f81f1270))
* grant prod-watch a least-privilege headless allowlist ([#1094](https://github.com/MaxPayne89/klass-hero/issues/1094)) ([aa7c4e0](https://github.com/MaxPayne89/klass-hero/commit/aa7c4e0182a67d2e8639c36f6695fbff5da4365d))


### Bug Fixes

* feed prod-watch prompt via stdin so --allowedTools doesn't eat it ([#1095](https://github.com/MaxPayne89/klass-hero/issues/1095)) ([ad03b3a](https://github.com/MaxPayne89/klass-hero/commit/ad03b3aa8b5185d063bc947d39e60613f21401d5))
* pin prod-watch scheduler to a self-updating worktree ([#1093](https://github.com/MaxPayne89/klass-hero/issues/1093)) ([505c5d0](https://github.com/MaxPayne89/klass-hero/commit/505c5d0e2cc8827482e8b1ba1318927cceb509dd))


### Code Refactoring

* cut vetting save_case/1 to N+1 writes, 0 reads ([#1068](https://github.com/MaxPayne89/klass-hero/issues/1068)) ([#1088](https://github.com/MaxPayne89/klass-hero/issues/1088)) ([ffb0ca7](https://github.com/MaxPayne89/klass-hero/commit/ffb0ca77f736bb7e62f351a29d23554766a07bfb))
* deduplicate provider vetting step list ([#1079](https://github.com/MaxPayne89/klass-hero/issues/1079)) ([#1087](https://github.com/MaxPayne89/klass-hero/issues/1087)) ([972270d](https://github.com/MaxPayne89/klass-hero/commit/972270dec32f409346099b8d2be66856e8bcfd0a))
* in-memory dedup of confirmed enrollment in provider dashboard ([#1081](https://github.com/MaxPayne89/klass-hero/issues/1081)) ([59b33a3](https://github.com/MaxPayne89/klass-hero/commit/59b33a34c5876645a3854f9bc82fa6efda216e99)), closes [#871](https://github.com/MaxPayne89/klass-hero/issues/871)
* prod-watch wrapper owns state I/O, agent is pure compute ([#1096](https://github.com/MaxPayne89/klass-hero/issues/1096)) ([7c7356b](https://github.com/MaxPayne89/klass-hero/commit/7c7356b564a8e709a6cde40b6a52dfa420670134))

## [0.56.1](https://github.com/MaxPayne89/klass-hero/compare/v0.56.0...v0.56.1) (2026-07-11)


### Bug Fixes

* update video screening description on About and Trust & Safety pages ([#1076](https://github.com/MaxPayne89/klass-hero/issues/1076)) ([02dcc47](https://github.com/MaxPayne89/klass-hero/commit/02dcc4760ec79d1b8ccec32120abde0d57a432a9)), closes [#557](https://github.com/MaxPayne89/klass-hero/issues/557)


### Code Refactoring

* route TeamLive pay rate through Provider facade ([#1060](https://github.com/MaxPayne89/klass-hero/issues/1060)) ([#1078](https://github.com/MaxPayne89/klass-hero/issues/1078)) ([41b423b](https://github.com/MaxPayne89/klass-hero/commit/41b423b776c3841d9c5e82cd8e1d0449db4d71ab))

## [0.56.0](https://github.com/MaxPayne89/klass-hero/compare/v0.55.3...v0.56.0) (2026-07-10)


### Features

* provider vetting engine (individual track) ([#1064](https://github.com/MaxPayne89/klass-hero/issues/1064)) ([24543e6](https://github.com/MaxPayne89/klass-hero/commit/24543e675ec94f5cebed8961de0229f2eba974ab))


### Bug Fixes

* make parent/provider profile creation idempotent inside critical event transaction ([#1070](https://github.com/MaxPayne89/klass-hero/issues/1070)) ([c41437c](https://github.com/MaxPayne89/klass-hero/commit/c41437c8dc8815cab9db2d74471d857e7dbb27ee)), closes [#1065](https://github.com/MaxPayne89/klass-hero/issues/1065)

## [0.55.3](https://github.com/MaxPayne89/klass-hero/compare/v0.55.2...v0.55.3) (2026-07-10)


### Code Refactoring

* lead instructor single source of truth on program_staff_assignments ([#840](https://github.com/MaxPayne89/klass-hero/issues/840)) ([#1063](https://github.com/MaxPayne89/klass-hero/issues/1063)) ([ccaf9a7](https://github.com/MaxPayne89/klass-hero/commit/ccaf9a752a6b433b3aa297e22bd4a71b58738989))
* unify Messaging event dispatch on EventDispatchHelper ([#1061](https://github.com/MaxPayne89/klass-hero/issues/1061)) ([ced7dfc](https://github.com/MaxPayne89/klass-hero/commit/ced7dfc2e98f887b47b54f3c4469927168b1ee7b)), closes [#849](https://github.com/MaxPayne89/klass-hero/issues/849)

## [0.55.2](https://github.com/MaxPayne89/klass-hero/compare/v0.55.1...v0.55.2) (2026-07-08)


### Bug Fixes

* add provider-ownership (IDOR) guards to dashboard mutations ([#1059](https://github.com/MaxPayne89/klass-hero/issues/1059)) ([590f5fd](https://github.com/MaxPayne89/klass-hero/commit/590f5fd42329a10b07bab7c47acf0d74e4591c0e)), closes [#1048](https://github.com/MaxPayne89/klass-hero/issues/1048)
* drop Enrollment schema's belongs_to into Family ([#1052](https://github.com/MaxPayne89/klass-hero/issues/1052)) ([#1057](https://github.com/MaxPayne89/klass-hero/issues/1057)) ([8182e02](https://github.com/MaxPayne89/klass-hero/commit/8182e02f785b19c6eed14de7f5847dbd8470cf0f))
* replace stale provider tier pricing in home FAQ ([#1055](https://github.com/MaxPayne89/klass-hero/issues/1055)) ([#1056](https://github.com/MaxPayne89/klass-hero/issues/1056)) ([6b938d0](https://github.com/MaxPayne89/klass-hero/commit/6b938d01ec0ff90acdc6bbf69d7c11da392fd33b))

## [0.55.1](https://github.com/MaxPayne89/klass-hero/compare/v0.55.0...v0.55.1) (2026-07-08)


### Bug Fixes

* repoint seeds.exs schema aliases after context flattens ([#1045](https://github.com/MaxPayne89/klass-hero/issues/1045)) ([#1050](https://github.com/MaxPayne89/klass-hero/issues/1050)) ([43a1179](https://github.com/MaxPayne89/klass-hero/commit/43a1179657af09a0ec5be8afe9c2e4f28733a1f1))


### Code Refactoring

* route Enrollment parent reads through the Family ACL ([#1051](https://github.com/MaxPayne89/klass-hero/issues/1051)) ([046f4e0](https://github.com/MaxPayne89/klass-hero/commit/046f4e0a38dbf17cfb8454d3df48be15378db645)), closes [#1046](https://github.com/MaxPayne89/klass-hero/issues/1046)

## [0.55.0](https://github.com/MaxPayne89/klass-hero/compare/v0.54.7...v0.55.0) (2026-07-07)


### Features

* remove parent subscription tiers and the Entitlements service ([#1044](https://github.com/MaxPayne89/klass-hero/issues/1044)) ([8a6d757](https://github.com/MaxPayne89/klass-hero/commit/8a6d757f3ec1bf14d9feb471d0260eb52cc37df1)), closes [#925](https://github.com/MaxPayne89/klass-hero/issues/925)


### Code Refactoring

* reconcile drifted gettext catalogs and add sync gate ([#1043](https://github.com/MaxPayne89/klass-hero/issues/1043)) ([6113a49](https://github.com/MaxPayne89/klass-hero/commit/6113a4927bf03a44becbaa34af00a1f50319c431)), closes [#876](https://github.com/MaxPayne89/klass-hero/issues/876)
* split ProviderDashboardLive into four sub-LiveViews ([#904](https://github.com/MaxPayne89/klass-hero/issues/904)) ([#1047](https://github.com/MaxPayne89/klass-hero/issues/1047)) ([69025c0](https://github.com/MaxPayne89/klass-hero/commit/69025c0b8910b9899b9d140f48fc1df7f37ebf06))

## [0.54.7](https://github.com/MaxPayne89/klass-hero/compare/v0.54.6...v0.54.7) (2026-07-07)


### Bug Fixes

* isolate tracing tests from cross-test span leakage ([#1042](https://github.com/MaxPayne89/klass-hero/issues/1042)) ([e27583c](https://github.com/MaxPayne89/klass-hero/commit/e27583c1f304fadb07f2f885f7e205be46bd525b)), closes [#1035](https://github.com/MaxPayne89/klass-hero/issues/1035)


### Code Refactoring

* replace raw programs query in conversation summaries with facade read ([#1040](https://github.com/MaxPayne89/klass-hero/issues/1040)) ([f0b51b1](https://github.com/MaxPayne89/klass-hero/commit/f0b51b19dbfd7ccc820705e92ab9d9fafc475fed)), closes [#1027](https://github.com/MaxPayne89/klass-hero/issues/1027)

## [0.54.6](https://github.com/MaxPayne89/klass-hero/compare/v0.54.5...v0.54.6) (2026-07-06)


### Bug Fixes

* guard critical-event payloads to JSON scalars ([#1010](https://github.com/MaxPayne89/klass-hero/issues/1010)) ([#1038](https://github.com/MaxPayne89/klass-hero/issues/1038)) ([dd2fae1](https://github.com/MaxPayne89/klass-hero/commit/dd2fae1020426b81bac85c6305f485451a2b3fad))
* tolerate out-of-enum verification document_type ([#1026](https://github.com/MaxPayne89/klass-hero/issues/1026)) ([#1039](https://github.com/MaxPayne89/klass-hero/issues/1039)) ([03d0149](https://github.com/MaxPayne89/klass-hero/commit/03d0149af640dd7be65e2926b1a257cb757d560f))


### Code Refactoring

* flatten Enrollment.ParticipantPolicyForm to context root ([#1020](https://github.com/MaxPayne89/klass-hero/issues/1020)) ([#1037](https://github.com/MaxPayne89/klass-hero/issues/1037)) ([833543a](https://github.com/MaxPayne89/klass-hero/commit/833543affb792560e7f2e7daf26e1ef7c516402c))
* flatten Family.ProcessInviteClaim to context root ([#1019](https://github.com/MaxPayne89/klass-hero/issues/1019)) ([#1034](https://github.com/MaxPayne89/klass-hero/issues/1034)) ([66f6f41](https://github.com/MaxPayne89/klass-hero/commit/66f6f4116e5562335c4dc4fd4ca97e8061c8c036))

## [0.54.5](https://github.com/MaxPayne89/klass-hero/compare/v0.54.4...v0.54.5) (2026-07-06)


### Code Refactoring

* route Participation session reads through ProgramCatalog/Provider facades ([#1032](https://github.com/MaxPayne89/klass-hero/issues/1032)) ([d3efb54](https://github.com/MaxPayne89/klass-hero/commit/d3efb54452f8f9f5faf8c4de73574355af42f48e)), closes [#998](https://github.com/MaxPayne89/klass-hero/issues/998)

## [0.54.4](https://github.com/MaxPayne89/klass-hero/compare/v0.54.3...v0.54.4) (2026-07-05)


### Code Refactoring

* flatten Shared context, preserve env-swapped adapter seams ([#1014](https://github.com/MaxPayne89/klass-hero/issues/1014)) ([#1031](https://github.com/MaxPayne89/klass-hero/issues/1031)) ([7c030a5](https://github.com/MaxPayne89/klass-hero/commit/7c030a51d88089c259f0e5b6e58e04d703045b41))
* read user display names via Accounts facade, drop Messaging ACL ([#1029](https://github.com/MaxPayne89/klass-hero/issues/1029)) ([319db5c](https://github.com/MaxPayne89/klass-hero/commit/319db5c486da3f370f8508829b24da2f94c78bcd))

## [0.54.3](https://github.com/MaxPayne89/klass-hero/compare/v0.54.2...v0.54.3) (2026-07-05)


### Bug Fixes

* demote provider topbar name from h1 to span for single page heading ([#1025](https://github.com/MaxPayne89/klass-hero/issues/1025)) ([1706f25](https://github.com/MaxPayne89/klass-hero/commit/1706f2520ae8dd86cb8fdb38269d87ab0a1ea600)), closes [#984](https://github.com/MaxPayne89/klass-hero/issues/984)


### Code Refactoring

* flatten Messaging application layer to conventional Phoenix ([#1022](https://github.com/MaxPayne89/klass-hero/issues/1022)) ([b85f0ed](https://github.com/MaxPayne89/klass-hero/commit/b85f0ed12f8370518b42fb12b6fb9864879020bf)), closes [#1021](https://github.com/MaxPayne89/klass-hero/issues/1021)
* flatten participation test tree to context root ([#1017](https://github.com/MaxPayne89/klass-hero/issues/1017)) ([2188f58](https://github.com/MaxPayne89/klass-hero/commit/2188f58e8a7d5dc1429e359f061074286dcf919e))
* migrate provider status pills onto Theme.status_badge/1 ([#1024](https://github.com/MaxPayne89/klass-hero/issues/1024)) ([f57c1a0](https://github.com/MaxPayne89/klass-hero/commit/f57c1a0aa22902b0f86d555483cbde9d0f56652e)), closes [#983](https://github.com/MaxPayne89/klass-hero/issues/983)
* mirror provider test tree to post-[#1003](https://github.com/MaxPayne89/klass-hero/issues/1003) sub-domain layout ([#1016](https://github.com/MaxPayne89/klass-hero/issues/1016)) ([36388d7](https://github.com/MaxPayne89/klass-hero/commit/36388d7b1082a599e836a0dd0e5033e2eddf9c8d)), closes [#1013](https://github.com/MaxPayne89/klass-hero/issues/1013)

## [0.54.2](https://github.com/MaxPayne89/klass-hero/compare/v0.54.1...v0.54.2) (2026-07-04)


### Bug Fixes

* durable Oban delivery for provider staff-assignment events ([#1011](https://github.com/MaxPayne89/klass-hero/issues/1011)) ([e0689a0](https://github.com/MaxPayne89/klass-hero/commit/e0689a0c3f4e0ebe9978b37b32c508b43dcb0775)), closes [#1004](https://github.com/MaxPayne89/klass-hero/issues/1004)


### Code Refactoring

* delete Enrollment→Accounts UserAccountResolver ACL ([#1015](https://github.com/MaxPayne89/klass-hero/issues/1015)) ([7130fcc](https://github.com/MaxPayne89/klass-hero/commit/7130fccec9e6a26bc6f5aa4d27e56c56e77b8fc9)), closes [#990](https://github.com/MaxPayne89/klass-hero/issues/990)
* remove dead RepositoryHelpers mapper-variant functions ([#1008](https://github.com/MaxPayne89/klass-hero/issues/1008)) ([bdaacf3](https://github.com/MaxPayne89/klass-hero/commit/bdaacf3b23fdf148d63e435dbbf05b178f8550de)), closes [#1005](https://github.com/MaxPayne89/klass-hero/issues/1005)
* split KlassHero.Provider context module by sub-domain ([#1012](https://github.com/MaxPayne89/klass-hero/issues/1012)) ([03f2c79](https://github.com/MaxPayne89/klass-hero/commit/03f2c796e8e9f2489bd30763e3f31053d901bf5c))

## [0.54.1](https://github.com/MaxPayne89/klass-hero/compare/v0.54.0...v0.54.1) (2026-07-03)


### Code Refactoring

* flatten Accounts to conventional Phoenix; drop ports/adapters/mappers ([#993](https://github.com/MaxPayne89/klass-hero/issues/993)) ([d727ac9](https://github.com/MaxPayne89/klass-hero/commit/d727ac9162983dcd52af6ef00518fd6d6bf892b4))
* flatten Enrollment to conventional Phoenix ([#999](https://github.com/MaxPayne89/klass-hero/issues/999)) ([74355f0](https://github.com/MaxPayne89/klass-hero/commit/74355f030dd81ce46438400ad130642799d1365c))
* flatten Family to conventional Phoenix; remove boundary library ([#986](https://github.com/MaxPayne89/klass-hero/issues/986)) ([6def5fc](https://github.com/MaxPayne89/klass-hero/commit/6def5fcbb8b4d535a1fe5631d1ebc68452ac8e8c))
* flatten Messaging bounded context to conventional Phoenix ([#1001](https://github.com/MaxPayne89/klass-hero/issues/1001)) ([a80b0c9](https://github.com/MaxPayne89/klass-hero/commit/a80b0c9887b5105b0c20e208838604970afcaabe))
* flatten Participation to conventional Phoenix ([#997](https://github.com/MaxPayne89/klass-hero/issues/997)) ([e0f4a18](https://github.com/MaxPayne89/klass-hero/commit/e0f4a1860a9722c1fcf2afee75ab1066d1e24d75))
* flatten Program Catalog to conventional Phoenix; keep CQRS read model ([#995](https://github.com/MaxPayne89/klass-hero/issues/995)) ([1c5d9b4](https://github.com/MaxPayne89/klass-hero/commit/1c5d9b43b3f5a808b85896895b50cc208cd799d6))
* flatten Provider to conventional Phoenix (7th & final context) ([#1002](https://github.com/MaxPayne89/klass-hero/issues/1002)) ([8004790](https://github.com/MaxPayne89/klass-hero/commit/800479030c8c8a62ccc49ca7e52d5f78098baf0b))

## [0.54.0](https://github.com/MaxPayne89/klass-hero/compare/v0.53.1...v0.54.0) (2026-06-14)


### Features

* Interaction observability envelope for driven-adapter I/O ([#981](https://github.com/MaxPayne89/klass-hero/issues/981)) ([e7cfe25](https://github.com/MaxPayne89/klass-hero/commit/e7cfe25504e7627caca53f16d9bf3cdd3197558f))

## [0.53.1](https://github.com/MaxPayne89/klass-hero/compare/v0.53.0...v0.53.1) (2026-06-12)


### Bug Fixes

* seed UI test staff user as staff-only ([#972](https://github.com/MaxPayne89/klass-hero/issues/972) follow-up) ([#975](https://github.com/MaxPayne89/klass-hero/issues/975)) ([ef1ec05](https://github.com/MaxPayne89/klass-hero/commit/ef1ec054ee705dbbb41441df62652158574a4f84))

## [0.53.0](https://github.com/MaxPayne89/klass-hero/compare/v0.52.0...v0.53.0) (2026-06-12)


### Features

* separate Provider from Staff Member as independent personas (ADR-0005) ([#973](https://github.com/MaxPayne89/klass-hero/issues/973)) ([ecdae28](https://github.com/MaxPayne89/klass-hero/commit/ecdae28c27ab63e96f71495c2d3e3aa4e2bec1b4))

## [0.52.0](https://github.com/MaxPayne89/klass-hero/compare/v0.51.4...v0.52.0) (2026-06-07)


### Features

* remove provider subscription tiers ([#961](https://github.com/MaxPayne89/klass-hero/issues/961)) ([aa71f58](https://github.com/MaxPayne89/klass-hero/commit/aa71f589858c1a888458118f9b7d4d319af4c749))

## [0.51.4](https://github.com/MaxPayne89/klass-hero/compare/v0.51.3...v0.51.4) (2026-06-02)


### Code Refactoring

* consolidate duplicate code into shared seams (16 issues) ([#937](https://github.com/MaxPayne89/klass-hero/issues/937)) ([9e66ba2](https://github.com/MaxPayne89/klass-hero/commit/9e66ba2705dc8b01cdcb89f759c46227de7559a8))

## [0.51.3](https://github.com/MaxPayne89/klass-hero/compare/v0.51.2...v0.51.3) (2026-05-22)


### Code Refactoring

* CSV enrollment import — partial success + application-level chunking ([#908](https://github.com/MaxPayne89/klass-hero/issues/908)) ([43320e5](https://github.com/MaxPayne89/klass-hero/commit/43320e564f8256b97e1ae934a18d6fa2b40b07d9))

## [0.51.2](https://github.com/MaxPayne89/klass-hero/compare/v0.51.1...v0.51.2) (2026-05-20)


### Bug Fixes

* read msg.content not msg.body in dashboard message preview ([#902](https://github.com/MaxPayne89/klass-hero/issues/902)) ([78cde35](https://github.com/MaxPayne89/klass-hero/commit/78cde355817d86b17883db65915873bc7b5a6901)), closes [#897](https://github.com/MaxPayne89/klass-hero/issues/897)

## [0.51.1](https://github.com/MaxPayne89/klass-hero/compare/v0.51.0...v0.51.1) (2026-05-20)


### Bug Fixes

* show program name on broadcast inbox rows ([#895](https://github.com/MaxPayne89/klass-hero/issues/895)) ([ee0175c](https://github.com/MaxPayne89/klass-hero/commit/ee0175cf83569577a2d17456770a239bb15ffa75))

## [0.51.0](https://github.com/MaxPayne89/klass-hero/compare/v0.50.6...v0.51.0) (2026-05-19)


### Features

* add safety standards section to /for-providers ([#890](https://github.com/MaxPayne89/klass-hero/issues/890)) ([9a8fd12](https://github.com/MaxPayne89/klass-hero/commit/9a8fd122e1b3453bf7b03e9d27278c65532e87b0))
* update homepage provider CTA copy and link ([#875](https://github.com/MaxPayne89/klass-hero/issues/875)) ([4a01a5a](https://github.com/MaxPayne89/klass-hero/commit/4a01a5ab4600b4115f58690a3850eae2e1a453de)), closes [#650](https://github.com/MaxPayne89/klass-hero/issues/650)


### Bug Fixes

* dispatch participant_added on broadcast so inbox updates without restart ([#893](https://github.com/MaxPayne89/klass-hero/issues/893)) ([212cd64](https://github.com/MaxPayne89/klass-hero/commit/212cd6491cdfdc6b4d4fdc1de82e11626b1f67fd))


### Code Refactoring

* collapse pending-enrollments refresh to single channel ([#872](https://github.com/MaxPayne89/klass-hero/issues/872)) ([5573fbd](https://github.com/MaxPayne89/klass-hero/commit/5573fbd67556682af9c535db8127092d07477fde))

## [0.50.6](https://github.com/MaxPayne89/klass-hero/compare/v0.50.5...v0.50.6) (2026-05-17)


### Bug Fixes

* let providers approve pending enrollments ([#859](https://github.com/MaxPayne89/klass-hero/issues/859)) ([#866](https://github.com/MaxPayne89/klass-hero/issues/866)) ([73b1287](https://github.com/MaxPayne89/klass-hero/commit/73b12872f2e4b091b52dbb2ed7ad46f3c87895ab))
* route admin users to primary layout with shared dropdown nav ([#864](https://github.com/MaxPayne89/klass-hero/issues/864)) ([d0bbe64](https://github.com/MaxPayne89/klass-hero/commit/d0bbe64bbb1aeb96b1eec07a495cee7f63284c6d))

## [0.50.5](https://github.com/MaxPayne89/klass-hero/compare/v0.50.4...v0.50.5) (2026-05-17)


### Code Refactoring

* extract name-to-initials algorithm to Shared.NameUtils ([#852](https://github.com/MaxPayne89/klass-hero/issues/852)) ([5570c4a](https://github.com/MaxPayne89/klass-hero/commit/5570c4afaac6741b85c82c0b953ecd30f404535d)), closes [#847](https://github.com/MaxPayne89/klass-hero/issues/847)
* extract projection boilerplate into Shared.Projection macro ([#862](https://github.com/MaxPayne89/klass-hero/issues/862)) ([3ec2513](https://github.com/MaxPayne89/klass-hero/commit/3ec25135274e0f278e1a0899f239dbcccfa6630e))
* extract staff assigned-programs lookup to shared helper ([#855](https://github.com/MaxPayne89/klass-hero/issues/855)) ([8719c92](https://github.com/MaxPayne89/klass-hero/commit/8719c923edfec770e8d0e6c159c1040480b825e6))

## [0.50.4](https://github.com/MaxPayne89/klass-hero/compare/v0.50.3...v0.50.4) (2026-05-14)


### Bug Fixes

* display assigned instructor on program detail page ([#841](https://github.com/MaxPayne89/klass-hero/issues/841)) ([09b8c96](https://github.com/MaxPayne89/klass-hero/commit/09b8c962bcd3e5d7dca3266547af15894b8b35cc))
* staff inbox visibility via event-driven CQRS ([#817](https://github.com/MaxPayne89/klass-hero/issues/817)) ([#848](https://github.com/MaxPayne89/klass-hero/issues/848)) ([16b4f14](https://github.com/MaxPayne89/klass-hero/commit/16b4f14acf339502aa8d393aee804e7ee5190fe7))

## [0.50.3](https://github.com/MaxPayne89/klass-hero/compare/v0.50.2...v0.50.3) (2026-05-12)


### Bug Fixes

* allow single-day workshops in program date validation ([#794](https://github.com/MaxPayne89/klass-hero/issues/794)) ([#827](https://github.com/MaxPayne89/klass-hero/issues/827)) ([dbab7d1](https://github.com/MaxPayne89/klass-hero/commit/dbab7d1c78ead073c6cf293ee9045331be66af31))
* clear participant restrictions on edit ([#795](https://github.com/MaxPayne89/klass-hero/issues/795)) ([#832](https://github.com/MaxPayne89/klass-hero/issues/832)) ([1ce9570](https://github.com/MaxPayne89/klass-hero/commit/1ce9570b6863093c66563372157df8e4050d3ea4))

## [0.50.2](https://github.com/MaxPayne89/klass-hero/compare/v0.50.1...v0.50.2) (2026-05-11)


### Bug Fixes

* allow attachments in provider and staff broadcasts ([#778](https://github.com/MaxPayne89/klass-hero/issues/778)) ([#823](https://github.com/MaxPayne89/klass-hero/issues/823)) ([5dca7ad](https://github.com/MaxPayne89/klass-hero/commit/5dca7ad7c8b424330f2d2d592cf7e190d59440f8))

## [0.50.1](https://github.com/MaxPayne89/klass-hero/compare/v0.50.0...v0.50.1) (2026-05-10)


### Bug Fixes

* add find_participation_record guard to submit_note handlers ([#761](https://github.com/MaxPayne89/klass-hero/issues/761)) ([721e62a](https://github.com/MaxPayne89/klass-hero/commit/721e62ab617cf1a11d346cc2c47076bd9141626a))
* include assigned staff as participants in private broadcast replies ([#818](https://github.com/MaxPayne89/klass-hero/issues/818)) ([d2cd0d8](https://github.com/MaxPayne89/klass-hero/commit/d2cd0d8b1a1afe4d7a86d802fce1eaf4b0d047e0))
* replace primeyouth.com emails with KlassHero contact address ([#815](https://github.com/MaxPayne89/klass-hero/issues/815)) ([a075169](https://github.com/MaxPayne89/klass-hero/commit/a075169e5dd8e8732da4a64b82fc5b6cb0bb676f))
* seeds.exs uitest-staff registration missing :name and :password ([#816](https://github.com/MaxPayne89/klass-hero/issues/816)) ([42de3ca](https://github.com/MaxPayne89/klass-hero/commit/42de3ca1e2ef8997ffbf4feac381d809ac2dba11)), closes [#710](https://github.com/MaxPayne89/klass-hero/issues/710)
* set active_nav in provider sidebar pages missing highlight ([#809](https://github.com/MaxPayne89/klass-hero/issues/809)) ([4961dd3](https://github.com/MaxPayne89/klass-hero/commit/4961dd3fe1d742166b451fcbd24fefe766f101d1))
* use atom list in booking_live can?/3 status check ([#774](https://github.com/MaxPayne89/klass-hero/issues/774)) ([77de305](https://github.com/MaxPayne89/klass-hero/commit/77de305d92f3c87c784f97ba1ea035e1d1f28e89))

## [0.50.0](https://github.com/MaxPayne89/klass-hero/compare/v0.49.0...v0.50.0) (2026-05-08)


### Features

* migrate UI to new design system shells ([#806](https://github.com/MaxPayne89/klass-hero/issues/806)) ([4da79cf](https://github.com/MaxPayne89/klass-hero/commit/4da79cf41287bbf82e76099beb91aa6bcf0d2924))

## [0.49.0](https://github.com/MaxPayne89/klass-hero/compare/v0.48.1...v0.49.0) (2026-05-01)


### Features

* carry owner email + name on incident_reported payload ([#781](https://github.com/MaxPayne89/klass-hero/issues/781)) ([0510680](https://github.com/MaxPayne89/klass-hero/commit/0510680391bb7c883fef3f3e6f468c1e636e9211))

## [0.48.1](https://github.com/MaxPayne89/klass-hero/compare/v0.48.0...v0.48.1) (2026-04-30)


### Bug Fixes

* enqueue incident email atomically with submission ([#754](https://github.com/MaxPayne89/klass-hero/issues/754)) ([#773](https://github.com/MaxPayne89/klass-hero/issues/773)) ([4207808](https://github.com/MaxPayne89/klass-hero/commit/4207808aef30c09083756f763d005b050be554b0))

## [0.48.0](https://github.com/MaxPayne89/klass-hero/compare/v0.47.0...v0.48.0) (2026-04-25)


### Features

* viewable incident reports under Programs Inventory ([#757](https://github.com/MaxPayne89/klass-hero/issues/757)) ([48e216f](https://github.com/MaxPayne89/klass-hero/commit/48e216f28af0af90c57a9b92321cecf3372463e0))

## [0.47.0](https://github.com/MaxPayne89/klass-hero/compare/v0.46.0...v0.47.0) (2026-04-25)


### Features

* notify business owner by email on incident report ([#755](https://github.com/MaxPayne89/klass-hero/issues/755)) ([d8df7cc](https://github.com/MaxPayne89/klass-hero/commit/d8df7cce33b3d1adeb13847948d2620568790b93))

## [0.46.0](https://github.com/MaxPayne89/klass-hero/compare/v0.45.0...v0.46.0) (2026-04-24)


### Features

* incident reporting for providers (closes [#34](https://github.com/MaxPayne89/klass-hero/issues/34)) ([#743](https://github.com/MaxPayne89/klass-hero/issues/743)) ([af5a07f](https://github.com/MaxPayne89/klass-hero/commit/af5a07fba73ae18df24bf965da98726cc08adfbd))

## [0.45.0](https://github.com/MaxPayne89/klass-hero/compare/v0.44.0...v0.45.0) (2026-04-23)


### Features

* filter "Meet the Heroes" to program-assigned staff only ([#722](https://github.com/MaxPayne89/klass-hero/issues/722)) ([ee9323b](https://github.com/MaxPayne89/klass-hero/commit/ee9323b3efa84676ef6f9ba07b75fe9fe310a353))

## [0.44.0](https://github.com/MaxPayne89/klass-hero/compare/v0.43.0...v0.44.0) (2026-04-22)


### Features

* pay rates per staff member with Money value object ([#720](https://github.com/MaxPayne89/klass-hero/issues/720)) ([e41f6cd](https://github.com/MaxPayne89/klass-hero/commit/e41f6cdf2d15271d2ae8a2ea4e1ec22ed5070d92))

## [0.43.0](https://github.com/MaxPayne89/klass-hero/compare/v0.42.0...v0.43.0) (2026-04-21)


### Features

* allow providers to manually invite individual participants ([#715](https://github.com/MaxPayne89/klass-hero/issues/715)) ([3673b48](https://github.com/MaxPayne89/klass-hero/commit/3673b482a1e146176918ae5d14bad76eb6dc7a24))

## [0.42.0](https://github.com/MaxPayne89/klass-hero/compare/v0.41.0...v0.42.0) (2026-04-20)


### Features

* optional checkout + edit-after-check-in on attendance roster ([#709](https://github.com/MaxPayne89/klass-hero/issues/709)) ([6bf170a](https://github.com/MaxPayne89/klass-hero/commit/6bf170a3be3412f7db959b0d1b4ecce715ce98e8))

## [0.41.0](https://github.com/MaxPayne89/klass-hero/compare/v0.40.0...v0.41.0) (2026-04-19)


### Features

* add ForQueryingSessionDetails port ([52980df](https://github.com/MaxPayne89/klass-hero/commit/52980df05b9060db7fa8f6cf940a1f94bd546aab))
* add ListProgramSessions query use case ([d0a3d2b](https://github.com/MaxPayne89/klass-hero/commit/d0a3d2b9dd851287f0e07e0856a44c520ff5240f))
* add provider_session_details read table ([1ab282c](https://github.com/MaxPayne89/klass-hero/commit/1ab282c3e8a259526dac422bf391971d3af9a1c5))
* add session_cancelled integration event ([5f1e144](https://github.com/MaxPayne89/klass-hero/commit/5f1e1443a7eba524e53d881efeb78a40fefbc512))
* add SessionDetail DTO, schema, and mapper ([ae1785a](https://github.com/MaxPayne89/klass-hero/commit/ae1785aad12cbca2b43a895218a338813aed212d))
* add SessionDetailsRepository (implements port) ([7e5ffb6](https://github.com/MaxPayne89/klass-hero/commit/7e5ffb68c86edbb6ee100e143398d871c9488676))
* add Sessions button to programs_table Actions ([40cf579](https://github.com/MaxPayne89/klass-hero/commit/40cf579a884fc9ad681e86242ac2845fc21289ea))
* add sessions_modal component ([1002ed8](https://github.com/MaxPayne89/klass-hero/commit/1002ed8a2f13174ce5fe5eca0e580a4e51a80ad5))
* bootstrap ProviderSessionDetails from write tables ([e70a96a](https://github.com/MaxPayne89/klass-hero/commit/e70a96ac15887a60a9725a07f98c59ac4f4922b0))
* extend participation_status with :cancelled variant ([0f0e19d](https://github.com/MaxPayne89/klass-hero/commit/0f0e19db80d485e8d058649554cac9b94ad04851))
* per-session view in provider dashboard ([#373](https://github.com/MaxPayne89/klass-hero/issues/373)) ([14ef096](https://github.com/MaxPayne89/klass-hero/commit/14ef09699c6afab8f611a29a5f27ce39e213ac00))
* project attendance counters ([18b2f70](https://github.com/MaxPayne89/klass-hero/commit/18b2f70ae34b3738768735520837a0f97c220a3b))
* project roster_seeded total_count ([83f7dc3](https://github.com/MaxPayne89/klass-hero/commit/83f7dc3e5c2d49a41e08bbd9f80097861524066a))
* project session status transitions ([aba4e42](https://github.com/MaxPayne89/klass-hero/commit/aba4e42ecc6f9ac2d61d73ad12edd40ae0c06e8b))
* project session_created into provider_session_details ([7aed9dc](https://github.com/MaxPayne89/klass-hero/commit/7aed9dcee45a6754eabfad79a42b9e0a163718e1))
* project staff assignment changes for scheduled sessions ([76fc559](https://github.com/MaxPayne89/klass-hero/commit/76fc5593b6973ea1bcd3345999b17b7be1ccddb9))
* promote session_cancelled domain event to integration event ([81936a8](https://github.com/MaxPayne89/klass-hero/commit/81936a880311a62deff535262806f40d333535b8))
* scaffold ProviderSessionDetails projection GenServer ([93b4855](https://github.com/MaxPayne89/klass-hero/commit/93b485520e0d2832c013b4c6437e7d83bff56d01))
* wire sessions modal into provider dashboard ([f9300ad](https://github.com/MaxPayne89/klass-hero/commit/f9300ad140c28a04cea91d9d27eddc4de3d8ff5b))


### Bug Fixes

* address PR review comments ([fb4cc47](https://github.com/MaxPayne89/klass-hero/commit/fb4cc47d07e692e061152439f4a49a294b74a1c4))
* address PR review comments on program staff assignment factory ([31f97f0](https://github.com/MaxPayne89/klass-hero/commit/31f97f06fe93ec4a5bbcf9d4ccb06d143bd1d69f)), closes [#672](https://github.com/MaxPayne89/klass-hero/issues/672)
* correct table name in ConversationQueries total_unread_count test ([4e6385d](https://github.com/MaxPayne89/klass-hero/commit/4e6385d0b7d1cf28c7b066bfd042d78ddc399d79)), closes [#686](https://github.com/MaxPayne89/klass-hero/issues/686)
* preserve evolved state on session_created replay ([f186092](https://github.com/MaxPayne89/klass-hero/commit/f1860926346e20bcaa2fbffe065e0e2d2aa1552b))
* preserve nil type in ConversationMapper.to_create_attrs/1 ([64464d4](https://github.com/MaxPayne89/klass-hero/commit/64464d4c4e31c29651327503c8acd8b34a7b3860))
* warn when status transition targets unknown session ([2d91593](https://github.com/MaxPayne89/klass-hero/commit/2d915939a6c8916af7cdeee0ec829cffdee293d5))


### Code Refactoring

* drop unused bootstrapped flag from ProviderSessionDetails state ([1d7c135](https://github.com/MaxPayne89/klass-hero/commit/1d7c135d1072a0908e45ef5b7c3a632825904324))
* extract warn_if_missing helper for projection zero-row updates ([7bf4b63](https://github.com/MaxPayne89/klass-hero/commit/7bf4b631c0ca8fa8eee4f6094752f8a7581a2abc))
* merge resolve_program + staff lookup into one query ([f0e07ad](https://github.com/MaxPayne89/klass-hero/commit/f0e07ad41f770bfd31c178b33da0f6781c0414af))
* rename ListProgramSessions.run to execute for convention consistency ([df3cf2d](https://github.com/MaxPayne89/klass-hero/commit/df3cf2d190d75fb8ef3a676ead02a71eb76a7b92))
* resolve credo strict warnings in messaging ([6dc8b7f](https://github.com/MaxPayne89/klass-hero/commit/6dc8b7f12db35858ac96cd4a77a0dec757a652f3))

## [0.40.0](https://github.com/MaxPayne89/klass-hero/compare/v0.39.0...v0.40.0) (2026-04-18)


### Features

* initialize conversation on Contact Provider click ([#586](https://github.com/MaxPayne89/klass-hero/issues/586)) ([5f8956e](https://github.com/MaxPayne89/klass-hero/commit/5f8956ef96efa67e009461af60e3d5ca2671e1fd))
* initialize conversation when parent clicks Contact Provider ([#586](https://github.com/MaxPayne89/klass-hero/issues/586)) ([741dcb1](https://github.com/MaxPayne89/klass-hero/commit/741dcb1cdc11f8421110e845fdbe2a6ab0a68903))


### Bug Fixes

* isolate cross-parent conversations in StartProgramConversation ([d4bbca3](https://github.com/MaxPayne89/klass-hero/commit/d4bbca363e1576d04a34519b8ca03d159fc5a816)), closes [#691](https://github.com/MaxPayne89/klass-hero/issues/691)

## [0.39.0](https://github.com/MaxPayne89/klass-hero/compare/v0.38.0...v0.39.0) (2026-04-18)


### Features

* add child_created and child_updated domain and integration events ([73da49f](https://github.com/MaxPayne89/klass-hero/commit/73da49f84b6e0d38a3f2414e98801729b71c3382))
* add EnrolledChildren projection with schema and bootstrap ([04090ff](https://github.com/MaxPayne89/klass-hero/commit/04090fffe066d9a1ce128415c762ba5123cfc5d0))
* add EnrolledChildren to ProjectionSupervisor ([e0b4858](https://github.com/MaxPayne89/klass-hero/commit/e0b4858e885bd6037f91e8750c29d5cd68c31a5f))
* add enrollment_created domain and integration events ([189043e](https://github.com/MaxPayne89/klass-hero/commit/189043ecf55557055a9ea65ffe3b6b7dba86d076))
* add messaging_enrolled_children table and enrolled_child_names column ([fa6fef4](https://github.com/MaxPayne89/klass-hero/commit/fa6fef45ded14f7fbee8527d4abbd1f50a70a05b))
* extend ConversationSummaries with enrolled_child_names ([f0ae90c](https://github.com/MaxPayne89/klass-hero/commit/f0ae90c3de9855c3cd6361de4a5f95b7e2456883))
* show enrolled child names in conversation card subtitle ([39b607f](https://github.com/MaxPayne89/klass-hero/commit/39b607f2ad42386877cfab80b072df55c111efd0))
* show enrolled child names in conversation cards and titles ([361380c](https://github.com/MaxPayne89/klass-hero/commit/361380c15f12795d9edae4710e768bd4de5b9aff))
* update get_conversation_title to show parent name with child names ([ae7a9bf](https://github.com/MaxPayne89/klass-hero/commit/ae7a9bffa758553ba7875c13980b9ac8b66f1136))
* wire enrollment_created event promotion and dispatch ([5ef06b8](https://github.com/MaxPayne89/klass-hero/commit/5ef06b887aa41c61fadb9d8aa92ac2e8cfa45e6a))


### Bug Fixes

* include program_id in conversation_created event payload ([34c4c63](https://github.com/MaxPayne89/klass-hero/commit/34c4c63096585984ce5933972393243094b1ba4d))
* resolve child_first_name from children table on enrollment_created ([8dc8749](https://github.com/MaxPayne89/klass-hero/commit/8dc87496211a60fa02e5a469e3ff5d22aec7e4af))
* scope enrolled child names to provider and staff viewers only ([6547725](https://github.com/MaxPayne89/klass-hero/commit/65477255a5a3eb674e729b7ca45644b8bffe63d2)), closes [#688](https://github.com/MaxPayne89/klass-hero/issues/688)


### Code Refactoring

* simplify EnrolledChildren projection queries ([be2181e](https://github.com/MaxPayne89/klass-hero/commit/be2181eaf9585a60172ff93e48376cb56ca79129))

## [0.38.0](https://github.com/MaxPayne89/klass-hero/compare/v0.37.0...v0.38.0) (2026-04-16)


### Features

* show provider business name above program title on program detail page ([5809ff3](https://github.com/MaxPayne89/klass-hero/commit/5809ff3a8d41dfe6789153baac596a8b838db837)), closes [#549](https://github.com/MaxPayne89/klass-hero/issues/549)
* show provider business name in hero on program detail page ([c7e343d](https://github.com/MaxPayne89/klass-hero/commit/c7e343db24eaa522a536342719b22cc82dc60ead))

## [0.37.0](https://github.com/MaxPayne89/klass-hero/compare/v0.36.0...v0.37.0) (2026-04-16)


### Features

* add provider business profile card to program detail page ([b56b0b3](https://github.com/MaxPayne89/klass-hero/commit/b56b0b35b6cdd0cf47f0079b22db20b23fa9e03e))
* add provider business profile card to program detail page ([17c05dd](https://github.com/MaxPayne89/klass-hero/commit/17c05dd85371dbdc23e7e688c8484ebdf2dc9a35)), closes [#550](https://github.com/MaxPayne89/klass-hero/issues/550)


### Bug Fixes

* allow provider staff to send follow-ups in broadcasts ([882d48b](https://github.com/MaxPayne89/klass-hero/commit/882d48bf072d8a53fae6532a76e762b0c8ff89b8))
* allow provider staff to send follow-ups in broadcasts ([d77fcb2](https://github.com/MaxPayne89/klass-hero/commit/d77fcb27bf89223217b153d586e8d192c546ef52)), closes [#669](https://github.com/MaxPayne89/klass-hero/issues/669)
* filter active staff lookup by both provider_id and user_id ([ae3821d](https://github.com/MaxPayne89/klass-hero/commit/ae3821d06fc149d8939591ad2331f720f2446774)), closes [#669](https://github.com/MaxPayne89/klass-hero/issues/669)

## [0.36.0](https://github.com/MaxPayne89/klass-hero/compare/v0.35.0...v0.36.0) (2026-04-15)


### Features

* add bootstrap ACL for session completion counts ([f2726d7](https://github.com/MaxPayne89/klass-hero/commit/f2726d78f6ae0c859ad13a3b463e059a030b7e72))
* add provider_session_stats read model table and schema ([88e6cc8](https://github.com/MaxPayne89/klass-hero/commit/88e6cc8a31d304b4f756ffd73db7680ce703cc87))
* add ProviderSessionStats projection GenServer ([ad2f120](https://github.com/MaxPayne89/klass-hero/commit/ad2f1209dcf51ea5e6237b87ab50fa9cb6cc1725))
* add session counter to provider overview dashboard ([623f1ad](https://github.com/MaxPayne89/klass-hero/commit/623f1adae70d892c8121d8fc7f23453e89a9d54b))
* add SessionStats read model DTO and query port ([37f7016](https://github.com/MaxPayne89/klass-hero/commit/37f70161995d8ec435fab46fa347c120ce732cfa))
* add SessionStats read repository with query port wiring ([5f7520d](https://github.com/MaxPayne89/klass-hero/commit/5f7520d243799dcec6ec8d1af72a96e814df5a04))
* display session counter on provider overview dashboard ([6ddb94a](https://github.com/MaxPayne89/klass-hero/commit/6ddb94ac0412b487abafd71ad3f265de32d66756))
* enrich session_completed event with provider_id and program_title ([51e3775](https://github.com/MaxPayne89/klass-hero/commit/51e3775423f4950fe41296961574fb5b70de3f7b)), closes [#372](https://github.com/MaxPayne89/klass-hero/issues/372)


### Bug Fixes

* address PR review comments ([8927105](https://github.com/MaxPayne89/klass-hero/commit/892710506e8150624a35eef47647f6f6705a9bbe)), closes [#675](https://github.com/MaxPayne89/klass-hero/issues/675)
* use fallback values in session_completed event resolution ([7d421ee](https://github.com/MaxPayne89/klass-hero/commit/7d421eefa6fb18b3375d1c1a698b38e21511f5d0))


### Performance Improvements

* guard session stats refresh by tab and change detection ([e2a2c49](https://github.com/MaxPayne89/klass-hero/commit/e2a2c49a336c716fbf64fb89d9036529b5f9d7ae))


### Code Refactoring

* extract shared fetch_program in ProgramProviderResolver ([0d0bb27](https://github.com/MaxPayne89/klass-hero/commit/0d0bb2721ca89858edeb8941037a7c0e66e909eb))
* rename Participation config keys to for_ convention ([30c6e30](https://github.com/MaxPayne89/klass-hero/commit/30c6e307c4307fe36b5dbc5cbed7471c6f74ba69))
* standardize Participation ACL directory naming ([8c7f147](https://github.com/MaxPayne89/klass-hero/commit/8c7f147d42a8b3d2809c94981e0fb918b5cb9a0e))
* switch ProjectionSupervisor to one_for_one strategy ([38e5786](https://github.com/MaxPayne89/klass-hero/commit/38e5786afbef8b34b8413279f1f1f25e1cee6a9f))

## [0.35.0](https://github.com/MaxPayne89/klass-hero/compare/v0.34.0...v0.35.0) (2026-04-14)


### Features

* unify staff invitation email and auto-create provider profile ([24fc2db](https://github.com/MaxPayne89/klass-hero/commit/24fc2dba963e3a8b8cf4e49e57189f227cee78d2))
* unify staff invitation email and auto-create provider profile ([8d3afec](https://github.com/MaxPayne89/klass-hero/commit/8d3afec722e137c1348f6659b86685bdaac545be)), closes [#363](https://github.com/MaxPayne89/klass-hero/issues/363)

## [0.34.0](https://github.com/MaxPayne89/klass-hero/compare/v0.33.0...v0.34.0) (2026-04-14)


### Features

* add provider profile completion flow after activation ([5d48801](https://github.com/MaxPayne89/klass-hero/commit/5d48801002f2198e649993062984a19107635e6e))
* add provider profile completion flow after staff activation ([a2f6c91](https://github.com/MaxPayne89/klass-hero/commit/a2f6c91c7b06a794f02c40f40ecf541bcf97593a)), closes [#364](https://github.com/MaxPayne89/klass-hero/issues/364)


### Bug Fixes

* filter empty strings from categories hidden input ([1913533](https://github.com/MaxPayne89/klass-hero/commit/1913533e6fd457647472bdb8c60fdf537851b7f4)), closes [#667](https://github.com/MaxPayne89/klass-hero/issues/667)


### Code Refactoring

* move StaffInvitationStatusHandler into event_handlers/ subdirectory ([d1bd8d3](https://github.com/MaxPayne89/klass-hero/commit/d1bd8d37224b53869282d3b95abcc98b83f022b1))

## [0.33.0](https://github.com/MaxPayne89/klass-hero/compare/v0.32.0...v0.33.0) (2026-04-12)


### Features

* update Community Focused homepage section with secure messaging copy ([9f8a0dd](https://github.com/MaxPayne89/klass-hero/commit/9f8a0dd5fc134ac0a31a4758c38bc3373199c079))

## [0.32.0](https://github.com/MaxPayne89/klass-hero/compare/v0.31.0...v0.32.0) (2026-04-12)


### Features

* add /dream skill for memory consolidation ([8ef9a08](https://github.com/MaxPayne89/klass-hero/commit/8ef9a089a9eb64d9d27fc648109eb296f1f0041d))


### Bug Fixes

* correct describe block arity for update_schema in mapper tests ([2661bfa](https://github.com/MaxPayne89/klass-hero/commit/2661bfacda6bcd79bce3c34ae9b5aaf8f0c16d77)), closes [#626](https://github.com/MaxPayne89/klass-hero/issues/626)
* correct e2e test description to Wallaby only ([931022d](https://github.com/MaxPayne89/klass-hero/commit/931022de85fb945302a2de6a528d66f84e8f22ee)), closes [#660](https://github.com/MaxPayne89/klass-hero/issues/660)
* force recompile lazy_html NIF in CI to prevent stale cache ([40e5b11](https://github.com/MaxPayne89/klass-hero/commit/40e5b11ebe47f20831df51de06332b80ddb7d77c)), closes [#660](https://github.com/MaxPayne89/klass-hero/issues/660)
* replace Task.async with Task.Supervisor.async_nolink in all LiveViews ([451353e](https://github.com/MaxPayne89/klass-hero/commit/451353eb6b653a82e462c933ade88338bfaf4206)), closes [#628](https://github.com/MaxPayne89/klass-hero/issues/628)


### Performance Improvements

* **dashboard_live:** parallelize children + programs queries in parent mount ([6e3739f](https://github.com/MaxPayne89/klass-hero/commit/6e3739f8065927cf546d7c7d399dcb3e0ccb03c7))


### Code Refactoring

* document CQRS direction and add command/query section headers to facades ([55e25c1](https://github.com/MaxPayne89/klass-hero/commit/55e25c1f958131614158e06784283347a5c5b690))
* extract direct repo calls from facades into command/query modules ([f70341d](https://github.com/MaxPayne89/klass-hero/commit/f70341d673bddadc86fb337f28ca3a28a1fc6312))
* reorganize use cases into commands/ and queries/ directories ([598bdf3](https://github.com/MaxPayne89/klass-hero/commit/598bdf3d2bea28f96c22c043045becd8f206496a))
* split mixed ports into read/write pairs for CQRS ([5ea551d](https://github.com/MaxPayne89/klass-hero/commit/5ea551d74c066f61f33a609fce4f750f1db5627a))

## [0.31.0](https://github.com/MaxPayne89/klass-hero/compare/v0.30.0...v0.31.0) (2026-04-11)


### Features

* add count_by_provider_and_origin to program repository ([#360](https://github.com/MaxPayne89/klass-hero/issues/360)) ([d04c58d](https://github.com/MaxPayne89/klass-hero/commit/d04c58d8754ed7f5064911f1a9d88c60a8b7a068))
* add origin column to programs table ([#360](https://github.com/MaxPayne89/klass-hero/issues/360)) ([69f9b3e](https://github.com/MaxPayne89/klass-hero/commit/69f9b3e6b0799431babdf0dac48cc4e21b303487))
* add origin field to Program domain model ([#360](https://github.com/MaxPayne89/klass-hero/issues/360)) ([7582893](https://github.com/MaxPayne89/klass-hero/commit/7582893554bde4c554d4b2e0c6c1ea6dbdaaabf4))
* add origin field to program schema and mapper ([#360](https://github.com/MaxPayne89/klass-hero/issues/360)) ([443fa6e](https://github.com/MaxPayne89/klass-hero/commit/443fa6ea425cf7e31ff4aa5fb20c664987e03afa))
* enforce program limit in CreateProgram use case ([#360](https://github.com/MaxPayne89/klass-hero/issues/360)) ([d5eaa14](https://github.com/MaxPayne89/klass-hero/commit/d5eaa14723d14c0e538e466f9cd75c4b7801a622))
* enforce program limit in provider dashboard UI ([#360](https://github.com/MaxPayne89/klass-hero/issues/360)) ([79f14b0](https://github.com/MaxPayne89/klass-hero/commit/79f14b087f31060a0060d0e70e0b69e4edb452f6))
* enforce starter tier 2-program limit with origin tracking ([21fa805](https://github.com/MaxPayne89/klass-hero/commit/21fa8050e97bf5737e765795e726ebc19bc8f140))


### Bug Fixes

* address code review suggestions for program limit ([#360](https://github.com/MaxPayne89/klass-hero/issues/360)) ([9cb1541](https://github.com/MaxPayne89/klass-hero/commit/9cb154110b714986290ba31f1a829d9e9c7258bc))
* use configured Logger metadata key in ProgramMapper ([#360](https://github.com/MaxPayne89/klass-hero/issues/360)) ([03441ce](https://github.com/MaxPayne89/klass-hero/commit/03441ce416d6fd7b6b34ae4643a5c98c42b81c0d))
* use self-posted count for program slots in dashboard ([#360](https://github.com/MaxPayne89/klass-hero/issues/360)) ([965de6f](https://github.com/MaxPayne89/klass-hero/commit/965de6f28ec4c7d18cf9fdd37331f1f8408ef4bc))


### Code Refactoring

* move count query to ForListingPrograms port and add origin validation ([#360](https://github.com/MaxPayne89/klass-hero/issues/360)) ([52e94e1](https://github.com/MaxPayne89/klass-hero/commit/52e94e18ea41358a3ec4e23c862bb494789a0467))
* simplify program limit tests and harden mapper ([#360](https://github.com/MaxPayne89/klass-hero/issues/360)) ([0d42914](https://github.com/MaxPayne89/klass-hero/commit/0d4291477f620506a58829f73e1f05147e1c7527))

## [0.30.0](https://github.com/MaxPayne89/klass-hero/compare/v0.29.0...v0.30.0) (2026-04-10)


### Features

* add message and broadcast buttons to staff roster view ([9fb0b21](https://github.com/MaxPayne89/klass-hero/commit/9fb0b21486b6d5e50c23bba5bd63e253223287b1))
* add message and broadcast buttons to staff roster view ([98d41f5](https://github.com/MaxPayne89/klass-hero/commit/98d41f5092d15c118f406431238a831e77d7cbaf)), closes [#620](https://github.com/MaxPayne89/klass-hero/issues/620)


### Bug Fixes

* add server-side entitlement guard and simplify staff assignment check ([94f1187](https://github.com/MaxPayne89/klass-hero/commit/94f1187663ca29c606225d3f810cb202a88e88f6))
* harden error handling and tighten entitlement clause ([077b4a0](https://github.com/MaxPayne89/klass-hero/commit/077b4a01c172919d039d6bbc3c31f0c7a8de636e))


### Code Refactoring

* fix credo strict issues in staff messaging ([6163bd1](https://github.com/MaxPayne89/klass-hero/commit/6163bd19bf5cfee134afbbdab286dbddcf00d44c))
* fix remaining credo strict issues ([c77524d](https://github.com/MaxPayne89/klass-hero/commit/c77524d146a80121659c1a86f18d2ecf50800c41))

## [0.29.0](https://github.com/MaxPayne89/klass-hero/compare/v0.28.0...v0.29.0) (2026-04-09)


### Features

* **program_catalog:** hide expired programs from featured section ([0fa9aed](https://github.com/MaxPayne89/klass-hero/commit/0fa9aeda1407e14486f1720c9b5abc99464afa54))


### Bug Fixes

* remove free cancellation line from program detail page ([ccbb2f2](https://github.com/MaxPayne89/klass-hero/commit/ccbb2f27554b47854d55108edd2f0a2553cbfedd))


### Performance Improvements

* **sessions_live:** parallelize programs + sessions DB queries in mount ([0331c7e](https://github.com/MaxPayne89/klass-hero/commit/0331c7e95f340daffe84d43ad22e0223a6f6503c))


### Code Refactoring

* **sessions_live:** extract apply_sessions_result/2 helper ([ec93742](https://github.com/MaxPayne89/klass-hero/commit/ec937420f019d015c9b12d8f7253bdd608aff86e)), closes [#622](https://github.com/MaxPayne89/klass-hero/issues/622)

## [0.28.0](https://github.com/MaxPayne89/klass-hero/compare/v0.27.0...v0.28.0) (2026-04-09)


### Features

* hide expired programs from home page featured section ([3b79f3c](https://github.com/MaxPayne89/klass-hero/commit/3b79f3c8eb9fb51e86478cbf20c132187ef28649))
* **program_catalog:** hide expired programs from featured section ([baa991e](https://github.com/MaxPayne89/klass-hero/commit/baa991e1619fcdda7c73efb5b4624c54eafc1141))

## [0.27.0](https://github.com/MaxPayne89/klass-hero/compare/v0.26.1...v0.27.0) (2026-04-07)


### Features

* hide expired programs from public listing page ([6f94876](https://github.com/MaxPayne89/klass-hero/commit/6f948768128c939fb8ad4f958c1aa84e65a61aad))
* polish frontend with typography, scroll animations, and component cleanup ([6f5d3be](https://github.com/MaxPayne89/klass-hero/commit/6f5d3be704e59af54430dcf646392b9b1e8fa475))
* **program_catalog:** hide expired programs from public listing ([f29015f](https://github.com/MaxPayne89/klass-hero/commit/f29015f67cb68b987df91d743271d62f96fcb6fa)), closes [#610](https://github.com/MaxPayne89/klass-hero/issues/610)


### Bug Fixes

* harden ScrollReveal hook against timeout races and JS failures ([d6c28d2](https://github.com/MaxPayne89/klass-hero/commit/d6c28d22e92c142ec7ce568ae650d9b100f5e50d)), closes [#615](https://github.com/MaxPayne89/klass-hero/issues/615)


### Performance Improvements

* **program_catalog:** index program_listings.end_date ([a6d79f7](https://github.com/MaxPayne89/klass-hero/commit/a6d79f7712df05441bfe4330b084957d303c6fa5))

## [0.26.1](https://github.com/MaxPayne89/klass-hero/compare/v0.26.0...v0.26.1) (2026-04-07)


### Performance Improvements

* **messaging:** eliminate redundant provider DB query in conversation show ([3ecf481](https://github.com/MaxPayne89/klass-hero/commit/3ecf481cfde1d80dcaff2af3ca22cf22321594fb))
* **messaging:** eliminate redundant provider DB query in conversation show ([0afc865](https://github.com/MaxPayne89/klass-hero/commit/0afc865d7f4fbfa88d4291fbc6ed315e65f6eb5b))

## [0.26.0](https://github.com/MaxPayne89/klass-hero/compare/v0.25.0...v0.26.0) (2026-04-06)


### Features

* add cross-navigation links between staff and provider dashboards ([cde4c4d](https://github.com/MaxPayne89/klass-hero/commit/cde4c4d75c9040a284f5cc7c5b2ec6436e1b39ea))
* add opt-in provider checkbox to staff invitation form ([65399ea](https://github.com/MaxPayne89/klass-hero/commit/65399ea010e24bb309bfaeb60a546b7cc88ea0b6))
* add originated_from column to providers table ([bbdcb5e](https://github.com/MaxPayne89/klass-hero/commit/bbdcb5e6c265842e4c6a8edf4213cb236f41e7c5))
* add originated_from field to ProviderProfile domain model ([62d3806](https://github.com/MaxPayne89/klass-hero/commit/62d38064b537164d228ba452415cafe4096b95d9))
* add originated_from field to ProviderProfileSchema ([36b53f3](https://github.com/MaxPayne89/klass-hero/commit/36b53f35b0c47ef2bf478477161a0384b620524c))
* allow staff members to opt-in as independent providers ([8004357](https://github.com/MaxPayne89/klass-hero/commit/8004357288c37937809d73295a628bb0a88810f1))
* create provider profile on staff registration when opted in ([c6eab3c](https://github.com/MaxPayne89/klass-hero/commit/c6eab3ccaffcf683ab93b0e8d506743b43894c79))
* extend emit_staff_user_registered with optional payload ([26f41da](https://github.com/MaxPayne89/klass-hero/commit/26f41da7cd77a820962b3326226aa6cad563b8fd))
* map originated_from in ProviderProfileMapper ([78ce898](https://github.com/MaxPayne89/klass-hero/commit/78ce898cdd2e58c5e2cdda920458bfe32bbd34a5))
* support dual-role in staff registration changeset ([244e7c9](https://github.com/MaxPayne89/klass-hero/commit/244e7c96c5ef2a6ab93a77850b9cddd11a23f136))
* swap router precedence so provider takes priority over staff ([96043ea](https://github.com/MaxPayne89/klass-hero/commit/96043ea2ebb86536638e09c378f376afdbaf992e))


### Bug Fixes

* address PR review comments ([5c3fa29](https://github.com/MaxPayne89/klass-hero/commit/5c3fa293e475002cef287c762b92d4b83110499b)), closes [#603](https://github.com/MaxPayne89/klass-hero/issues/603)
* preserve checkbox state through LiveView re-renders ([5e9caa6](https://github.com/MaxPayne89/klass-hero/commit/5e9caa69175a381f2d85cc313ad61663f504d5b5))
* prevent race between ProviderEventHandler and StaffInvitationStatusHandler ([bd7d2b5](https://github.com/MaxPayne89/klass-hero/commit/bd7d2b5ef5c5b830a724a4fda7fac49f5f1f58f0))
* simplify test name for empty-list batch absent guard ([ae2a542](https://github.com/MaxPayne89/klass-hero/commit/ae2a5429185f3f8f57e5109515dd4b3c21a52334)), closes [#602](https://github.com/MaxPayne89/klass-hero/issues/602)
* strengthen mapper test assertions and fix moduledoc ([c5b7ce4](https://github.com/MaxPayne89/klass-hero/commit/c5b7ce4b3104ba3b8497e4ca0536e4bc08d6fa1b)), closes [#600](https://github.com/MaxPayne89/klass-hero/issues/600)


### Performance Improvements

* **participation:** batch-update absent records via update_all in CompleteSession ([47788ef](https://github.com/MaxPayne89/klass-hero/commit/47788ef50ced323da6fcaf6a9f46b997d12d8766))
* **participation:** batch-update absent records via update_all in CompleteSession ([04758f9](https://github.com/MaxPayne89/klass-hero/commit/04758f91964747bc9d898bd93c31eec8399b4537))


### Code Refactoring

* simplify dual-role implementation after code review ([d946272](https://github.com/MaxPayne89/klass-hero/commit/d946272c75598dd9d39e21aabddaa2360c46a29f))
* simplify redundant mapper test assertions ([86ad154](https://github.com/MaxPayne89/klass-hero/commit/86ad1540093c2136624690d5aa9ba29ea4298cfa)), closes [#600](https://github.com/MaxPayne89/klass-hero/issues/600)

## [0.25.0](https://github.com/MaxPayne89/klass-hero/compare/v0.24.3...v0.25.0) (2026-04-05)


### Features

* add Attachment domain model with validation ([047fdf9](https://github.com/MaxPayne89/klass-hero/commit/047fdf9f31abdb51405e54cde27a68bde267b962))
* add AttachmentSchema, AttachmentMapper, update MessageSchema ([6b37faf](https://github.com/MaxPayne89/klass-hero/commit/6b37faf3d361256905af0d91f50ce8ee1f1beb10))
* add ForManagingAttachments port, wire DI, update boundary exports ([bca432d](https://github.com/MaxPayne89/klass-hero/commit/bca432df63bee0a4d5e7b4344f738a5105b1a0fa))
* add photo upload UI and attachment rendering in messages ([473697f](https://github.com/MaxPayne89/klass-hero/commit/473697f3f6be2a1cddc9ba1dfc0ead7fc65f4086))
* clean up S3 attachment files during retention enforcement ([ad7499f](https://github.com/MaxPayne89/klass-hero/commit/ad7499f5e128d7a18c530f35ad837914573132da))
* create message_attachments table and add has_attachments to summaries ([e81cb92](https://github.com/MaxPayne89/klass-hero/commit/e81cb92aa707c20a62c67164094dc8ba88862942))
* enrich message_sent event with attachment metadata ([c381454](https://github.com/MaxPayne89/klass-hero/commit/c3814542b6cdb01c26ea58c18a3c03f845ffb167))
* implement AttachmentRepository with TDD ([1187f76](https://github.com/MaxPayne89/klass-hero/commit/1187f76b002b1986f025b012b9757e8c4512b066))
* make message content optional when attachments present ([3e65f6d](https://github.com/MaxPayne89/klass-hero/commit/3e65f6d075b26a8e7a83f3e1db95aee43aa81469))
* project has_attachments in conversation summaries ([b568c44](https://github.com/MaxPayne89/klass-hero/commit/b568c44cd8a1835bc162c4358a075839ba57ea8a))
* support attachments in SendMessage use case with S3 upload ([8635c1c](https://github.com/MaxPayne89/klass-hero/commit/8635c1c1f5169d5347b772540d9eac013cd00230))
* support photo attachments in messages ([c9526cb](https://github.com/MaxPayne89/klass-hero/commit/c9526cbb52446786b745051cf9de721b18bac16f))


### Bug Fixes

* add UUID validation to Attachment model ([1632944](https://github.com/MaxPayne89/klass-hero/commit/1632944328a7c4453adcce86a8e90e15d0669783))
* address PR review comments for photo attachments ([bc4dfd0](https://github.com/MaxPayne89/klass-hero/commit/bc4dfd087630ea7e2402ca83e7a027381098e680)), closes [#594](https://github.com/MaxPayne89/klass-hero/issues/594)
* address review findings for photo attachments robustness ([a5abd17](https://github.com/MaxPayne89/klass-hero/commit/a5abd17b769fb6e5f741cead210d28bd8688529e))
* eliminate flaky tests caused by TOCTOU race and non-deterministic ordering ([ccb8a4b](https://github.com/MaxPayne89/klass-hero/commit/ccb8a4bb914b6350b7db748aba0de95f1cdc5ef4))
* register added_count Logger metadata key ([500283b](https://github.com/MaxPayne89/klass-hero/commit/500283bbc96e69b4b5ae9384e4c8dd84eea555ab))
* resolve credo strict issues for photo attachments ([93422cd](https://github.com/MaxPayne89/klass-hero/commit/93422cd491bd18a1a7294e8e3492e09b8a00d38a))
* resolve flaky EntitlementsBypassTest via start_supervised! ([4c61ad0](https://github.com/MaxPayne89/klass-hero/commit/4c61ad09e445e82077d5bdf73cc3709bb04e0bbb))
* use public S3 bucket and add cleanup on message creation failure ([45363f8](https://github.com/MaxPayne89/klass-hero/commit/45363f87f1ad17fbf00292104065c6c4163391ed))


### Performance Improvements

* **messaging:** batch-insert staff participants via insert_all in StaffAssignmentHandler ([742e66d](https://github.com/MaxPayne89/klass-hero/commit/742e66d4e4fa313396103db9a933e099e9bbc02a))
* **messaging:** batch-insert staff participants via insert_all in StaffAssignmentHandler ([6b5e6cd](https://github.com/MaxPayne89/klass-hero/commit/6b5e6cd1d9016cb18ad8e95a6b47dc35a07bf6b3))


### Code Refactoring

* address review suggestions and move workers to canonical location ([5fb7530](https://github.com/MaxPayne89/klass-hero/commit/5fb7530226bdd93e4d8c98733597f32b54836115))
* simplify photo attachments code ([98b9a1c](https://github.com/MaxPayne89/klass-hero/commit/98b9a1ceeebe29f6bb12f055c2f5e03377e29b93))

## [0.24.3](https://github.com/MaxPayne89/klass-hero/compare/v0.24.2...v0.24.3) (2026-04-03)


### Bug Fixes

* address PR review comments ([ae4fe39](https://github.com/MaxPayne89/klass-hero/commit/ae4fe3995e1e5da1f5a3fb28fce57e3b0346a0cc)), closes [#588](https://github.com/MaxPayne89/klass-hero/issues/588)
* center icon and text in provider step cards ([1de2231](https://github.com/MaxPayne89/klass-hero/commit/1de2231ac6ee750e545515373703c681f10de31d))
* center icon and text in provider step cards ([6349f03](https://github.com/MaxPayne89/klass-hero/commit/6349f032b8eab4d69847220139d0dd249f6a91cb)), closes [#544](https://github.com/MaxPayne89/klass-hero/issues/544)
* left-align step numbers and center icons in vetting cards ([4c07ab9](https://github.com/MaxPayne89/klass-hero/commit/4c07ab987887ede38bf11b4b4009f4798beb7726))
* left-align step numbers and center icons in vetting process cards ([334928c](https://github.com/MaxPayne89/klass-hero/commit/334928c2f44f6fcbd4a7fd5c543e0a541785a0d3)), closes [#545](https://github.com/MaxPayne89/klass-hero/issues/545)
* shorten guard clause to satisfy credo MaxLineLength ([f4a9328](https://github.com/MaxPayne89/klass-hero/commit/f4a9328c7cb236120e92242af4f731e080711e48))


### Performance Improvements

* **messaging:** pass pre-fetched conversation to SendMessage in LiveHelper ([5ab1a8c](https://github.com/MaxPayne89/klass-hero/commit/5ab1a8c869f8a9bac231e4f4e9eec8104d6b7431))
* **messaging:** pass pre-fetched conversation to SendMessage in LiveHelper ([60c206d](https://github.com/MaxPayne89/klass-hero/commit/60c206d1c835dfb439ef0bc6ea89c3b6ebb2be02))
* speed up test suite by eliminating artificial delays (60s → 28s) ([d7dccc9](https://github.com/MaxPayne89/klass-hero/commit/d7dccc90bc5e85d4a520be792e0471a6ee2b27f1))
* speed up test suite by eliminating artificial delays (60s to 28s) ([c9e7ca8](https://github.com/MaxPayne89/klass-hero/commit/c9e7ca89eb3171e17afc7e3b3388c56c166ca0d4))


### Code Refactoring

* simplify VerifyWebhookSignature plug tests ([18415c7](https://github.com/MaxPayne89/klass-hero/commit/18415c786ede63407141aede6ea03da3f28a196f))

## [0.24.2](https://github.com/MaxPayne89/klass-hero/compare/v0.24.1...v0.24.2) (2026-04-02)


### Bug Fixes

* keep program slots counter in sync after program changes ([c38a9c4](https://github.com/MaxPayne89/klass-hero/commit/c38a9c436d09d1ce0acfb6804af06bcc3d8c243d))
* keep program slots counter in sync after program creation ([940eb54](https://github.com/MaxPayne89/klass-hero/commit/940eb544c46ac3cd5fcaf44a63cec5daba1b01c7)), closes [#568](https://github.com/MaxPayne89/klass-hero/issues/568)

## [0.24.1](https://github.com/MaxPayne89/klass-hero/compare/v0.24.0...v0.24.1) (2026-04-01)


### Bug Fixes

* address PR review comments on gen-migration skill ([8b895d2](https://github.com/MaxPayne89/klass-hero/commit/8b895d2fa496ffb3de67f6b22f363ed2290896ed)), closes [#573](https://github.com/MaxPayne89/klass-hero/issues/573)


### Performance Improvements

* enable interpreted compilation and parallel dep builds ([9a35e2e](https://github.com/MaxPayne89/klass-hero/commit/9a35e2e8b4ec2d1822b90c1b1416a18b4cac8944))

## [0.24.0](https://github.com/MaxPayne89/klass-hero/compare/v0.23.0...v0.24.0) (2026-04-01)


### Features

* add assign/unassign staff use cases with integration events ([#361](https://github.com/MaxPayne89/klass-hero/issues/361)) ([344363a](https://github.com/MaxPayne89/klass-hero/commit/344363a075d550b3b071480114644c095da50139))
* add messaging event handler for staff assignment changes ([#361](https://github.com/MaxPayne89/klass-hero/issues/361)) ([3437cdb](https://github.com/MaxPayne89/klass-hero/commit/3437cdb58506a7450016b6c5a1eeea5e449e0878))
* add messaging projection for program staff participants ([#361](https://github.com/MaxPayne89/klass-hero/issues/361)) ([993d25c](https://github.com/MaxPayne89/klass-hero/commit/993d25c2c023d591eb8e7d8401e545023b78296d))
* add program staff assignment domain model, port, and repository ([#361](https://github.com/MaxPayne89/klass-hero/issues/361)) ([ee90fd1](https://github.com/MaxPayne89/klass-hero/commit/ee90fd161da7786639c2fcc7f6efba51bc8c4a0e))
* add program_staff_assignments table and schema ([#361](https://github.com/MaxPayne89/klass-hero/issues/361)) ([4873104](https://github.com/MaxPayne89/klass-hero/commit/487310404f65fa3a759d33aec8a08f8cf984fada))
* add staff messaging routes and LiveViews ([#361](https://github.com/MaxPayne89/klass-hero/issues/361)) ([9285a7a](https://github.com/MaxPayne89/klass-hero/commit/9285a7ac969710fe9826436e104a45a4b82dbe02))
* allow assigned staff to send in broadcast conversations ([#361](https://github.com/MaxPayne89/klass-hero/issues/361)) ([157af45](https://github.com/MaxPayne89/klass-hero/commit/157af452e3b3a2216ea27e7e16ee49d0e1a6a993))
* allow program-assigned staff to message parents ([ae6750b](https://github.com/MaxPayne89/klass-hero/commit/ae6750b5cc1374527467e48543a88b6d1fe37bc1))
* auto-include assigned staff in new conversations ([#361](https://github.com/MaxPayne89/klass-hero/issues/361)) ([a6c73f5](https://github.com/MaxPayne89/klass-hero/commit/a6c73f5473753d559793e10ed65ad60b307c5da4))
* show provider-branded message attribution with staff names ([#361](https://github.com/MaxPayne89/klass-hero/issues/361)) ([693bca0](https://github.com/MaxPayne89/klass-hero/commit/693bca013705605e314f10e4063c3b15db93c841))


### Bug Fixes

* address PR review comments ([#571](https://github.com/MaxPayne89/klass-hero/issues/571)) ([2638727](https://github.com/MaxPayne89/klass-hero/commit/26387275014fab55709a1c7d1bf4d158d2fca4fc))
* resolve non-idempotent HEEx formatter issue in attribution span ([#361](https://github.com/MaxPayne89/klass-hero/issues/361)) ([6ec71cb](https://github.com/MaxPayne89/klass-hero/commit/6ec71cb70bb7364f7bf289edc8ed1fa06a60deff))


### Code Refactoring

* extract shared staff helper and reuse EctoErrorHelpers ([#361](https://github.com/MaxPayne89/klass-hero/issues/361)) ([bf8851c](https://github.com/MaxPayne89/klass-hero/commit/bf8851cdc389acbb8650c75a97474da90b9dbd63))
* move Ecto query from StaffAssignmentHandler into port/adapter ([#361](https://github.com/MaxPayne89/klass-hero/issues/361)) ([5e4228c](https://github.com/MaxPayne89/klass-hero/commit/5e4228ce27ae945c5caa9c4b05983bbbb5eef63d))

## [0.23.0](https://github.com/MaxPayne89/klass-hero/compare/v0.22.0...v0.23.0) (2026-03-31)


### Features

* add provider tier bypass and unlimited team seats ([8c06693](https://github.com/MaxPayne89/klass-hero/commit/8c06693aa2996f2e38ca09623e35f6d826e538c1))
* add provider tier bypass and unlimited team seats ([#294](https://github.com/MaxPayne89/klass-hero/issues/294)) ([cad7560](https://github.com/MaxPayne89/klass-hero/commit/cad75609c7a8aa4de7868375a16c130784f5bc23))


### Code Refactoring

* simplify bypass flag helpers and staff count syncing ([e1f43a7](https://github.com/MaxPayne89/klass-hero/commit/e1f43a78a918a399299deb4ede28114cea97beb0))

## [0.22.0](https://github.com/MaxPayne89/klass-hero/compare/v0.21.0...v0.22.0) (2026-03-31)


### Features

* add core span macro for deliberate adapter tracing ([ffa0069](https://github.com/MaxPayne89/klass-hero/commit/ffa006986b9414bf62992d6eae506d2563e79427)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)
* add LiveView on_mount hook for root spans ([55789a6](https://github.com/MaxPayne89/klass-hero/commit/55789a64cb578fb9f7e95e251d659633f73e1662)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)
* add trace context propagation for cross-process continuity ([0d13136](https://github.com/MaxPayne89/klass-hero/commit/0d13136c2287b48103849cc081faca238fae903c)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)
* add TracedWorker for Oban with context propagation ([192f33b](https://github.com/MaxPayne89/klass-hero/commit/192f33b8b62ce8ff806ea250253a7592e030b295)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)
* add Tracing.Plug for HTTP root spans ([a093046](https://github.com/MaxPayne89/klass-hero/commit/a093046c0a0b1895477f267fbe4538049cea490a)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)
* convert Oban workers to TracedWorker with context propagation ([d5a756c](https://github.com/MaxPayne89/klass-hero/commit/d5a756cc0be507a4de1157c466ab97317a264f1e)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)
* instrument all adapter boundaries with deliberate tracing ([00da55b](https://github.com/MaxPayne89/klass-hero/commit/00da55b46626b51195feb5c52eb292a3eaca3688)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)
* instrument exemplar adapters with deliberate tracing ([ac9f6e6](https://github.com/MaxPayne89/klass-hero/commit/ac9f6e6b68eb395ab2dc5141b313db8b891ed79a)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)
* integrate root spans into router pipelines and live sessions ([541b6d1](https://github.com/MaxPayne89/klass-hero/commit/541b6d156fddf783d457b62eb7425c2873979321)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)
* replace auto-instrumented OTel with deliberate adapter-only tracing ([00c7592](https://github.com/MaxPayne89/klass-hero/commit/00c7592a68cec06af9208bdaed5bc44fcf2c96e1))
* wire trace context into event publishing and subscribing ([ad1e925](https://github.com/MaxPayne89/klass-hero/commit/ad1e9254fc98df0f13bf5cf012bfe3be56f505f6)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)


### Bug Fixes

* harden tracing modules against OTel failures ([80763fb](https://github.com/MaxPayne89/klass-hero/commit/80763fbd0655d0965f9a670a97d2a8546d1210d2)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)


### Code Refactoring

* remove auto-instrumentation and configure 50% parent-based sampler ([dec21c0](https://github.com/MaxPayne89/klass-hero/commit/dec21c0c3b2d4403412da1935be7d8ee3450a258)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)
* simplify tracing modules — deduplicate noise segments and route lookup ([f4f2299](https://github.com/MaxPayne89/klass-hero/commit/f4f22993ffdb9d42748375b8f39f986c298017dd)), closes [#514](https://github.com/MaxPayne89/klass-hero/issues/514)

## [0.21.0](https://github.com/MaxPayne89/klass-hero/compare/v0.20.0...v0.21.0) (2026-03-30)


### Features

* add parent tier bypass via feature flag for early-adopter phase ([4273187](https://github.com/MaxPayne89/klass-hero/commit/4273187fc4722309b8789e253582fafe501c7656))
* add parent tier bypass via feature flag for early-adopter phase ([e6b5530](https://github.com/MaxPayne89/klass-hero/commit/e6b55301742d771209a84019e06d6607cf5dfda6)), closes [#513](https://github.com/MaxPayne89/klass-hero/issues/513)


### Code Refactoring

* move Entitlements into Shared bounded context ([f7d8daf](https://github.com/MaxPayne89/klass-hero/commit/f7d8dafe0b1ad74c3fda3187135c93995589712b))

## [0.20.0](https://github.com/MaxPayne89/klass-hero/compare/v0.19.0...v0.20.0) (2026-03-30)


### Features

* add action buttons and roster modal to staff dashboard ([29c4658](https://github.com/MaxPayne89/klass-hero/commit/29c465811fe358a95f05b0712f0412f4f39700d6))
* add staff sessions and participation routes with stub LiveViews ([e8802bf](https://github.com/MaxPayne89/klass-hero/commit/e8802bf1c7abf85320bacfef22107a43cfbf0de9))
* extend participation_card component to accept :staff role ([5561513](https://github.com/MaxPayne89/klass-hero/commit/5561513e183ece9e20804ea6087de4276f598637))
* implement StaffParticipationLive with check-in/check-out and behavioral notes ([bbb2f44](https://github.com/MaxPayne89/klass-hero/commit/bbb2f44b48bb277178c533783ec2133cad2d4a7f))
* implement StaffSessionsLive with date-based session management ([375f500](https://github.com/MaxPayne89/klass-hero/commit/375f50027ff9c5edbae51d1fc1cd8d7096d0e072))
* improve staff dashboard with sessions and participation management ([fc4c544](https://github.com/MaxPayne89/klass-hero/commit/fc4c544e70f23c2ff4415d3e09b68fd4ed91cd95))


### Bug Fixes

* narrow dashboard_path/1 catch-all to nil instead of any input ([5e9ec2c](https://github.com/MaxPayne89/klass-hero/commit/5e9ec2c4eb6fcba305cb5d6e489b74b25503dff1))
* route staff members to correct dashboard via role-aware navigation ([f4df925](https://github.com/MaxPayne89/klass-hero/commit/f4df9256b7f7ec941bcc86b05db0c3c2278b629b))
* route staff members to correct dashboard via role-aware navigation ([b13c98a](https://github.com/MaxPayne89/klass-hero/commit/b13c98a9fa72798055b16ebcd918979e287cad3f)), closes [#530](https://github.com/MaxPayne89/klass-hero/issues/530)


### Code Refactoring

* improve hook naming accuracy and add integration tests ([dfd7b39](https://github.com/MaxPayne89/klass-hero/commit/dfd7b395e833c086cbbdcc67ab5b6e32d63b687b))
* move staff program filtering to Provider domain layer ([37cf2ad](https://github.com/MaxPayne89/klass-hero/commit/37cf2ad88f3a727a8bcaed3630aeff3edb0d6a4c))
* simplify staff LiveViews — remove dead code and unused state ([65921c8](https://github.com/MaxPayne89/klass-hero/commit/65921c8a38f425b502158da3c9580816fe13fe00))

## [0.19.0](https://github.com/MaxPayne89/klass-hero/compare/v0.18.0...v0.19.0) (2026-03-29)


### Features

* add German translation for provider section heading ([34f7ba9](https://github.com/MaxPayne89/klass-hero/commit/34f7ba913b51e4bab2ee1995f4fdec1d004a05ae))


### Bug Fixes

* switch daily perf improver engine from copilot to claude-sonnet-4-6 ([9bb56e4](https://github.com/MaxPayne89/klass-hero/commit/9bb56e497a7205ad656c174f79c9a04e21cf6b66))
* switch daily perf improver engine from copilot to claude-sonnet-4-6 ([3b3ca8a](https://github.com/MaxPayne89/klass-hero/commit/3b3ca8ad0be40918a8c7b7fb059685e7639cb4ad)), closes [#518](https://github.com/MaxPayne89/klass-hero/issues/518)
* switch daily QA engine from copilot to claude-sonnet-4-6 ([b579afa](https://github.com/MaxPayne89/klass-hero/commit/b579afa30d2db4608289ad3e44bc644c82c0c2da))
* switch daily QA engine from copilot to claude-sonnet-4-6 ([dfac2c7](https://github.com/MaxPayne89/klass-hero/commit/dfac2c7d77844f7bb03304e5a13ab3980ccba94e)), closes [#516](https://github.com/MaxPayne89/klass-hero/issues/516)
* switch duplicate code detector engine from copilot to claude-sonnet-4-6 ([7732efe](https://github.com/MaxPayne89/klass-hero/commit/7732efedc8efb200a8746b8619c6c5fc934baa04))
* switch duplicate code detector engine from copilot to claude-sonnet-4-6 ([47eab7e](https://github.com/MaxPayne89/klass-hero/commit/47eab7ea8556a093124ae1d80fd63a7186ff17bc)), closes [#517](https://github.com/MaxPayne89/klass-hero/issues/517)


### Code Refactoring

* update provider section heading copy ([ef43fd6](https://github.com/MaxPayne89/klass-hero/commit/ef43fd6b2462e598023b01f0d9a55b6254961f86))
* update provider section heading to youth program copy ([3c16a46](https://github.com/MaxPayne89/klass-hero/commit/3c16a463b5eb817f01bf850260bcc7f58e3bfba0)), closes [#536](https://github.com/MaxPayne89/klass-hero/issues/536)

## [0.18.0](https://github.com/MaxPayne89/klass-hero/compare/v0.17.2...v0.18.0) (2026-03-28)


### Features

* add feature flag infrastructure via fun_with_flags ([5e77e47](https://github.com/MaxPayne89/klass-hero/commit/5e77e477ed679d339cf01d69ead35696d6bb182d))
* add feature flag infrastructure via fun_with_flags ([ed2a6b4](https://github.com/MaxPayne89/klass-hero/commit/ed2a6b4553d1457cc798e1234e03cb86257294b3)), closes [#327](https://github.com/MaxPayne89/klass-hero/issues/327)


### Code Refactoring

* remove redundant local variable in ReceiveInboundEmail ([b84c221](https://github.com/MaxPayne89/klass-hero/commit/b84c2215440d59dc10af959e12f8c0eb7286ba39))
* replace Messaging Repositories service locator with compile-time adapter resolution ([5f86871](https://github.com/MaxPayne89/klass-hero/commit/5f868719692e2dd9d4f28d27521b65770d1cfe40)), closes [#511](https://github.com/MaxPayne89/klass-hero/issues/511)
* replace Messaging Repositories service locator with compile-time resolution ([5156091](https://github.com/MaxPayne89/klass-hero/commit/51560913b071586b0da7a2b34d9cff5cb8d6d159))
* split ports and adapters into driven/driving directories ([1154999](https://github.com/MaxPayne89/klass-hero/commit/11549991d8ff1fdcfdcacd93b01f6ec89d24b71e))
* split ports and adapters into explicit driven/driving directories ([7c88c2f](https://github.com/MaxPayne89/klass-hero/commit/7c88c2fa1110ce9b9562fc97f3692cd2e4a2d945)), closes [#510](https://github.com/MaxPayne89/klass-hero/issues/510)

## [0.17.2](https://github.com/MaxPayne89/klass-hero/compare/v0.17.1...v0.17.2) (2026-03-27)


### Bug Fixes

* correct 23 wrong/fuzzy German translations in PO file ([13d3b3e](https://github.com/MaxPayne89/klass-hero/commit/13d3b3ecb793b6577a483edc410b054750a25472)), closes [#512](https://github.com/MaxPayne89/klass-hero/issues/512)
* wrap ~50 hardcoded English strings in gettext for i18n support ([021b4d7](https://github.com/MaxPayne89/klass-hero/commit/021b4d7cc0921e73592c47bcfb28c4193781c9b8)), closes [#512](https://github.com/MaxPayne89/klass-hero/issues/512)
* wrap hardcoded English strings in gettext for i18n ([e707233](https://github.com/MaxPayne89/klass-hero/commit/e707233c8f78386bf95bbac4343b8f4f71a53f00))

## [0.17.1](https://github.com/MaxPayne89/klass-hero/compare/v0.17.0...v0.17.1) (2026-03-27)


### Bug Fixes

* update inbound email test fixtures to use mail.klasshero.com subdomain ([11bc37b](https://github.com/MaxPayne89/klass-hero/commit/11bc37b370215565044a1619ee623e30f4ddfe43)), closes [#522](https://github.com/MaxPayne89/klass-hero/issues/522)
* use mail.klasshero.com subdomain for all contact email addresses ([806c9a5](https://github.com/MaxPayne89/klass-hero/commit/806c9a561b3eaa9c94619f23b90358eb5bddac9c))
* use mail.klasshero.com subdomain for all contact email addresses ([093f9dc](https://github.com/MaxPayne89/klass-hero/commit/093f9dc0e2caec834e545e7b7de53452816d83f3)), closes [#509](https://github.com/MaxPayne89/klass-hero/issues/509)

## [0.17.0](https://github.com/MaxPayne89/klass-hero/compare/v0.16.1...v0.17.0) (2026-03-27)


### Features

* add E2ECase, MessagingHelpers, and data-role test anchors ([b8f48f3](https://github.com/MaxPayne89/klass-hero/commit/b8f48f30dae0a1bffaac9e6ef2e88866af9c3b4a))
* add Wallaby dependency and E2E test infrastructure config ([d8e6f1b](https://github.com/MaxPayne89/klass-hero/commit/d8e6f1bded0ed8ad8e669335437d7cc16c8790a9))
* register Accounts integration events for durable Oban delivery ([ec7f4dd](https://github.com/MaxPayne89/klass-hero/commit/ec7f4dd6a0efd2a302eb9407c1d9cd1595501026))
* register Accounts integration events for durable Oban delivery ([902febe](https://github.com/MaxPayne89/klass-hero/commit/902febea710a3bcbe5d57ff0725e16975c5e48ae)), closes [#486](https://github.com/MaxPayne89/klass-hero/issues/486)
* role-aware post-confirmation redirect for providers ([e06503b](https://github.com/MaxPayne89/klass-hero/commit/e06503b4f1973ddc65a6de178a685eaa4a417d0f))
* role-aware post-confirmation redirect for providers ([1868730](https://github.com/MaxPayne89/klass-hero/commit/18687306ad63bf41df9ed44e8fdc700c4783b668)), closes [#485](https://github.com/MaxPayne89/klass-hero/issues/485)


### Bug Fixes

* add user_agent to socket connect_info and move sandbox plug to top of pipeline ([6b912a9](https://github.com/MaxPayne89/klass-hero/commit/6b912a94a9661f9dab5a7438058a4210136fd062))
* build assets and add --no-sandbox for E2E in CI ([1a05e55](https://github.com/MaxPayne89/klass-hero/commit/1a05e55b977dadb62df03e24ec0c956570c63ca4))
* redirect staff_provider users to staff dashboard after login ([5a0a4fc](https://github.com/MaxPayne89/klass-hero/commit/5a0a4fc986e2fde1d753ca87da1d153288e5222b))
* redirect staff_provider users to staff dashboard after login ([e4c1d66](https://github.com/MaxPayne89/klass-hero/commit/e4c1d66292a1fc4151241e0a2bed44f4fcc0f08e)), closes [#503](https://github.com/MaxPayne89/klass-hero/issues/503)
* set CHROME_BROWSER env in CI to match chromedriver version ([bfb321a](https://github.com/MaxPayne89/klass-hero/commit/bfb321a25a6a4d5fcb255c6fced10c82dbb84cf8))
* use CSS selector for login button to avoid text match issues ([ab93130](https://github.com/MaxPayne89/klass-hero/commit/ab9313036254aa296994c12f37d04a8909c8d0ad))
* use nanasess/setup-chromedriver for version-matched ChromeDriver in CI ([f4c9f3d](https://github.com/MaxPayne89/klass-hero/commit/f4c9f3dd7db94351a179160f783b0e135c262ee9))


### Code Refactoring

* extract shared E2E setup and remove duplication ([9f2860d](https://github.com/MaxPayne89/klass-hero/commit/9f2860de5238b236710fcd50e04b1aeb89bbf702))
* remove redundant guard and add test-drive report ([30f9584](https://github.com/MaxPayne89/klass-hero/commit/30f95844465761dda6b615a1ecc97eb14714997a))

## [0.16.1](https://github.com/MaxPayne89/klass-hero/compare/v0.16.0...v0.16.1) (2026-03-26)


### Bug Fixes

* tighten oban version constraint to ~&gt; 2.21 ([e21ea22](https://github.com/MaxPayne89/klass-hero/commit/e21ea222ee2a71812d237ba3094e01d65f76eabd))

## [0.16.0](https://github.com/MaxPayne89/klass-hero/compare/v0.15.0...v0.16.0) (2026-03-25)


### Features

* add :staff_provider role resolution to Scope ([3cb04aa](https://github.com/MaxPayne89/klass-hero/commit/3cb04aa2bc34cfea7f2da10366af61374019ed99))
* add :staff_provider role to UserRole system ([3221ec2](https://github.com/MaxPayne89/klass-hero/commit/3221ec2f722dc3bbb3813e8267366a7686645cf9))
* add :staff_provider routing and auth mount hook ([4728d51](https://github.com/MaxPayne89/klass-hero/commit/4728d5198144b96e39a84e98ad3cb8e7be9e6c37))
* add integration event factories for staff invitation saga ([c27431b](https://github.com/MaxPayne89/klass-hero/commit/c27431b10c6a72da47a5e8247898290563179717))
* add invitation fields to staff member persistence layer ([cb9f2ec](https://github.com/MaxPayne89/klass-hero/commit/cb9f2ec6828315504290dd3502f581a4ef012d39))
* add invitation fields to staff_members table ([a704636](https://github.com/MaxPayne89/klass-hero/commit/a704636f55d8086e2a439680e767ef3f33273fb0))
* add invitation state machine to StaffMember domain model ([bc7cdc2](https://github.com/MaxPayne89/klass-hero/commit/bc7cdc29363389589763af9e8d2ced2b8866b9f7))
* add invitation status display and resend flow to team UI ([8823652](https://github.com/MaxPayne89/klass-hero/commit/8823652960fb1a92979669f29a83c512a77986c6))
* add minimal staff dashboard LiveView ([bd6e532](https://github.com/MaxPayne89/klass-hero/commit/bd6e532e38267af309d67e96059aa4f0ca57319f))
* add staff invitation and notification email templates ([9340228](https://github.com/MaxPayne89/klass-hero/commit/9340228c272d2826492740ea1bbe8b390d3c3cf6))
* add staff invitation registration LiveView ([e507900](https://github.com/MaxPayne89/klass-hero/commit/e507900ca1fb523335acd437d670d93055a59418))
* add staff invitation saga for automatic provider account creation ([ad79298](https://github.com/MaxPayne89/klass-hero/commit/ad792984c247ff2c55e0977eb67a57243115f5bc))
* add staff_registration_changeset and register_staff_user facade ([0282ee5](https://github.com/MaxPayne89/klass-hero/commit/0282ee54de1907ea6c3bd3b36946d6eac0d613e1))
* generate invitation token and emit event on staff member creation ([0a65a15](https://github.com/MaxPayne89/klass-hero/commit/0a65a15b7fedb43d869708fd8f2a45860208750b))
* implement provider-side staff invitation status handler ([be62b28](https://github.com/MaxPayne89/klass-hero/commit/be62b2897f4cf350169b5baf7fc621ec9e5c2c0c))
* implement StaffInvitationHandler for accounts context ([51dd590](https://github.com/MaxPayne89/klass-hero/commit/51dd590655b781d390b62d1534af879b98ae1ced))
* wire staff invitation saga event subscribers and critical handlers ([3ed82ca](https://github.com/MaxPayne89/klass-hero/commit/3ed82ca71d86d2f0dd25d70338313deb3a2f9b7b))


### Bug Fixes

* address architecture review findings for staff invitation saga ([17eea48](https://github.com/MaxPayne89/klass-hero/commit/17eea4890d85daa715ac4c8c9bdcd510d8073442))
* address PR review comments ([adb07e2](https://github.com/MaxPayne89/klass-hero/commit/adb07e2565e494892298ef3eae9ddbe2d96302f2)), closes [#498](https://github.com/MaxPayne89/klass-hero/issues/498)
* harden event payload handling and improve error differentiation ([0093593](https://github.com/MaxPayne89/klass-hero/commit/0093593bb826ceda352aef8d4a71b08b8b0037ff))
* remove cross-context belongs_to and add emit failure compensation ([6b9c901](https://github.com/MaxPayne89/klass-hero/commit/6b9c9018a0742a69b32383757282c9fe1a8dba6e))
* resolve boundary violations in staff invitation email handling ([ba5ec8f](https://github.com/MaxPayne89/klass-hero/commit/ba5ec8f0e3f62c62f534afd4cc3749ab087e49b0))


### Code Refactoring

* add Accounts facade for staff changeset and fill test gaps ([087b649](https://github.com/MaxPayne89/klass-hero/commit/087b649ac615cc8334cc370f4897e874505391c5))
* simplify staff invitation saga after code review ([211f95d](https://github.com/MaxPayne89/klass-hero/commit/211f95d93bc628d2af5147092db76249cf965552))
* simplify staff invitation saga code ([9224962](https://github.com/MaxPayne89/klass-hero/commit/9224962438abe1577cc584e98d3a015cd70c999c))

## [0.15.0](https://github.com/MaxPayne89/klass-hero/compare/v0.14.0...v0.15.0) (2026-03-21)


### Features

* add content status handling, reply list, and form clearing to admin emails ([418bed2](https://github.com/MaxPayne89/klass-hero/commit/418bed214dc4e3143f487e7ccf744174d1c7b7c0))
* add email reply persistence layer (schema, mapper, queries, repo) ([1f8122d](https://github.com/MaxPayne89/klass-hero/commit/1f8122db68dbbc23e1201e6878719b7c87db534b))
* add EmailReply domain model and InboundEmail content fields ([2b1b3ed](https://github.com/MaxPayne89/klass-hero/commit/2b1b3ed7ff6efe0b4937f9e302003665c587dacf))
* add migration for email content status and replies ([e74b412](https://github.com/MaxPayne89/klass-hero/commit/e74b412e0ecb5e6656dcfd9ed29fbd97a3e4112a))
* add Oban email job scheduler adapter ([5229b58](https://github.com/MaxPayne89/klass-hero/commit/5229b587f72d1208f739f8ff753f051e4e319749))
* add Oban workers for email content fetch and reply delivery ([8209312](https://github.com/MaxPayne89/klass-hero/commit/82093120943e912a69ef18e43438feea33ffe7ce))
* add ports for email content fetching, reply management, and job scheduling ([b09554e](https://github.com/MaxPayne89/klass-hero/commit/b09554e9d882a8f527ea0ceb00c12f6078f66b95))
* add Resend email content adapter with Req HTTP client ([cddb588](https://github.com/MaxPayne89/klass-hero/commit/cddb588e52240efec2caaa14e8c1eaaddee51b1c))
* add update_content to inbound email persistence layer ([13579d7](https://github.com/MaxPayne89/klass-hero/commit/13579d7cc202662736605923b0ce72992cb5dbb3))
* enqueue content fetch after receiving inbound email ([793abfe](https://github.com/MaxPayne89/klass-hero/commit/793abfe803e01dd3eb7c353ff21909493a328df7))
* extract message_id from webhook payload for email threading ([dfb2f1b](https://github.com/MaxPayne89/klass-hero/commit/dfb2f1b1c9e0dbadd88ca17904eff3e21368eb40))
* wire new ports into config, repositories, and messaging facade ([a9feac3](https://github.com/MaxPayne89/klass-hero/commit/a9feac38282f9d4db2971eb1910d84522cb051ab))


### Bug Fixes

* address architecture review findings ([e14efb6](https://github.com/MaxPayne89/klass-hero/commit/e14efb6a5962d15bd7c346bd7c0d5de0ed6df3c0))
* address PR review comments ([f0416cb](https://github.com/MaxPayne89/klass-hero/commit/f0416cb98c31ad0c77e2835fdf95c1e5a2bd25bd)), closes [#494](https://github.com/MaxPayne89/klass-hero/issues/494)
* fetch email content from Resend API, persist replies, and thread responses ([24f6862](https://github.com/MaxPayne89/klass-hero/commit/24f686224a62e53b2cb49cad00a1045c8f3d141b))
* include headers in content_changeset with array-of-maps test data ([41090ba](https://github.com/MaxPayne89/klass-hero/commit/41090baf43f00b9f86ab0420a5a0919e70e8f21d))


### Code Refactoring

* address architecture review suggestions ([0caeaac](https://github.com/MaxPayne89/klass-hero/commit/0caeaacebeffa6b9174d6aaa070543595dd9bc8b))
* ReplyToEmail now persists reply and enqueues async delivery ([092abbc](https://github.com/MaxPayne89/klass-hero/commit/092abbc44856688ee11ce0e8bca33447845bb985))
* simplify admin email code after review ([a45a62c](https://github.com/MaxPayne89/klass-hero/commit/a45a62c669493f5670b909d9176e2f1bb6c4af8c))

## [0.14.0](https://github.com/MaxPayne89/klass-hero/compare/v0.13.0...v0.14.0) (2026-03-20)


### Features

* add admin emails LiveView with inbox, detail, and reply ([09a2d8e](https://github.com/MaxPayne89/klass-hero/commit/09a2d8e14432457313e18fc31000f6d071f9bab4))
* add inbound email receiving via Resend webhooks ([42c9a72](https://github.com/MaxPayne89/klass-hero/commit/42c9a72901df8ce1abdffda736f7b87174710f9b))
* add VERIFY_WEBHOOK_SIGNATURE env var for dev server testing ([fac8bd6](https://github.com/MaxPayne89/klass-hero/commit/fac8bd6630d990821d8b5704ee4e8e865a60b53f))


### Bug Fixes

* address PR review comments ([08f77b6](https://github.com/MaxPayne89/klass-hero/commit/08f77b6c879459ee02e789206a27131b27dd24d2)), closes [#489](https://github.com/MaxPayne89/klass-hero/issues/489)


### Code Refactoring

* consolidate filter handlers, use input component, add interaction tests ([590fad8](https://github.com/MaxPayne89/klass-hero/commit/590fad8686d4f95e7e2377bf28f674518c0f61cf))
* delegate mark-read logic to domain model, add Boundary export ([cae7567](https://github.com/MaxPayne89/klass-hero/commit/cae75672c64296a7d663d4ee8b4a8d0b066cc797))
* fix credo strict issues — flatten nesting, inline logger metadata ([752eefa](https://github.com/MaxPayne89/klass-hero/commit/752eefa9a03032fb26bd4c017ba661c97b9b9e14))
* remove tautological guard in InboundEmail.validate_list ([0fc0a39](https://github.com/MaxPayne89/klass-hero/commit/0fc0a39ae2dfdbe59e4fad2bd4e3f3a6d6f7913b))

## [0.13.0](https://github.com/MaxPayne89/klass-hero/compare/v0.12.0...v0.13.0) (2026-03-20)


### Features

* add address-pr-comments skill ([c41f38c](https://github.com/MaxPayne89/klass-hero/commit/c41f38c829a58bd56c44c796640ea51ac06c9cec))
* add user_confirmed integration event factory ([8188f54](https://github.com/MaxPayne89/klass-hero/commit/8188f54f59d72e90d8bbb5769a9c7be9ba5d985b))
* enrich user_confirmed event with name, roles, and tier ([7f44f13](https://github.com/MaxPayne89/klass-hero/commit/7f44f136607954044bfda4e3148e3cdf62936d23))
* FamilyEventHandler subscribes to user_confirmed ([9ff5373](https://github.com/MaxPayne89/klass-hero/commit/9ff5373055476f72dc1dc6c8425cadc36744c425))
* promote user_confirmed to integration event ([955db18](https://github.com/MaxPayne89/klass-hero/commit/955db1885f154ac0887d3856a2dd7dd39ba81439))
* ProviderEventHandler subscribes to user_confirmed ([cc0a114](https://github.com/MaxPayne89/klass-hero/commit/cc0a11412c01ee2d2eb756b8e55d88c7b10362a9))


### Bug Fixes

* address PR review comments ([d978fdd](https://github.com/MaxPayne89/klass-hero/commit/d978fdd4543479102b0ca197008b22ab8afbed0f)), closes [#487](https://github.com/MaxPayne89/klass-hero/issues/487)
* mark user_confirmed domain event as critical ([4bc173c](https://github.com/MaxPayne89/klass-hero/commit/4bc173ca672c85639f2aea5e5ccbdd31db2e7eb7))
* persist provider_subscription_tier as real DB column ([5912839](https://github.com/MaxPayne89/klass-hero/commit/59128390b039dbc721d36bf9e5ec08edca93efbc)), closes [#484](https://github.com/MaxPayne89/klass-hero/issues/484)
* provider registration creates family account instead ([#484](https://github.com/MaxPayne89/klass-hero/issues/484)) ([dbd410e](https://github.com/MaxPayne89/klass-hero/commit/dbd410e3035f1d49e6e243a93762cbfa5d96fc47))


### Code Refactoring

* extract assert_eventually to shared DataCase helper ([729a99c](https://github.com/MaxPayne89/klass-hero/commit/729a99c676d945234e492b78c743dcf6140360ae))

## [0.12.0](https://github.com/MaxPayne89/klass-hero/compare/v0.11.0...v0.12.0) (2026-03-19)


### Features

* add EnrolledChildrenResolver ACL adapter ([#471](https://github.com/MaxPayne89/klass-hero/issues/471)) ([d6d8394](https://github.com/MaxPayne89/klass-hero/commit/d6d8394d88c33c7db41800454072c180a962caa3))
* add ForResolvingEnrolledChildren port ([#471](https://github.com/MaxPayne89/klass-hero/issues/471)) ([255a6cd](https://github.com/MaxPayne89/klass-hero/commit/255a6cd7d9ae97f68ee3672d0b4be802d43c6abf))
* add roster_seeded domain and integration events ([#471](https://github.com/MaxPayne89/klass-hero/issues/471)) ([e032c97](https://github.com/MaxPayne89/klass-hero/commit/e032c975591443c93ffe989eb8fb56d00b484ebf))
* add seed_batch/2 with ON CONFLICT DO NOTHING ([#471](https://github.com/MaxPayne89/klass-hero/issues/471)) ([4e3286c](https://github.com/MaxPayne89/klass-hero/commit/4e3286c2056e9e069ef2438c8257cad00434e7ba))
* add SeedSessionRoster use case ([#471](https://github.com/MaxPayne89/klass-hero/issues/471)) ([ecf4f26](https://github.com/MaxPayne89/klass-hero/commit/ecf4f268b8f0067362fc4533982737ea7947b4f5))
* add SeedSessionRosterHandler + wire into supervision tree ([#471](https://github.com/MaxPayne89/klass-hero/issues/471)) ([6572212](https://github.com/MaxPayne89/klass-hero/commit/657221285873e237cc9f5099785a4021a92af193))


### Bug Fixes

* add validation clauses to roster_seeded integration event factory ([#471](https://github.com/MaxPayne89/klass-hero/issues/471)) ([5973f3e](https://github.com/MaxPayne89/klass-hero/commit/5973f3ea488bdfc090d6c0e62f6f63738d730b78))
* address PR review findings — tests and dispatch error handling ([#471](https://github.com/MaxPayne89/klass-hero/issues/471)) ([65ecb2d](https://github.com/MaxPayne89/klass-hero/commit/65ecb2de5d7fc9975ad03a97a0e3b714cb04629d))
* remove unused participant_count variable after credo refactor ([8b57b31](https://github.com/MaxPayne89/klass-hero/commit/8b57b3100442e9f2796bf4b459c40e960a646734))
* seed session roster with enrolled children on creation ([c6578d4](https://github.com/MaxPayne89/klass-hero/commit/c6578d4d599efaddc50b1c83d1c5a760362a121e))
* separate error handling for seeding vs event dispatch ([#471](https://github.com/MaxPayne89/klass-hero/issues/471)) ([58e7c2f](https://github.com/MaxPayne89/klass-hero/commit/58e7c2f1de111f3a8c210e2648ca7130679f3271))


### Code Refactoring

* resolve all credo --strict warnings and suggestions ([5e4f209](https://github.com/MaxPayne89/klass-hero/commit/5e4f2098930e6761740a59076445f61b292bed82))

## [0.11.0](https://github.com/MaxPayne89/klass-hero/compare/v0.10.0...v0.11.0) (2026-03-19)


### Features

* add ForResolvingProgramProvider ACL port ([#464](https://github.com/MaxPayne89/klass-hero/issues/464)) ([1e54ae0](https://github.com/MaxPayne89/klass-hero/commit/1e54ae0ec190ad84fc9a6929d7c5b8a0c6d011ef))
* add ProgramProviderResolver ACL adapter ([#464](https://github.com/MaxPayne89/klass-hero/issues/464)) ([869dcef](https://github.com/MaxPayne89/klass-hero/commit/869dcefac021ffb9c3e0720eeeb0061e740bdd50))
* enrich attendance event payloads with program_id ([#464](https://github.com/MaxPayne89/klass-hero/issues/464)) ([815347d](https://github.com/MaxPayne89/klass-hero/commit/815347d6d416bd76e6d0207bf686d5acb10eab5d))
* pass session to attendance event factories for payload enrichment ([#464](https://github.com/MaxPayne89/klass-hero/issues/464)) ([134c898](https://github.com/MaxPayne89/klass-hero/commit/134c898e9fb4eb20dd57085b589f2b5052817582))
* publish participation events to provider-specific PubSub topics ([#464](https://github.com/MaxPayne89/klass-hero/issues/464)) ([37401ad](https://github.com/MaxPayne89/klass-hero/commit/37401ad88853c118c9690a06ba27f12a2cb3ed23))
* rebuild CQRS projections after seeding write tables ([4674c35](https://github.com/MaxPayne89/klass-hero/commit/4674c35eb54df6d33bf637f9bdc287bba6b51bef))
* rebuild CQRS projections after seeding write tables ([2d328e1](https://github.com/MaxPayne89/klass-hero/commit/2d328e14135cc6098e29a0e0fdc41e5ec730225b)), closes [#465](https://github.com/MaxPayne89/klass-hero/issues/465)
* subscribe SessionsLive to provider-specific PubSub topic ([#464](https://github.com/MaxPayne89/klass-hero/issues/464)) ([943f4ae](https://github.com/MaxPayne89/klass-hero/commit/943f4ae238d1086a1f99b82dc1627d80c3973b86))


### Bug Fixes

* address PR review comments on [#469](https://github.com/MaxPayne89/klass-hero/issues/469) ([09f1e5c](https://github.com/MaxPayne89/klass-hero/commit/09f1e5c6f9893506230375ea94d835caed893ae3))
* address PR review comments on [#479](https://github.com/MaxPayne89/klass-hero/issues/479) ([8e67f99](https://github.com/MaxPayne89/klass-hero/commit/8e67f99727f23cb50c47f3a1cdbc6979f4bf3388))
* address PR review comments on [#480](https://github.com/MaxPayne89/klass-hero/issues/480) ([76bf5de](https://github.com/MaxPayne89/klass-hero/commit/76bf5deb4f8dd8da2beb82b1541b427632f07a96))
* make event enrichment best-effort to prevent false failures ([#464](https://github.com/MaxPayne89/klass-hero/issues/464)) ([064eff6](https://github.com/MaxPayne89/klass-hero/commit/064eff6366496cc19c634d6eeed104be5ba3dd46))
* remove orphaned Task.async in DashboardLive mount ([c390247](https://github.com/MaxPayne89/klass-hero/commit/c390247ec1c00d8b33dcf6f5f10470d6450cf4d8))
* use registered Logger metadata keys in SessionsLive.load_sessions ([#464](https://github.com/MaxPayne89/klass-hero/issues/464)) ([4d63f15](https://github.com/MaxPayne89/klass-hero/commit/4d63f1578475d540bfa48ee12ff2f5751302a31b))


### Code Refactoring

* fix N+1 session fetch in BulkCheckIn, remove repetitive comments ([#464](https://github.com/MaxPayne89/klass-hero/issues/464)) ([d3b126e](https://github.com/MaxPayne89/klass-hero/commit/d3b126e8a2dd84e72fd9cc90e8c6ca209d1b1f3f))
* migrate SessionsLive PubSub to provider-specific topic routing ([96dfbb9](https://github.com/MaxPayne89/klass-hero/commit/96dfbb9f414dba10513276e81e69e5aa3bdc5a7a))
* remove orphaned Task.async in DashboardLive mount ([e4114f7](https://github.com/MaxPayne89/klass-hero/commit/e4114f7fc2f841fb7d36660e79b6694e5d8a0deb))

## [0.10.0](https://github.com/MaxPayne89/klass-hero/compare/v0.9.0...v0.10.0) (2026-03-19)


### Features

* add Sessions tab to provider dashboard navigation ([31ebe5a](https://github.com/MaxPayne89/klass-hero/commit/31ebe5ae669baaca241e2d054bb75d0148dec530))
* add Sessions tab to provider dashboard navigation ([dd5d95a](https://github.com/MaxPayne89/klass-hero/commit/dd5d95a808de96fa02b2932c7f7d6301b362e5bb))


### Code Refactoring

* consolidate redundant sessions navigation tests ([153e291](https://github.com/MaxPayne89/klass-hero/commit/153e291833bbc9683a51554ddb526d83f2b83039))

## [0.9.0](https://github.com/MaxPayne89/klass-hero/compare/v0.8.2...v0.9.0) (2026-03-18)


### Features

* add create session route and modal shell ([4efc58f](https://github.com/MaxPayne89/klass-hero/commit/4efc58f8a6ce116a1efbd41600d1f13b0d0708dd))
* add create-issue skill ([c414744](https://github.com/MaxPayne89/klass-hero/commit/c414744359a7ce04567adef403681104842abfbc))
* add create-issue skill for turning findings into GitHub issues ([3457372](https://github.com/MaxPayne89/klass-hero/commit/3457372d201bbfe7f31229c6634b7f483a5bdbf6))
* add date filtering for session_created events and Create Session button ([b712a16](https://github.com/MaxPayne89/klass-hero/commit/b712a16d79d419d6ce3730d27c0975881de139b0))
* add form fields and program pre-fill to create session modal ([0e66f13](https://github.com/MaxPayne89/klass-hero/commit/0e66f134adf44c7804c9d488e2ac267f270a28cd))
* add ParticipationIntegrationEvents factory for cross-context event promotion ([bbd794f](https://github.com/MaxPayne89/klass-hero/commit/bbd794fea77a1c084d04841264c2bbff0effa33e))
* add PromoteIntegrationEvents handler for Participation context ([7b34182](https://github.com/MaxPayne89/klass-hero/commit/7b341821d4ea68e2334fb85dec681c9a2db66382))
* expose session creation in provider Sessions LiveView ([4a1b004](https://github.com/MaxPayne89/klass-hero/commit/4a1b004f65fedb9cb4138bea63b9fc43508c7dfd))
* implement create session form submission with validation ([985991d](https://github.com/MaxPayne89/klass-hero/commit/985991d915bd81f20764e7d7e107387612154b27))


### Bug Fixes

* address PR review comments on [#466](https://github.com/MaxPayne89/klass-hero/issues/466) ([7bc226f](https://github.com/MaxPayne89/klass-hero/commit/7bc226ffc403bb482d83504c7a3a001e1737b910))
* correct PubSub subscriptions, message format, and stream shape in SessionsLive ([f6ba571](https://github.com/MaxPayne89/klass-hero/commit/f6ba571fd57a3b424fc0b386a331a8f902ceaf06))


### Code Refactoring

* simplify SessionsLive after code review ([eb095fd](https://github.com/MaxPayne89/klass-hero/commit/eb095fd1133a5d46fdf4d9c6cdab9af55ae93f67))

## [0.8.2](https://github.com/MaxPayne89/klass-hero/compare/v0.8.1...v0.8.2) (2026-03-18)


### Bug Fixes

* address PR review — widen broadcast spec, use real event structs in tests ([fd657be](https://github.com/MaxPayne89/klass-hero/commit/fd657bee17af465555d58f789c8a044563753dbd))
* address PR review comments on [#458](https://github.com/MaxPayne89/klass-hero/issues/458) ([4b73de4](https://github.com/MaxPayne89/klass-hero/commit/4b73de4aeaf9b786698f33fbffc12d1ace60c23d))
* address PR review comments on [#460](https://github.com/MaxPayne89/klass-hero/issues/460) ([cf2a1b7](https://github.com/MaxPayne89/klass-hero/commit/cf2a1b7cb27ab800f40090f9d63e34416cb9fa58))
* resolve merge conflict markers in agentic workflow files ([69faf6d](https://github.com/MaxPayne89/klass-hero/commit/69faf6da894ca6815970af74e6ee26039fad7913))
* update rules with correct references and current state ([a20f1fc](https://github.com/MaxPayne89/klass-hero/commit/a20f1fc22e923bc7adb067b784810064a0c21b7d))
* use Mermaid alias syntax for participant names with parentheses ([99c8c5f](https://github.com/MaxPayne89/klass-hero/commit/99c8c5fd93350ad25359ed22e429916f2dd0670e))


### Code Refactoring

* deduplicate EventPublishing and IntegrationEventPublishing ([a151f84](https://github.com/MaxPayne89/klass-hero/commit/a151f8431c2db65ba7318db7d8af14af2437a907))
* deduplicate EventPublishing and IntegrationEventPublishing ([5bed30e](https://github.com/MaxPayne89/klass-hero/commit/5bed30eaa6b2b2febaa584f5da18a9cda4519220)), closes [#385](https://github.com/MaxPayne89/klass-hero/issues/385)
* extract fetch_verification_docs/1 helper in DashboardLive ([e8c5379](https://github.com/MaxPayne89/klass-hero/commit/e8c53794da20d44ddbc902490fc27da37b98d0a7))
* extract fetch_verification_docs/1 helper in DashboardLive ([444d94a](https://github.com/MaxPayne89/klass-hero/commit/444d94a9dcb512fdf9fe5ba4f35216a99d4451a0)), closes [#376](https://github.com/MaxPayne89/klass-hero/issues/376)
* extract shared PubSubBroadcaster from event publishers ([7443037](https://github.com/MaxPayne89/klass-hero/commit/74430375e029e9d467569bc1f751e277db4a0259))
* extract shared PubSubBroadcaster from event publishers ([#445](https://github.com/MaxPayne89/klass-hero/issues/445)) ([b2ca574](https://github.com/MaxPayne89/klass-hero/commit/b2ca574f35cfed2b3d2dacbb0140f0ee4bda7c1c))

## [0.8.1](https://github.com/MaxPayne89/klass-hero/compare/v0.8.0...v0.8.1) (2026-03-17)


### Bug Fixes

* add broadcast_id and direct_conversation_id to Logger metadata ([e978115](https://github.com/MaxPayne89/klass-hero/commit/e97811543ad1d51efbff469ed1e1d5002a7c86d1))
* address PR review comments on [#448](https://github.com/MaxPayne89/klass-hero/issues/448) ([256d7d4](https://github.com/MaxPayne89/klass-hero/commit/256d7d423532c7f05726e9c8fdc233316ca9898a))
* resolve 4 production error tracker entries ([2667afa](https://github.com/MaxPayne89/klass-hero/commit/2667afa73d01c97d447074a517b88f6660b67a7b))
* resolve 4 production error tracker entries ([29282b5](https://github.com/MaxPayne89/klass-hero/commit/29282b5681994a2e35764ae412916525a2fa3db8))


### Code Refactoring

* use structural pattern matching for rate limit detection ([407003b](https://github.com/MaxPayne89/klass-hero/commit/407003bec8a8a15f4f25c892d8d93bc8e1368ee3))

## [0.8.0](https://github.com/MaxPayne89/klass-hero/compare/v0.7.0...v0.8.0) (2026-03-16)


### Features

* **messaging:** add ConversationSummaryQueries with system note lookup ([f81062f](https://github.com/MaxPayne89/klass-hero/commit/f81062fde06780c45ad3a17525ced3d46cfecc69))
* **messaging:** add has_system_note? and write_system_note_token ([528cbb6](https://github.com/MaxPayne89/klass-hero/commit/528cbb665d5cf06ee53640f24d3fd81e3e127fc2))
* **messaging:** add system_notes JSONB column with GIN index ([4e6a25c](https://github.com/MaxPayne89/klass-hero/commit/4e6a25cd842597ceb95c4ac93e65d5555a98cb11))
* **messaging:** bootstrap system_notes from existing system messages ([343b623](https://github.com/MaxPayne89/klass-hero/commit/343b6234e4727a4320a180d7cee803228ddce126))
* **messaging:** project system note tokens into JSONB on message_sent ([4839a69](https://github.com/MaxPayne89/klass-hero/commit/4839a6915002048adc2837705969bc1a0c910543))


### Bug Fixes

* **messaging:** address PR review — JSONB merge on conflict + idempotent timestamps ([6576a19](https://github.com/MaxPayne89/klass-hero/commit/6576a190a345c9e051a91a3528774725af8ecfb6))
* **messaging:** exclude soft-deleted messages from bootstrap system notes ([91f6734](https://github.com/MaxPayne89/klass-hero/commit/91f673451ab3a4dbf885c7c2a8700f923e881fde))
* **messaging:** harden error handling in system note write-through ([2238bb3](https://github.com/MaxPayne89/klass-hero/commit/2238bb322534a370d9891e88cb05dec6eb64045f))
* **messaging:** replace 100-message dedup ceiling with projection lookup ([1ca58c7](https://github.com/MaxPayne89/klass-hero/commit/1ca58c7f131dc620c5f9321ac148a72c2c04f721))
* **messaging:** restore seed fallback in write_system_note_token ([d958f17](https://github.com/MaxPayne89/klass-hero/commit/d958f17eba1c62e1cf1b359ba495ef761fdd9627))
* **messaging:** validate conversation ID match in SendMessage fast-path ([7006710](https://github.com/MaxPayne89/klass-hero/commit/70067108014532f959a0ecc87d52962fedd567f7))
* replace 100-message dedup ceiling with projection lookup ([189d671](https://github.com/MaxPayne89/klass-hero/commit/189d671ddf437bb29df4fe0d503ea376f4c78532))


### Performance Improvements

* **messaging:** skip conversation DB fetch in SendMessage when caller provides it ([d6e74c3](https://github.com/MaxPayne89/klass-hero/commit/d6e74c37357f93e65260259de41a10ea4d842216))
* **messaging:** skip conversation DB fetch in SendMessage when caller provides it ([9f8ca30](https://github.com/MaxPayne89/klass-hero/commit/9f8ca30721039477bd0a6c2158fcd94b37f75357)), closes [#430](https://github.com/MaxPayne89/klass-hero/issues/430)


### Code Refactoring

* accept optional log metadata in check_entitlement ([82b4892](https://github.com/MaxPayne89/klass-hero/commit/82b4892856d855e67357b1a306a6ae95f9511eab))
* extract check_entitlement into Shared module ([24a59e5](https://github.com/MaxPayne89/klass-hero/commit/24a59e5f94b17e4cd4355aacfb03eb771c0bb6fe)), closes [#432](https://github.com/MaxPayne89/klass-hero/issues/432)
* extract duplicate check_entitlement into Shared module ([76edd60](https://github.com/MaxPayne89/klass-hero/commit/76edd60b189f5fa1da1c888a7a9db3b9e5176591))
* extract verify_participant into Shared module ([da19197](https://github.com/MaxPayne89/klass-hero/commit/da1919752835e4bb7bbc092c2cc91fb9ca7fe569))
* extract verify_participant into Shared module ([6240ffc](https://github.com/MaxPayne89/klass-hero/commit/6240ffc97acc39d77df40557fed0d0231ddb4e13)), closes [#436](https://github.com/MaxPayne89/klass-hero/issues/436)
* **messaging:** simplify system note dedup projection ([ff33282](https://github.com/MaxPayne89/klass-hero/commit/ff33282404c3fd6acadc65ab1540cca485ccff2c))

## [0.7.0](https://github.com/MaxPayne89/klass-hero/compare/v0.6.0...v0.7.0) (2026-03-15)


### Features

* add account overview to admin dashboard ([6ae5481](https://github.com/MaxPayne89/klass-hero/commit/6ae54810f8e0ea3aef3aac22656f55e5d0550686))
* add admin dashboard link to app navigation ([4121f40](https://github.com/MaxPayne89/klass-hero/commit/4121f40af922f5398431072d6d484adeb28cec9a))
* add admin dashboard with Backpex user management ([e7d5a6c](https://github.com/MaxPayne89/klass-hero/commit/e7d5a6c58efd24e1b97d8fd7c3067f40049ef236))
* add admin layout with Backpex app shell ([47d660f](https://github.com/MaxPayne89/klass-hero/commit/47d660f55148b2c4200a4464d62a6e898799d331))
* add admin sessions LiveView with today mode and roster display ([5c78eca](https://github.com/MaxPayne89/klass-hero/commit/5c78ecaddd7e5e5812a6fbb4d5e5b0f701ab3b8b))
* add admin sessions route and sidebar item ([5240ea1](https://github.com/MaxPayne89/klass-hero/commit/5240ea18b626ffcb94abcdb5eba6557f20932939))
* add admin_changeset to ProviderProfileSchema ([8b413d6](https://github.com/MaxPayne89/klass-hero/commit/8b413d62b515a9c8b25473cbcf1679c660e5a98d))
* add admin_changeset/3 to StaffMemberSchema ([#339](https://github.com/MaxPayne89/klass-hero/issues/339)) ([7d7ce76](https://github.com/MaxPayne89/klass-hero/commit/7d7ce7645d151bacc43d4d9b834e3db36f811c77))
* add admin_correct/2 to ParticipationRecord for admin corrections ([df62dc8](https://github.com/MaxPayne89/klass-hero/commit/df62dc8ff33366ad7736363cd58495fd3ef39ee8))
* add Admin.Queries.list_providers_for_select/0 ([8f19a70](https://github.com/MaxPayne89/klass-hero/commit/8f19a70179942d66e179fb5380d9471811353b0c))
* add Backpex admin routes and User LiveResource ([3296807](https://github.com/MaxPayne89/klass-hero/commit/3296807077b61544808a074258ec3f5a9200c101))
* add Backpex ThemeSelectorPlug to browser pipeline ([d9bdfb5](https://github.com/MaxPayne89/klass-hero/commit/d9bdfb5e38783168911434b4f4e3f2ea91c59978))
* add bookings admin dashboard with cancel action ([4afb68f](https://github.com/MaxPayne89/klass-hero/commit/4afb68fb87f374d401295f9fa48939059be47735))
* add broadcast button to roster modal ([1cee319](https://github.com/MaxPayne89/klass-hero/commit/1cee319d7cecdf8cbb2d40700352f4fe3e263fba))
* add broadcast button to roster modal with disabled state ([3f80dee](https://github.com/MaxPayne89/klass-hero/commit/3f80dee6a4849e36c9dd4ffe7c1926869849237b)), closes [#317](https://github.com/MaxPayne89/klass-hero/issues/317)
* add bulk parent profile lookup by IDs to Family context ([de8082d](https://github.com/MaxPayne89/klass-hero/commit/de8082d33654c61457607cdd6fb96de0e3303c7f))
* add change_subscription_tier/2 to Provider facade ([00dce82](https://github.com/MaxPayne89/klass-hero/commit/00dce8239d60e8a2fd267dc78b7461761eedbba3))
* add change_tier/2 to ProviderProfile domain model ([afb555c](https://github.com/MaxPayne89/klass-hero/commit/afb555c52ffbc99a58a93e1e98cb42dab9f28071))
* add ChangeSubscriptionTier use case ([302366b](https://github.com/MaxPayne89/klass-hero/commit/302366b7f8a3065d8d880afa0b24ef36e7fa905d))
* add CheckProviderVerificationStatus domain event handler ([fbd5d5e](https://github.com/MaxPayne89/klass-hero/commit/fbd5d5ed819bfa540ee06369536852f289bde650))
* add ConsentStatusFilter for admin consents ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([7599a8a](https://github.com/MaxPayne89/klass-hero/commit/7599a8a7117021eca937d554c731cdbdd97e6ddc))
* add ConsentTypeFilter for admin consents ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([35ee8a4](https://github.com/MaxPayne89/klass-hero/commit/35ee8a414c62f6a24a68703fca949374d89bdfac))
* add CorrectAttendance use case for admin attendance fixes ([a5fca75](https://github.com/MaxPayne89/klass-hero/commit/a5fca75cfbba39af6f3bf28bd179783eed114ab2))
* add CriticalEventDispatcher with handler_ref/1 ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([9cb3f36](https://github.com/MaxPayne89/klass-hero/commit/9cb3f36bfd344d30c05a35e45024c05312d0db65))
* add CriticalEventDispatcher.execute/3 with transactional idempotency ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([e45d33b](https://github.com/MaxPayne89/klass-hero/commit/e45d33bd6d5d72c68aae1e61fdc01279125f058e))
* add CriticalEventDispatcher.mark_processed/2 ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([73c30fa](https://github.com/MaxPayne89/klass-hero/commit/73c30fac05f3271b2c78adb68ef6dfcf775d5e4e))
* add CriticalEventHandlerRegistry and critical_events Oban queue ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([e8ffddd](https://github.com/MaxPayne89/klass-hero/commit/e8ffddd13dc88e9874426315d2fde2664a3813d5))
* add CriticalEventSerializer for event struct JSON round-trip ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([c245af5](https://github.com/MaxPayne89/klass-hero/commit/c245af57e4464d8826422bf40d154ac009f097e4))
* add CriticalEventWorker Oban worker for durable event delivery ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([b15fb0b](https://github.com/MaxPayne89/klass-hero/commit/b15fb0b9c34d667a1d069c1576696339f99c7469))
* add DomainEventBus.dispatch_critical/2 with per-handler identity ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([2691fff](https://github.com/MaxPayne89/klass-hero/commit/2691fff54280e6da2beda9be46eabdfc2feb77c2))
* add dual delivery for critical integration events in PubSubIntegrationEventPublisher ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([a834341](https://github.com/MaxPayne89/klass-hero/commit/a8343416073ad87e5e5a4d7168291d3862b5c821))
* add empty state message to admin sessions list ([9a9d017](https://github.com/MaxPayne89/klass-hero/commit/9a9d01775cf4dd2c425069c3c0149ae9859e732e))
* add empty state message to admin sessions list ([5e35d83](https://github.com/MaxPayne89/klass-hero/commit/5e35d83b4af403779cecddcbe5612dc593027d06))
* add ForResolvingParentInfo ACL port and adapter ([b334fac](https://github.com/MaxPayne89/klass-hero/commit/b334facdb81747d4deb46e9ab3365be213e956b8))
* add German translations for admin sessions dashboard ([aad0c3b](https://github.com/MaxPayne89/klass-hero/commit/aad0c3b681a7e811d20a5aa9629b4358eb79d810))
* add has_one associations for parent/provider profiles on User schema ([837d138](https://github.com/MaxPayne89/klass-hero/commit/837d138ce13105408490108b40bd1d88c2a24887))
* add list_admin_sessions/1 with enriched data for admin dashboard ([13b562a](https://github.com/MaxPayne89/klass-hero/commit/13b562a7a5fcbeaef0503d2266bc65383e96baf1))
* add Oban Web dashboard with admin-only access ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([0d1b8e0](https://github.com/MaxPayne89/klass-hero/commit/0d1b8e070601e8384a7aa5f71ba117783147ced4))
* add participation session management to admin dashboard ([b8b7f20](https://github.com/MaxPayne89/klass-hero/commit/b8b7f206e9153de6e585f86e22d23a35dd642e0b))
* add persistent critical events with exactly-once delivery ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([ba73d12](https://github.com/MaxPayne89/klass-hero/commit/ba73d12c8a43ba21d28c0b385c94cd6ee35ba240))
* add processed_events table and schema for critical event idempotency ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([95f2771](https://github.com/MaxPayne89/klass-hero/commit/95f277105027bb8eebff9e3440b95c89f0de3868))
* add ProcessInviteClaim use case for serialized invite processing ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([62c6707](https://github.com/MaxPayne89/klass-hero/commit/62c6707259117fbb1bdc0dc4239d2e0685f379d0))
* add ProcessInviteClaimWorker with serialized queue processing ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([a593c3c](https://github.com/MaxPayne89/klass-hero/commit/a593c3c11b25caa727de6dee480668ffc8a9811c))
* add provider profiles Backpex admin resource ([9aa9bc4](https://github.com/MaxPayne89/klass-hero/commit/9aa9bc404b5eb5f25bc6e1677625afb82f273cdf)), closes [#338](https://github.com/MaxPayne89/klass-hero/issues/338)
* add provider profiles to admin dashboard ([bb058ac](https://github.com/MaxPayne89/klass-hero/commit/bb058aca7c257bbd6d41a3c47598b8cbb717bbf5))
* add provider subscription management page ([58e07fc](https://github.com/MaxPayne89/klass-hero/commit/58e07fc17f5bf43f6d76aa97417e3dfe890d0d58))
* add providers link to admin sidebar ([cac9f66](https://github.com/MaxPayne89/klass-hero/commit/cac9f660d91eb2ff8e1825e93bc597ee02b59734))
* add read-only admin consent overview with Backpex ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([8195263](https://github.com/MaxPayne89/klass-hero/commit/81952630c8112c9edfd4b27b37accdd0ba3ea15b))
* add read-only admin consents overview ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([1bf091d](https://github.com/MaxPayne89/klass-hero/commit/1bf091d98a7e7fcebd0636d37470c0ee865a3e3d))
* add roles badges to admin account overview ([d3dc31f](https://github.com/MaxPayne89/klass-hero/commit/d3dc31f8a79a8aa9a0f734f614614846ebd27b2c))
* add SearchableSelect LiveComponent with basic rendering ([49943af](https://github.com/MaxPayne89/klass-hero/commit/49943af4fdb12be2cc7577c286a0218a43fe7670))
* add send individual message button to roster modal ([c35f843](https://github.com/MaxPayne89/klass-hero/commit/c35f8434223b4e44a15a90ecb502bb2a42effd47))
* add send message button to roster with entitlement gating ([9e097a6](https://github.com/MaxPayne89/klass-hero/commit/9e097a64f04ed3824b14ab4354c10cf429b517be))
* add skeleton Trust & Safety page with route and test ([#250](https://github.com/MaxPayne89/klass-hero/issues/250)) ([74cc92e](https://github.com/MaxPayne89/klass-hero/commit/74cc92e284090472164a6ee80454fd552998c4f8))
* add staff members to admin dashboard ([f743a2b](https://github.com/MaxPayne89/klass-hero/commit/f743a2bdf24501b34abda52dfe6c4a788716da50))
* add staff members to admin dashboard ([#339](https://github.com/MaxPayne89/klass-hero/issues/339)) ([edbd3db](https://github.com/MaxPayne89/klass-hero/commit/edbd3dba52a03b227683ba935897a1222f985096))
* add subscription CTA banner to provider dashboard ([562e038](https://github.com/MaxPayne89/klass-hero/commit/562e038891e8212c05ef5fc681b162e7b0958789))
* add subscription tier badges to admin account overview ([2b3e048](https://github.com/MaxPayne89/klass-hero/commit/2b3e0489de0baf033678912a868c63ba9b96e557))
* add subscription upgrade path for providers ([cf7ed19](https://github.com/MaxPayne89/klass-hero/commit/cf7ed198aae24faf1ab18820ce5b97bbd5dc0096))
* add tier selector to provider registration flow ([5fa952d](https://github.com/MaxPayne89/klass-hero/commit/5fa952db590b648d2ccc8325c29c970524d641bc))
* add Trust & Safety links to navbar, sidebar, and footer ([#250](https://github.com/MaxPayne89/klass-hero/issues/250)) ([cd5fea5](https://github.com/MaxPayne89/klass-hero/commit/cd5fea534bd2c21f14249a9e3c5523725e7e8272))
* add Trust & Safety page ([#250](https://github.com/MaxPayne89/klass-hero/issues/250)) ([453b726](https://github.com/MaxPayne89/klass-hero/commit/453b7260949e8cd077606abd7bcfadbe8fa35bc3))
* **admin:** add BookingLive Backpex resource with cancel action and status filter ([13c1a52](https://github.com/MaxPayne89/klass-hero/commit/13c1a526bc6653f505de981b059d5b0f9faf11b5))
* **admin:** add CancelBookingAction item action with reason modal ([5fe264d](https://github.com/MaxPayne89/klass-hero/commit/5fe264d9c057973eeb1d3a3c49470f1064437eb1))
* **admin:** add StatusFilter for enrollment status filtering ([0d383e4](https://github.com/MaxPayne89/klass-hero/commit/0d383e418b6df19f1aa47344f46073e1325882cf))
* dispatch domain event on document approval ([061f539](https://github.com/MaxPayne89/klass-hero/commit/061f539e545b8fa2cfbbfd8f8321fdf6d2e6be35))
* dispatch domain event on document rejection ([950ba80](https://github.com/MaxPayne89/klass-hero/commit/950ba80227c4ddefdc467cdf13a1b368d7551146))
* **enrollment:** add belongs_to associations and admin_changeset to EnrollmentSchema ([c60485f](https://github.com/MaxPayne89/klass-hero/commit/c60485ff09112b53522e1ae961283fef12c425d3))
* **enrollment:** add CancelEnrollmentByAdmin use case with event dispatch ([5a74e49](https://github.com/MaxPayne89/klass-hero/commit/5a74e498b20c2a28ea927ffb19c2161cba479031))
* **enrollment:** add enrollment_cancelled domain event factory ([87fd2a1](https://github.com/MaxPayne89/klass-hero/commit/87fd2a1b86ecbb17e58505bdfbb62fa3266b30c6))
* **enrollment:** add enrollment_cancelled integration event factory ([cc1a05c](https://github.com/MaxPayne89/klass-hero/commit/cc1a05c123227be2f801086ac8bb1227c2c00fc5))
* **enrollment:** add update/2 to enrollment port and repository ([4c8907a](https://github.com/MaxPayne89/klass-hero/commit/4c8907ae47130f9964b5c8e72eb679cc0442c8c6))
* **enrollment:** promote enrollment_cancelled to integration event ([942c3f0](https://github.com/MaxPayne89/klass-hero/commit/942c3f0261be221bd32fa09adad1bf0808212f24))
* expose list_admin_sessions through participation context facade ([b6707b9](https://github.com/MaxPayne89/klass-hero/commit/b6707b98d2f5dea3cdda1ae0dd9d31aac46de8c7))
* **family:** add enrollment cleanup ACL for child deletion ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([324dfd1](https://github.com/MaxPayne89/klass-hero/commit/324dfd1f550acb95a5f5adaba76e6ed3970c2a9e))
* **family:** add participation cleanup ACL for child deletion ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([ed0907b](https://github.com/MaxPayne89/klass-hero/commit/ed0907bbc9ef63a9056810eaf0d6fe4447e5e917))
* **family:** add PrepareChildDeletion use case ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([b927914](https://github.com/MaxPayne89/klass-hero/commit/b9279142239bc8bd06b0b6576366835b304b678c))
* **family:** handle cross-context cleanup in DeleteChild ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([6582629](https://github.com/MaxPayne89/klass-hero/commit/65826293a784b7dd723788a530a27c43ab2ba687))
* finalize admin account overview field layout ([0ceede0](https://github.com/MaxPayne89/klass-hero/commit/0ceede0d17b56deea6e30dadf1ba065264a1fd2f))
* fix broadcast reply privacy — parents can no longer expose replies to group ([6409033](https://github.com/MaxPayne89/klass-hero/commit/6409033d5f5dd8c26fc63d5036ddfff535f0e698))
* fix categories display and add verified filter ([3c1b5d5](https://github.com/MaxPayne89/klass-hero/commit/3c1b5d539e7df0415e9d4d9f8e18f5e3dc8d5fdf))
* implement full Trust & Safety page content ([#250](https://github.com/MaxPayne89/klass-hero/issues/250)) ([ccc40a5](https://github.com/MaxPayne89/klass-hero/commit/ccc40a57eeb044c02d2e970d9d57b8f0be43eb91))
* include parent_id and parent_user_id in roster entries ([0c8303f](https://github.com/MaxPayne89/klass-hero/commit/0c8303ffe0334a3baf3dd0706d28aa6bb592bdef))
* integrate Backpex CSS sources and JS hooks ([91c8810](https://github.com/MaxPayne89/klass-hero/commit/91c8810442170bf8a52a6af130cf191b04fb41f6))
* **liveview:** two-step child deletion with enrollment warning ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([567e3a0](https://github.com/MaxPayne89/klass-hero/commit/567e3a04bfd22d867a3826173d1c592c5671d253))
* **messaging-ui:** add broadcast_reply_bar and conditional rendering ([8961c6f](https://github.com/MaxPayne89/klass-hero/commit/8961c6fef50ae15a8ea5bbca6939901ecf3cf584))
* **messaging:** add get_user_id_for_provider/1 to ForResolvingUsers port ([67cd06c](https://github.com/MaxPayne89/klass-hero/commit/67cd06c25dc14b21afc0782e424e987f57081f8e))
* **messaging:** add ReplyPrivatelyToBroadcast use case ([cecfe22](https://github.com/MaxPayne89/klass-hero/commit/cecfe22cd059f7fa4460e17e38e1cad029d463fb))
* **messaging:** add skip_entitlement_check opt to CreateDirectConversation ([e7f1943](https://github.com/MaxPayne89/klass-hero/commit/e7f1943b0833f5c70fa0c2b958c8bc1ae275b8a6))
* **messaging:** expose reply_privately_to_broadcast on facade ([b49b77a](https://github.com/MaxPayne89/klass-hero/commit/b49b77ab025dac1e0e85a4623ef5d6ef8be65e0f))
* **messaging:** inject reply_privately event handler in LiveView helper ([60428d8](https://github.com/MaxPayne89/klass-hero/commit/60428d851b6c0055b0abf6d39e0fc8c2858efb43))
* pass subscription tier through registration event to provider creation ([cd4d190](https://github.com/MaxPayne89/klass-hero/commit/cd4d19086163684a0bf81f2a49606abf3a3117d6))
* publish domain event on subscription tier change ([a7b4968](https://github.com/MaxPayne89/klass-hero/commit/a7b4968e53d66f6267e0dcaff57c5ae3784361ed))
* publish domain event on subscription tier change ([#271](https://github.com/MaxPayne89/klass-hero/issues/271)) ([53f3e10](https://github.com/MaxPayne89/klass-hero/commit/53f3e10a19901c6619bded3614b7d1ab8b6b5275))
* rebrand instructor section to Hero terminology ([4caa119](https://github.com/MaxPayne89/klass-hero/commit/4caa119a463069ab4236968264c8bba8f776e92b))
* rebrand instructor section to Hero terminology ([bf05af8](https://github.com/MaxPayne89/klass-hero/commit/bf05af8ee6d9dcefccb8bce5e47a283cdc523e0f)), closes [#297](https://github.com/MaxPayne89/klass-hero/issues/297)
* register verification status handlers on Provider DomainEventBus ([3c08d87](https://github.com/MaxPayne89/klass-hero/commit/3c08d870db772ee48a6507007e2a8f49569584b0))
* render cover image in program detail hero with gradient fallback ([99b45b3](https://github.com/MaxPayne89/klass-hero/commit/99b45b35ba0b5ce7011ff3614470ca4ee0bc4f1d))
* render cover image on program card with gradient fallback ([b8b28b6](https://github.com/MaxPayne89/klass-hero/commit/b8b28b6eeceb798c256230252bb924e1e0c08ecf)), closes [#196](https://github.com/MaxPayne89/klass-hero/issues/196)
* replace mode toggle with unified filter bar in admin sessions ([c9720b8](https://github.com/MaxPayne89/klass-hero/commit/c9720b8d4537f3023e5af6d019f2a8a6422d2b48))
* standardize font usage across all pages ([932a3bc](https://github.com/MaxPayne89/klass-hero/commit/932a3bcce83c52f8594a07c4bd3292ce7ba1ac61))
* standardize font usage across all pages ([#347](https://github.com/MaxPayne89/klass-hero/issues/347)) ([76cb706](https://github.com/MaxPayne89/klass-hero/commit/76cb7064b6bf7740a10a6f01fbcd6e88581d252a))
* update homepage FAQ content (`[#312](https://github.com/MaxPayne89/klass-hero/issues/312)`) ([28a3314](https://github.com/MaxPayne89/klass-hero/commit/28a33142e5b0292bfdb4fa83e4c21175e50194a5))
* update homepage FAQ content per issue [#312](https://github.com/MaxPayne89/klass-hero/issues/312) ([e6662ea](https://github.com/MaxPayne89/klass-hero/commit/e6662ea1f994901ac7b76d5176eeb0d7025a5252))
* update provider vetting to 6-step process across all pages ([98d7879](https://github.com/MaxPayne89/klass-hero/commit/98d78794ad278ddad36ae6d4563775abd47279ca))
* update provider vetting to 6-step process across all pages ([#251](https://github.com/MaxPayne89/klass-hero/issues/251)) ([dfd757e](https://github.com/MaxPayne89/klass-hero/commit/dfd757e87ec9e6f95bd097270009dc1fa80ee0d0))
* wire critical domain events through CriticalEventDispatcher in EventDispatchHelper ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([8b7208f](https://github.com/MaxPayne89/klass-hero/commit/8b7208f8710a70affa840f1e1f3baae14bd2468d))
* wrap critical integration events in CriticalEventDispatcher in EventSubscriber ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([24508e0](https://github.com/MaxPayne89/klass-hero/commit/24508e0cff3b9567aecb2dc27eef0b7ba16c5565))


### Bug Fixes

* add :warning flash kind to fix silently swallowed warnings ([7fb7697](https://github.com/MaxPayne89/klass-hero/commit/7fb76975adf037e671ea2e0e96dcb6cfc1fec085))
* add active-state feedback to provider dashboard buttons ([3a212ee](https://github.com/MaxPayne89/klass-hero/commit/3a212eeb88b22213e3982f1e8e98447d0e3b98b5))
* add active-state press feedback to provider dashboard buttons ([b7e30b6](https://github.com/MaxPayne89/klass-hero/commit/b7e30b6a0c3c72350705d4242e5d4eebeecd9930)), closes [#143](https://github.com/MaxPayne89/klass-hero/issues/143)
* add case-collision detection and gettext field labels in CSV import ([58869f8](https://github.com/MaxPayne89/klass-hero/commit/58869f846f3a7660e830e09594535b87658b02a9))
* add Consents link to admin sidebar navigation ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([9e66a20](https://github.com/MaxPayne89/klass-hero/commit/9e66a2085ff41da5aa2ff53483192ba65ea201fa))
* add contents read permission to Security workflow ([f7f01d2](https://github.com/MaxPayne89/klass-hero/commit/f7f01d2936512c7f36fc29d77424abcf6235719a))
* add DB connection pool resilience for Fly.io suspend/resume ([4ffd420](https://github.com/MaxPayne89/klass-hero/commit/4ffd4202dab33807de21e9e8a9fabf1c72c3a1e6))
* add DB connection pool resilience for Fly.io suspend/resume ([6bb4129](https://github.com/MaxPayne89/klass-hero/commit/6bb41291e047f7d4421bfd129dca8bada3179ce2)), closes [#395](https://github.com/MaxPayne89/klass-hero/issues/395)
* add error handling and observability for child deletion ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([af78e18](https://github.com/MaxPayne89/klass-hero/commit/af78e18ec9586441087b9b280d7dd7ce1669a791))
* add security-events write permission to Security workflow ([e17d85f](https://github.com/MaxPayne89/klass-hero/commit/e17d85f03c468687d9b6c93064a7db9907fbedba))
* add security-events write permission to Security workflow ([4605aef](https://github.com/MaxPayne89/klass-hero/commit/4605aefb815a03c574a6bcc78382e57984035a73)), closes [#268](https://github.com/MaxPayne89/klass-hero/issues/268)
* address architecture review findings for child deletion ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([4b4f860](https://github.com/MaxPayne89/klass-hero/commit/4b4f8601f32fd87b073087d46c4199e535d177e5))
* address Copilot PR review comments ([ce73fca](https://github.com/MaxPayne89/klass-hero/commit/ce73fca5d465227644fd38a3615db01ae39d1d5a))
* address Copilot PR review comments ([#1](https://github.com/MaxPayne89/klass-hero/issues/1), [#2](https://github.com/MaxPayne89/klass-hero/issues/2), [#3](https://github.com/MaxPayne89/klass-hero/issues/3), [#7](https://github.com/MaxPayne89/klass-hero/issues/7)) ([f89a0e2](https://github.com/MaxPayne89/klass-hero/commit/f89a0e2bfac3629bbff0f774431e9f8e27da9cec))
* address critical architecture review findings ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([780bc54](https://github.com/MaxPayne89/klass-hero/commit/780bc549ce3426e6c8335c7aa99413b188ca9a65))
* address critical PR review issues (C1-C3) ([1999748](https://github.com/MaxPayne89/klass-hero/commit/19997481ffef7f9bcec11a3a61265388b4d2a544))
* address important review findings for invite claim processing ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([f2e41a2](https://github.com/MaxPayne89/klass-hero/commit/f2e41a276a670903c01c252fab4a79e1258157ea))
* address PR [#252](https://github.com/MaxPayne89/klass-hero/issues/252) review comments ([18d2f64](https://github.com/MaxPayne89/klass-hero/commit/18d2f6424aa3be59ab6bbe307a10060cbc4f5276))
* address PR [#304](https://github.com/MaxPayne89/klass-hero/issues/304) review comments for child deletion ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([de6e214](https://github.com/MaxPayne89/klass-hero/commit/de6e214c02a4840361c394fed600ad3da0f6ef1a))
* address PR [#324](https://github.com/MaxPayne89/klass-hero/issues/324) accessibility and HTML validity review comments ([0368979](https://github.com/MaxPayne89/klass-hero/commit/036897987a1bb0d1721684c11e237146fd5cf55a))
* address PR review - test use cases directly instead of facade ([6e81c5e](https://github.com/MaxPayne89/klass-hero/commit/6e81c5e571a7ab8aa790859d598ae086e35d1c87))
* address PR review — add filter tests, fix test names, update spec ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([012dd9d](https://github.com/MaxPayne89/klass-hero/commit/012dd9dfd99c30592e758eb8a6748c62acd19a7d))
* address PR review — add tier error display and use shared test helper ([8f02fb9](https://github.com/MaxPayne89/klass-hero/commit/8f02fb9e34579347073ad629d5eececd766dc8b4))
* address PR review — extract shared helper and add enrollment summary tests ([978b0ab](https://github.com/MaxPayne89/klass-hero/commit/978b0ab91af39ed1b58b72e6ebb452781763d657))
* address PR review — guard tier functions and fix i18n in format_media ([b0708e2](https://github.com/MaxPayne89/klass-hero/commit/b0708e23a6144845cdb4ab65fa51c75bccd5697a))
* address PR review — misleading comment and missing assertion ([9ead52e](https://github.com/MaxPayne89/klass-hero/commit/9ead52e34084a3841e3b52df054eb0ec71270287))
* address PR review — typespecs accuracy ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([79444b9](https://github.com/MaxPayne89/klass-hero/commit/79444b97932a370c162c44a7c5e0efcd427e5288))
* address PR review comments for get_by_ids/1 ([c368027](https://github.com/MaxPayne89/klass-hero/commit/c36802704dea2be508de31574d79573a486bf11c))
* address PR review comments for invite claim processing ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([73e5161](https://github.com/MaxPayne89/klass-hero/commit/73e51615cd2e3a865887b58945f1e4af11f3259f))
* address PR review comments for vetting steps ([#251](https://github.com/MaxPayne89/klass-hero/issues/251)) ([10644e8](https://github.com/MaxPayne89/klass-hero/commit/10644e83c768c9fdc4f950cd637ebe75ae5d7be6))
* address PR review comments on concurrent enrollment test ([e36e4b7](https://github.com/MaxPayne89/klass-hero/commit/e36e4b7b9bc041b9532dc475e3cd3b2ecda7566e))
* address PR review comments on lint_typography ([59d6a8f](https://github.com/MaxPayne89/klass-hero/commit/59d6a8f07fcdd070ebbde6618b3cddc9b8b71a5d))
* address PR review comments on ReferralCodeGenerator tests ([ce5cba1](https://github.com/MaxPayne89/klass-hero/commit/ce5cba1d6c55fe1c22bb9ae5820cc131a86af701))
* address PR review suggestions (S11-S15) ([c388a2e](https://github.com/MaxPayne89/klass-hero/commit/c388a2e0357256f29b6ca8b8ddd963261a8a9e8c))
* address PR review suggestions for child deletion ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([e51960f](https://github.com/MaxPayne89/klass-hero/commit/e51960f03e5088f578f95a6a306c199fb60bdc0c))
* address suggestion-level review findings ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([0a7636f](https://github.com/MaxPayne89/klass-hero/commit/0a7636f9b15aeb36f9865aad8071419047752926))
* **admin:** add Bookings sidebar nav link and shorten date format ([57d1d40](https://github.com/MaxPayne89/klass-hero/commit/57d1d4061bb72e24804aecd74c112f90021a4c43))
* **admin:** propagate event dispatch errors and improve cancel action feedback ([87a311b](https://github.com/MaxPayne89/klass-hero/commit/87a311b3a14a6aebd649361d89fe501dfa2abd99))
* align security workflow with Elixir 1.20.0-rc.3 and OTP 28.4 ([d4f6442](https://github.com/MaxPayne89/klass-hero/commit/d4f64426732e271b471af1397638fc9ebb9a9d3f))
* align test names with assertions in dashboard tests ([0e8e866](https://github.com/MaxPayne89/klass-hero/commit/0e8e86610b531ae314269a6085d95bd1acbc74f5))
* allow minor version bumps for feat commits in pre-1.0 ([de4c12c](https://github.com/MaxPayne89/klass-hero/commit/de4c12c427f4daba8faa601ba3816a790006d97e))
* allow minor version bumps for feat commits in pre-1.0 ([768c2a2](https://github.com/MaxPayne89/klass-hero/commit/768c2a2e3beeca94bfe0419fde9921e51824bba2))
* auto-verify/unverify provider on document review ([3b3a306](https://github.com/MaxPayne89/klass-hero/commit/3b3a306ee0af8d730cf780e86e5fdbd2e1a7ebc5))
* cast binary UUIDs to string in remediation script output ([5ae1b76](https://github.com/MaxPayne89/klass-hero/commit/5ae1b76cd8773468db8203786603c7e6a546cb42))
* cast binary UUIDs to string in remediation script output ([3aeb7d7](https://github.com/MaxPayne89/klass-hero/commit/3aeb7d7eef08ccdaa479c42690957277bc757132))
* clear textarea after sending message ([5c8169f](https://github.com/MaxPayne89/klass-hero/commit/5c8169f0fffa080725a86d2a1381a46e3c0ea441))
* consolidate nil fallback and untrack beads backup artifacts ([14d2c3b](https://github.com/MaxPayne89/klass-hero/commit/14d2c3bee11c99d255c831a0e5acfaa31c6c2fe8))
* correct changeset error assertions in ParticipantPolicyForm tests ([c288a1e](https://github.com/MaxPayne89/klass-hero/commit/c288a1eae173cc04c3ed7237e0f0a0288b777e35))
* display cover image on program cards and detail page ([22a12ae](https://github.com/MaxPayne89/klass-hero/commit/22a12ae05fd461179dcb72671a34fca95a1fc3be))
* display featured programs using data-driven component ([c8dfebd](https://github.com/MaxPayne89/klass-hero/commit/c8dfebdbad95b1797745122734372ec7b1b42481))
* **enrollment:** address PR review findings ([#195](https://github.com/MaxPayne89/klass-hero/issues/195)) ([49a6716](https://github.com/MaxPayne89/klass-hero/commit/49a6716e8281cc800a3601111ac55f7449dd66f5))
* **enrollment:** remove adapter-layer dependency from CancelEnrollmentByAdmin ([1c2e77c](https://github.com/MaxPayne89/klass-hero/commit/1c2e77c47c66fa190b1f33a00c0d0d90c1527894))
* **enrollment:** remove silent nil fallback on program.price ([#195](https://github.com/MaxPayne89/klass-hero/issues/195)) ([631e3da](https://github.com/MaxPayne89/klass-hero/commit/631e3da3bca11cc4b8c869bd39e83a125cf5dace))
* **enrollment:** simplify pricing to use program.price directly ([#195](https://github.com/MaxPayne89/klass-hero/issues/195)) ([5a53b0d](https://github.com/MaxPayne89/klass-hero/commit/5a53b0d0e57c3e16c500420d73a8485db1bdf0c0))
* **enrollment:** use program.price directly as total ([#195](https://github.com/MaxPayne89/klass-hero/issues/195)) ([053fb26](https://github.com/MaxPayne89/klass-hero/commit/053fb26ad225356cd68337df3a792f17e416b86e))
* **enrollment:** validate non-empty reason in CancelEnrollmentByAdmin ([36d3378](https://github.com/MaxPayne89/klass-hero/commit/36d3378d99ef81a522b88bd4e2e9a2c08d00da36))
* export Admin.Queries from KlassHero boundary ([c6b0fc4](https://github.com/MaxPayne89/klass-hero/commit/c6b0fc40dc5a35eecf48a5115183ed73e408f737))
* export shared NotifyLiveViews from Shared boundary ([3c05883](https://github.com/MaxPayne89/klass-hero/commit/3c05883ab4a9cfea794348d9866f45d138669664))
* guard against nil delete_candidate in confirm handler ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([077fc96](https://github.com/MaxPayne89/klass-hero/commit/077fc96373c1570d9bd42f9eed76c9255ee36b4c))
* handle BOM, case-insensitive programs, and error labels in CSV import ([e0def48](https://github.com/MaxPayne89/klass-hero/commit/e0def4847ff6f2283ee6677bc080dc6ca1817665))
* handle BOM, case-insensitive programs, and error labels in CSV import ([caafdf5](https://github.com/MaxPayne89/klass-hero/commit/caafdf51a17712f45485f8397df1ac1731f15922)), closes [#243](https://github.com/MaxPayne89/klass-hero/issues/243)
* handle HH:MM:SS time format in program save ([b4d17dc](https://github.com/MaxPayne89/klass-hero/commit/b4d17dc1a0f2f6129d2e58bbd9f5bbf41fe24932))
* handle HH:MM:SS time format in program save ([#282](https://github.com/MaxPayne89/klass-hero/issues/282)) ([3e85491](https://github.com/MaxPayne89/klass-hero/commit/3e854912d62f645a9fe8bc5ce6054b4ac90d03bd))
* handle nil other_participant_name in conversation_card component ([70c13a6](https://github.com/MaxPayne89/klass-hero/commit/70c13a670f920f310c08f6fff3c26c26707a7b58))
* handle nil other_participant_name in conversation_card component ([787510e](https://github.com/MaxPayne89/klass-hero/commit/787510e88b4cacf9e3a0534f09eae2f125d5d861)), closes [#241](https://github.com/MaxPayne89/klass-hero/issues/241)
* harden admin consent view — nil parent render, catch-all filter, tighter tests ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([e47af47](https://github.com/MaxPayne89/klass-hero/commit/e47af476ca6d3e6c82d61b5506badcd894df5909))
* harden dashboard mount resilience and fix misleading param name ([a440150](https://github.com/MaxPayne89/klass-hero/commit/a44015040c6d7f9ef549a977754174dc94d14902))
* harden error handling, logging, and test coverage for critical events ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([31d1437](https://github.com/MaxPayne89/klass-hero/commit/31d14374c4c3f2fd3f1b7695c2faa8e0b19cc438))
* hide age range row in program card when nil ([059cc2b](https://github.com/MaxPayne89/klass-hero/commit/059cc2b5082939c742961208f74da2fde4b0a335))
* hide provider field from staff member edit form ([55f9f37](https://github.com/MaxPayne89/klass-hero/commit/55f9f3729e0ae9e560b12b5188dac16b19f7712c))
* improve docs, error messages, and test coverage for critical events ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([017b8b1](https://github.com/MaxPayne89/klass-hero/commit/017b8b14ffd088c515aacaf44f3e2a02c8d5f1c4))
* include cover_image_url in programs listing map ([f1d9926](https://github.com/MaxPayne89/klass-hero/commit/f1d99267190340c2d10601e07c0e66603bb25639))
* include headshot_url in staff member edit changeset ([#231](https://github.com/MaxPayne89/klass-hero/issues/231)) ([eb8bf20](https://github.com/MaxPayne89/klass-hero/commit/eb8bf20a5b7b545ec0dc9e5b87b2a015cbdd75c9))
* lint_typography off-by-one bug, broaden glob and exclusion ([12b39ce](https://github.com/MaxPayne89/klass-hero/commit/12b39ce1e0d267f3efb2aea807dd75aa208b87c2))
* log nil subscription tier fallback and test same_tier handler ([7d31dfb](https://github.com/MaxPayne89/klass-hero/commit/7d31dfb7e23128bab16449ddad41965bb9e1958e))
* match FAQ content exactly to issue [#312](https://github.com/MaxPayne89/klass-hero/issues/312) and add missing items ([39580fb](https://github.com/MaxPayne89/klass-hero/commit/39580fb253bc5e8b6b059617f2aabadc0cfb978b))
* **messaging:** add server-side guards for reply_privately ([af105da](https://github.com/MaxPayne89/klass-hero/commit/af105da41655ab38bc4a4dba6b5303e85e20b2a5))
* **messaging:** block non-provider replies in broadcast conversations ([9bc20bc](https://github.com/MaxPayne89/klass-hero/commit/9bc20bcddbf832ec468660adfaef475121dcd882))
* **messaging:** correct find_direct_conversation lookup in ReplyPrivatelyToBroadcast ([b3d5a9c](https://github.com/MaxPayne89/klass-hero/commit/b3d5a9c2390987e534017b4632ea2a0c6b53e3df))
* normalize qualifications params in save error paths ([e2c2b1f](https://github.com/MaxPayne89/klass-hero/commit/e2c2b1f29bf65ccb6fe9441838958e10f3b817f0))
* normalize qualifications params in save error paths ([57fc0c5](https://github.com/MaxPayne89/klass-hero/commit/57fc0c5cd3782ae73a49072ec3d594bb109b2c28)), closes [#141](https://github.com/MaxPayne89/klass-hero/issues/141)
* prevent duplicate child records on invite claim ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([ed9086b](https://github.com/MaxPayne89/klass-hero/commit/ed9086bcd20288d0b5c5e56424851adbb2da2d63))
* propagate handler errors + dedup test fixtures ([9d7bca8](https://github.com/MaxPayne89/klass-hero/commit/9d7bca8d08784d416ae72df7441d9231bcb4d48d))
* publish domain/integration events from admin provider updates ([a22ae27](https://github.com/MaxPayne89/klass-hero/commit/a22ae27dec5e38e6c2f751b66b83b3b01f6634ff))
* remove catch-all handle_info from messaging LiveView macros ([632b64d](https://github.com/MaxPayne89/klass-hero/commit/632b64d57f3dacacbcc0ce73db53c5a7415ca15c))
* remove duplicate mount_current_scope from admin on_mount ([274175a](https://github.com/MaxPayne89/klass-hero/commit/274175a7499143731634860005dcfb8988cec613))
* remove tests that referenced deleted CSV template ([ed0b80e](https://github.com/MaxPayne89/klass-hero/commit/ed0b80ef695a23e93e3b8dd8bbb56d804a64f6ee))
* remove unsupported caller-provided ID test ([a15fe5e](https://github.com/MaxPayne89/klass-hero/commit/a15fe5e123f40642ef3f6869805f63ac503ee093))
* replace brittle String.contains? assertions with non-empty list checks ([291a5f7](https://github.com/MaxPayne89/klass-hero/commit/291a5f7504f3c1b0534f046a271ee3cdb5535b15))
* replace hardcoded featured program cards with data-driven component ([078eb6d](https://github.com/MaxPayne89/klass-hero/commit/078eb6daef2cd446e86368bb7b6fbfe350fe5947))
* replace hero-blue-500 with hero-blue-600 for WCAG AA contrast ([f49e734](https://github.com/MaxPayne89/klass-hero/commit/f49e734526f65fad2c5c3cde99f34e8e78c7d8b4)), closes [#227](https://github.com/MaxPayne89/klass-hero/issues/227)
* replace raw SVG back arrow with icon component in provider MessagesLive.Show ([7407b3b](https://github.com/MaxPayne89/klass-hero/commit/7407b3bcbe9d565a898aba4a38eed98b6a5247b9))
* replace raw SVG back arrow with icon component in provider MessagesLive.Show ([954d6ea](https://github.com/MaxPayne89/klass-hero/commit/954d6ea63f5d499b14327eaaac527567056ee438))
* replace String.to_existing_atom with safe tier cast ([b7e00e5](https://github.com/MaxPayne89/klass-hero/commit/b7e00e58207b66d915436d93f4d12f8bbae4b21f))
* reset session_replication_role after FK bypass in test ([61fdb82](https://github.com/MaxPayne89/klass-hero/commit/61fdb82f1f3628bbee7f18f7580c31e6480da89c))
* resolve admin layout rendering and boundary violation regressions ([476d246](https://github.com/MaxPayne89/klass-hero/commit/476d246ed9e2fb5a2045abec7192677f4cf7fd7a))
* resolve credo strict issues — add admin_id metadata, reduce mount nesting ([1136207](https://github.com/MaxPayne89/klass-hero/commit/11362073bd6996f89574e840afdfdb4a6e5c3c26))
* resolve Elixir 1.20 type checker warnings ([ad41134](https://github.com/MaxPayne89/klass-hero/commit/ad4113477c233f3a4f9c306f0a76b7343af0c504))
* resolve flaky ChangeSubscriptionTierTest caused by global event bus leak ([9fe9f3d](https://github.com/MaxPayne89/klass-hero/commit/9fe9f3d5cbcded06542a5b730ba90d8f3e1b561f))
* resolve saga test race condition and add missing subscription tests ([a2de0de](https://github.com/MaxPayne89/klass-hero/commit/a2de0deff4c5cd7b9f8db9c9ffeff018a32ac86a))
* scope ThemeSelectorPlug to admin routes only ([31f66c6](https://github.com/MaxPayne89/klass-hero/commit/31f66c6f35460c09d904dcb59ebff2ea7255ded6))
* share provider_id in batch test to validate record_ids scoping ([4f493d5](https://github.com/MaxPayne89/klass-hero/commit/4f493d573e5fa8a7759e6fa3544bb9d663c6111a))
* show "You're just getting started!" at 0% weekly activity goal ([ecd1567](https://github.com/MaxPayne89/klass-hero/commit/ecd1567d130dcb9c128b329071017776e720ac72)), closes [#226](https://github.com/MaxPayne89/klass-hero/issues/226)
* show starter message at 0% weekly activity goal ([3c22864](https://github.com/MaxPayne89/klass-hero/commit/3c22864040cfecd54427006863dd2e32c9849041))
* show warning flash on cover upload failure instead of blocking save ([0a8e856](https://github.com/MaxPayne89/klass-hero/commit/0a8e856fc0048d83cd30363fb6e0b81db004c3d7))
* staff member headshot not updating on edit ([dd12a19](https://github.com/MaxPayne89/klass-hero/commit/dd12a19f61a46ce5de6ad324311cafb48ead4ae3))
* tighten retry_and_normalize spec to match retry_with_backoff ([823a929](https://github.com/MaxPayne89/klass-hero/commit/823a929f82e7d41b3342f4d1f6ffe4009fc5c2a8))
* two-step child deletion with enrollment cleanup ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([7359d97](https://github.com/MaxPayne89/klass-hero/commit/7359d97059b89dfb1b0bc2ad499aaeb427cdd8ae))
* unify assertion style in ListEnrolledIdentityIds tests ([d152558](https://github.com/MaxPayne89/klass-hero/commit/d15255883ed54970592494b9ab77bb70a14a5195))
* unread message count badge not visible ([9d092c6](https://github.com/MaxPayne89/klass-hero/commit/9d092c635f796d5d19aa68db84dad19a95999224))
* update Debian base image tag to available version ([03722e8](https://github.com/MaxPayne89/klass-hero/commit/03722e8cfc93ed7c0cbcf36fa23cf8db76b3d4a5))
* update Debian base image tag to available version ([3c91af6](https://github.com/MaxPayne89/klass-hero/commit/3c91af6b9f6ed666e76381743cc2ec33122a2a64))
* update stale version references in README ([ccf1d6b](https://github.com/MaxPayne89/klass-hero/commit/ccf1d6bba5e3741bc83e93424b23a3369e106af6))
* use consistent Unicode bullet in footer separator ([#250](https://github.com/MaxPayne89/klass-hero/issues/250)) ([e5c3f7c](https://github.com/MaxPayne89/klass-hero/commit/e5c3f7c4f3253976b6722cb7185e4da5e655836f))
* use current_scope.user.id for check-in/out FK integrity ([2f0a540](https://github.com/MaxPayne89/klass-hero/commit/2f0a5403f885d3d4e21e13ddda411a911fe847b8))
* use DaisyUI theme colors for unread message count badges ([3d858c3](https://github.com/MaxPayne89/klass-hero/commit/3d858c3df592b43973fbf82a06dcd98d1ca703cc)), closes [#229](https://github.com/MaxPayne89/klass-hero/issues/229)
* use divide-* class instead of border-* for conversation list dividers ([8bed751](https://github.com/MaxPayne89/klass-hero/commit/8bed7516eb9884b0191c23a851ca2c1442f33b05))
* use program price directly as enrollment total ([c6986b2](https://github.com/MaxPayne89/klass-hero/commit/c6986b2d49f05e0b79b574ec6f458e53428fb806))
* use realistic UUIDs in MessagingLiveHelper tests ([1358886](https://github.com/MaxPayne89/klass-hero/commit/1358886344cef499b61449d755da628f534a9b22))
* use tagged error tuples in cast_provider_tier and remove tier_label catch-all ([415c675](https://github.com/MaxPayne89/klass-hero/commit/415c675cbc1cd8c6523295bcf8b4d76ce5d9c520))
* use Text field for website (URL lacks readonly support) ([29efd0c](https://github.com/MaxPayne89/klass-hero/commit/29efd0cdf29bb4a6d0d1f98f5f2313240d8b8ac1))
* use text-error-content instead of text-white on unread badges ([27a39f7](https://github.com/MaxPayne89/klass-hero/commit/27a39f742683b0d2048c43d2102b84927a228871))
* use valid UUID format in RepositoryHelpers docstring examples ([3a3dd49](https://github.com/MaxPayne89/klass-hero/commit/3a3dd49613be0fccf524dd627e13dae9f8d98a9b))
* validate parent_user_id server-side and add starter tier test ([6c987d2](https://github.com/MaxPayne89/klass-hero/commit/6c987d289d89b10a0220c416511d4113810aaa0d))
* white-on-white text in message bubbles ([2bcc023](https://github.com/MaxPayne89/klass-hero/commit/2bcc023c44c46eadaa8fa6f91610e1cbd9b658d4))
* wire up Add Child button and View All link on parent dashboard ([197d3d7](https://github.com/MaxPayne89/klass-hero/commit/197d3d761f234bb4ab8bf87615de22b402ecce50)), closes [#225](https://github.com/MaxPayne89/klass-hero/issues/225)
* wire up Add Child button on parent dashboard ([fe17b36](https://github.com/MaxPayne89/klass-hero/commit/fe17b3668077bd9e8abf74aa03a8ddddbe1ced6d))


### Performance Improvements

* add LiveView telemetry metrics to LiveDashboard ([1c95353](https://github.com/MaxPayne89/klass-hero/commit/1c953535b6d44b7516cf998f1d80dddf68de63b5))
* add LiveView telemetry metrics to LiveDashboard ([cb0dd08](https://github.com/MaxPayne89/klass-hero/commit/cb0dd086dc43a20ff603caa8c29e7bcececeddd6))
* batch-load programs in DashboardLive to eliminate N+1 ([e019fc1](https://github.com/MaxPayne89/klass-hero/commit/e019fc129de51e64dbb37a622a56e27b38eb2f3f))
* batch-load programs in DashboardLive to eliminate N+1 ([05acf50](https://github.com/MaxPayne89/klass-hero/commit/05acf502ed39f113a0a94ec441a3c7fe76bae022))
* drop :event tag from handle_event telemetry metric ([258aba5](https://github.com/MaxPayne89/klass-hero/commit/258aba5e87e06cc30b92fe9ea740d2ad26d41d28))
* eliminate duplicate parent lookup and parallelize children + programs in parent dashboard mount ([070a07d](https://github.com/MaxPayne89/klass-hero/commit/070a07d0bf37ce8a2a661b9cbb80e47b2822fcb1))
* eliminate duplicate parent lookup and parallelize children + programs in parent dashboard mount ([828bbb7](https://github.com/MaxPayne89/klass-hero/commit/828bbb7d5c5bdeca18064a49797ad79ebffdb836))
* eliminate duplicate parent lookup in BookingLive mount ([7a383aa](https://github.com/MaxPayne89/klass-hero/commit/7a383aa5524113ba95e18a8244ec15ca7e476d95))
* eliminate duplicate parent lookup in BookingLive mount ([e78025d](https://github.com/MaxPayne89/klass-hero/commit/e78025ded2520e66d85dee5671dd26205f8c6ee8))
* eliminate duplicate staff query on provider dashboard mount ([b4f7c9f](https://github.com/MaxPayne89/klass-hero/commit/b4f7c9fb619958f363c7e8fcd9a41ff281c9c8d7))
* eliminate duplicate staff query on provider dashboard mount ([13b02f8](https://github.com/MaxPayne89/klass-hero/commit/13b02f8dc7d2515bae155e880a67197e0d283e21))
* eliminate redundant active-enrollment count query on provider dashboard ([944620e](https://github.com/MaxPayne89/klass-hero/commit/944620ec77efa716528e7534d5dd51585713e53f))
* eliminate redundant active-enrollment count query on provider dashboard ([8232f0f](https://github.com/MaxPayne89/klass-hero/commit/8232f0fdc3786110646035bdb4c4f18b00c55809))
* eliminate redundant DB query in ParticipationHistoryLive ([9410a6d](https://github.com/MaxPayne89/klass-hero/commit/9410a6d8d3b3581ca085bbd2a740f2533508bf41))
* eliminate redundant DB query in ParticipationHistoryLive ([a22360e](https://github.com/MaxPayne89/klass-hero/commit/a22360e62c255109bf02b5ba0e24bff77fdb07c8))
* parallelize independent DB queries in ProgramDetailLive mount ([a943ef4](https://github.com/MaxPayne89/klass-hero/commit/a943ef4748731473beb710215dbb53de77536620))
* parallelize independent DB queries in ProgramDetailLive mount ([ed9f59f](https://github.com/MaxPayne89/klass-hero/commit/ed9f59f967447bed978a2362da14b7b96f073c0f))
* parallelize programs + staff DB queries in provider dashboard mount ([2183eab](https://github.com/MaxPayne89/klass-hero/commit/2183eab3194fb7472228b31c6d3465711341aa88))
* parallelize programs + staff DB queries in provider dashboard mount ([ba639cc](https://github.com/MaxPayne89/klass-hero/commit/ba639cc0acd11012a3c1b13b779ae2a615808ae1))
* reuse resolved parent in booking usage to eliminate duplicate DB lookup ([7781a57](https://github.com/MaxPayne89/klass-hero/commit/7781a57cf88127fa6b9a31dbc52a7725dd075820))


### Code Refactoring

* add belongs_to associations and admin_changeset to ConsentSchema ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([f539e13](https://github.com/MaxPayne89/klass-hero/commit/f539e136b057f623412bfe4e2738a9b4712d1678))
* address admin dashboard review findings ([0aef4e0](https://github.com/MaxPayne89/klass-hero/commit/0aef4e02fae0173ddb30cf4a2b27074b0001a04e))
* address PR review findings for admin account overview ([eed2799](https://github.com/MaxPayne89/klass-hero/commit/eed27999dc70e8df86a269e3cd01d02caa932441))
* alias nested module references in Participation context ([64bd11a](https://github.com/MaxPayne89/klass-hero/commit/64bd11aaf05ffe8d022d11197a6b9257b3e9be5a))
* clarify retry_and_normalize docstring ([454810f](https://github.com/MaxPayne89/klass-hero/commit/454810f035731c5fcd3561102e770db117cd6fca))
* cleanup post-review for invite claim processing ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([5b9404e](https://github.com/MaxPayne89/klass-hero/commit/5b9404eaf07eef36b5a67fd0e867daf52951f868))
* deduplicate check-in/check-out attendance pipeline ([dea884e](https://github.com/MaxPayne89/klass-hero/commit/dea884e9f3596a5b1de5b5daaad6d4fd9fa012a3))
* deduplicate check-in/check-out attendance pipeline into Shared ([fd58df0](https://github.com/MaxPayne89/klass-hero/commit/fd58df056476cd17820790fb493dcb745e961b4f)), closes [#310](https://github.com/MaxPayne89/klass-hero/issues/310)
* deduplicate humanize helper, fix missing [@impl](https://github.com/impl), simplify tests ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([983a3ce](https://github.com/MaxPayne89/klass-hero/commit/983a3ce8e9d61daf1d5d5301749936092d4801eb))
* deduplicate messaging LiveView callbacks ([1f29df6](https://github.com/MaxPayne89/klass-hero/commit/1f29df6fb5f59880aa46be328f545ee0a54f930c))
* deduplicate messaging LiveView callbacks via __using__ macro ([61af8b2](https://github.com/MaxPayne89/klass-hero/commit/61af8b2b4dbbff27807d4320ca3c4cc291cac02a)), closes [#266](https://github.com/MaxPayne89/klass-hero/issues/266)
* derive subscription tier values from SubscriptionTiers ([718a17e](https://github.com/MaxPayne89/klass-hero/commit/718a17e62d6998a9bc75b6ef0bab7c6cf3384090))
* **enrollment:** remove dead fee calculation code ([#195](https://github.com/MaxPayne89/klass-hero/issues/195)) ([4d94097](https://github.com/MaxPayne89/klass-hero/commit/4d940970eea4af11753cfa757cf959edebb29090))
* **enrollment:** simplify CancelEnrollmentByAdmin use case ([a12fe8a](https://github.com/MaxPayne89/klass-hero/commit/a12fe8a7347586ac77a7b1279a10d3f641191363))
* extract check_title_collisions/1 to flatten nesting in build_context/1 ([9fb84d3](https://github.com/MaxPayne89/klass-hero/commit/9fb84d3ca573dec8bd0394a0c13914a239315519))
* extract duplicate unique constraint check to shared EctoErrorHelpers ([ec112e5](https://github.com/MaxPayne89/klass-hero/commit/ec112e54694507ee89152db581da5700728f874d))
* extract duplicate unique constraint check to shared EctoErrorHelpers ([8447ea9](https://github.com/MaxPayne89/klass-hero/commit/8447ea9bdf24dc5cabc57f2f1d3c24065b66efe3)), closes [#403](https://github.com/MaxPayne89/klass-hero/issues/403)
* extract duplicated to_domain_list into MapperHelpers ([2727a48](https://github.com/MaxPayne89/klass-hero/commit/2727a487560af247f69a8dc7150626771128ea6b))
* extract duplicated to_domain_list/1 into MapperHelpers ([c02c66c](https://github.com/MaxPayne89/klass-hero/commit/c02c66cc9d9cf3cde858dfedc265885046a4c112)), closes [#239](https://github.com/MaxPayne89/klass-hero/issues/239)
* extract filter_options/2 and fix open event in SearchableSelect ([d84e60e](https://github.com/MaxPayne89/klass-hero/commit/d84e60e8cf2c26c8820f416bd37635d0c096ad6a))
* extract infrastructure from domain service, fix critical event error handling ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([768b3ba](https://github.com/MaxPayne89/klass-hero/commit/768b3ba665b401c4c7194fbf9d05fd0ecc319636))
* extract publish-and-log boilerplate from PromoteIntegrationEvents ([66720d9](https://github.com/MaxPayne89/klass-hero/commit/66720d90131b92e58a813a55f5812d2361c9e1c5))
* extract publish-and-log boilerplate into shared helpers ([#323](https://github.com/MaxPayne89/klass-hero/issues/323)) ([bd1cb4d](https://github.com/MaxPayne89/klass-hero/commit/bd1cb4dec474585641fdd4f14b639782a605595b))
* extract repeated icon gradient to module attribute ([#250](https://github.com/MaxPayne89/klass-hero/issues/250)) ([382a2fc](https://github.com/MaxPayne89/klass-hero/commit/382a2fce6460dfa24dc77b929c511b699268721e))
* extract RepositoryHelpers.get_by_id/3 to eliminate duplicate Repo.get pattern ([33887b6](https://github.com/MaxPayne89/klass-hero/commit/33887b62a763f39171c83c8c7f55fbd862b74d3d))
* extract RepositoryHelpers.get_by_id/3 to eliminate duplicate Repo.get pattern ([cf88f24](https://github.com/MaxPayne89/klass-hero/commit/cf88f242b4d5365f22281accdd678c4c3163db41))
* extract retry_and_normalize/2 into RetryHelpers ([1700373](https://github.com/MaxPayne89/klass-hero/commit/17003737d6cd30e411d07b28325f6266f8b2712d))
* extract retry_and_normalize/2 into RetryHelpers ([b335e6a](https://github.com/MaxPayne89/klass-hero/commit/b335e6a0230aa37d989b69024bc3a16dba41ed01)), closes [#421](https://github.com/MaxPayne89/klass-hero/issues/421)
* extract shared badge and hero overlay components ([2703f07](https://github.com/MaxPayne89/klass-hero/commit/2703f070209f23e295318adf5222ecee847e7725))
* extract shared document_page component from legal pages ([d9b35ad](https://github.com/MaxPayne89/klass-hero/commit/d9b35ada9361b3ee6a80aad84f921957ba45c5b2))
* extract shared document_page component from legal pages ([d3bcea4](https://github.com/MaxPayne89/klass-hero/commit/d3bcea4cd7814779ea88ff319653463839c1af3f)), closes [#300](https://github.com/MaxPayne89/klass-hero/issues/300)
* extract shared helpers to ProgramPresenter ([aeb46df](https://github.com/MaxPayne89/klass-hero/commit/aeb46df899f65d013558770d9ca4007cd8c62b62))
* extract shared messaging templates ([#349](https://github.com/MaxPayne89/klass-hero/issues/349)) ([4a6ff8f](https://github.com/MaxPayne89/klass-hero/commit/4a6ff8f1a1c6578a2d775edcf4fd4f78ac7f74d0))
* extract shared messaging templates into MessagingComponents ([#349](https://github.com/MaxPayne89/klass-hero/issues/349)) ([d2fdafb](https://github.com/MaxPayne89/klass-hero/commit/d2fdafb0fece9b1e3b7fffd90fd3491b4bef5bc2))
* extract shared NotifyLiveViews handler to eliminate duplication ([f3b7e25](https://github.com/MaxPayne89/klass-hero/commit/f3b7e2561ed7baf8e576597ff6bee7db1d992e63))
* extract shared NotifyLiveViews handler to eliminate duplication ([8fdd19d](https://github.com/MaxPayne89/klass-hero/commit/8fdd19d8bcf28f8a1827a6455a43b391cebb4cf1)), closes [#253](https://github.com/MaxPayne89/klass-hero/issues/253)
* extract shared TierPresenter for tier display data ([2613ea9](https://github.com/MaxPayne89/klass-hero/commit/2613ea953b0d36cbb8a1f857555866e1211779a0)), closes [#270](https://github.com/MaxPayne89/klass-hero/issues/270)
* extract shared TierPresenter to eliminate duplicated tier display data ([419666d](https://github.com/MaxPayne89/klass-hero/commit/419666d63c315c97bc76caf4351b45a28e112b81))
* fix credo --strict issues across 4 files ([4b81fc1](https://github.com/MaxPayne89/klass-hero/commit/4b81fc133495ed9b83adeee97b2a902e14548bd6))
* InviteClaimedHandler enqueues Oban job instead of inline processing ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([e900d2f](https://github.com/MaxPayne89/klass-hero/commit/e900d2f418cb29e3b366859b57e481121a5b4141))
* loosen typespec on MapperHelpers.to_domain_list/2 ([fc2c7f5](https://github.com/MaxPayne89/klass-hero/commit/fc2c7f58c23b1fc47e653b017f6edb01696cdf10))
* **messaging:** route use case calls through Messaging facade ([199b838](https://github.com/MaxPayne89/klass-hero/commit/199b838fd29b2957f91a173ad9a1e762e1c47550))
* **messaging:** simplify broadcast reply code ([712ba67](https://github.com/MaxPayne89/klass-hero/commit/712ba678e7af26f46660396443df68e3e2c6c119))
* remove unused parent_id param from apply_history/4 ([83b7ed6](https://github.com/MaxPayne89/klass-hero/commit/83b7ed6fd03cd7df7b7b4c69d377d5b0ed860217))
* rename admin UserLive to AccountLive ([dd90dcb](https://github.com/MaxPayne89/klass-hero/commit/dd90dcbeb6d9c701d93447377ad0b5217b867e0b))
* rename gradient to gradient_class in document_page component ([483db53](https://github.com/MaxPayne89/klass-hero/commit/483db5355d925909bfced3a2bdd6bd8efb69a61d))
* replace staff_member provider_id field with belongs_to association ([a972cee](https://github.com/MaxPayne89/klass-hero/commit/a972ceeee0737200c42d1f60d1f029028127d79c))
* simplify admin sessions code after review ([3b2a212](https://github.com/MaxPayne89/klass-hero/commit/3b2a2129679a5cc6a7e03252ad9b8319136f99ad))
* simplify critical event infrastructure ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([6dac34d](https://github.com/MaxPayne89/klass-hero/commit/6dac34d63d4c5e00e733fcd55c4c58384c0ac9d8))
* simplify instructor options with for comprehension and extract helper ([dd1023a](https://github.com/MaxPayne89/klass-hero/commit/dd1023a34b54b3ef5ca34d2f6d53a55213d7e052))
* simplify SearchableSelect state and use domain status references ([d91a4e8](https://github.com/MaxPayne89/klass-hero/commit/d91a4e8c38bcdd2b9cc7bfd03cd6bc3d77c9e8b6))
* tighten broadcast button comment and test assertions ([2f7676c](https://github.com/MaxPayne89/klass-hero/commit/2f7676c7994e4fe683ca56c93c7fcff04520576f))
* use compile_env! module attributes in enrollment use cases ([e3a7f05](https://github.com/MaxPayne89/klass-hero/commit/e3a7f05f19c50dbb54f589a59c9c1e362e25b650))
* use compile_env! module attributes in enrollment use cases ([39a3422](https://github.com/MaxPayne89/klass-hero/commit/39a342213e6e9939a4cccba7166d5909ca39805f))
* use ngettext for Hero heading and add plural test ([32915be](https://github.com/MaxPayne89/klass-hero/commit/32915beb4c31b8185a8235a2680b4226f0517119))


### Dependencies

* add backpex for admin dashboard ([7f7af12](https://github.com/MaxPayne89/klass-hero/commit/7f7af12a268d62b100caee87548f4c741ee4c60a))
* update credo, ecto_sql, error_tracker, phoenix_live_view ([051889b](https://github.com/MaxPayne89/klass-hero/commit/051889b2a9494df2fac82fa3fdd473827ba43b38))

## [0.6.0](https://github.com/MaxPayne89/klass-hero/compare/v0.5.1...v0.6.0) (2026-03-15)


### Features

* fix broadcast reply privacy — parents can no longer expose replies to group ([6409033](https://github.com/MaxPayne89/klass-hero/commit/6409033d5f5dd8c26fc63d5036ddfff535f0e698))
* **messaging-ui:** add broadcast_reply_bar and conditional rendering ([8961c6f](https://github.com/MaxPayne89/klass-hero/commit/8961c6fef50ae15a8ea5bbca6939901ecf3cf584))
* **messaging:** add get_user_id_for_provider/1 to ForResolvingUsers port ([67cd06c](https://github.com/MaxPayne89/klass-hero/commit/67cd06c25dc14b21afc0782e424e987f57081f8e))
* **messaging:** add ReplyPrivatelyToBroadcast use case ([cecfe22](https://github.com/MaxPayne89/klass-hero/commit/cecfe22cd059f7fa4460e17e38e1cad029d463fb))
* **messaging:** add skip_entitlement_check opt to CreateDirectConversation ([e7f1943](https://github.com/MaxPayne89/klass-hero/commit/e7f1943b0833f5c70fa0c2b958c8bc1ae275b8a6))
* **messaging:** expose reply_privately_to_broadcast on facade ([b49b77a](https://github.com/MaxPayne89/klass-hero/commit/b49b77ab025dac1e0e85a4623ef5d6ef8be65e0f))
* **messaging:** inject reply_privately event handler in LiveView helper ([60428d8](https://github.com/MaxPayne89/klass-hero/commit/60428d851b6c0055b0abf6d39e0fc8c2858efb43))


### Bug Fixes

* **messaging:** add server-side guards for reply_privately ([af105da](https://github.com/MaxPayne89/klass-hero/commit/af105da41655ab38bc4a4dba6b5303e85e20b2a5))
* **messaging:** block non-provider replies in broadcast conversations ([9bc20bc](https://github.com/MaxPayne89/klass-hero/commit/9bc20bcddbf832ec468660adfaef475121dcd882))
* **messaging:** correct find_direct_conversation lookup in ReplyPrivatelyToBroadcast ([b3d5a9c](https://github.com/MaxPayne89/klass-hero/commit/b3d5a9c2390987e534017b4632ea2a0c6b53e3df))
* tighten retry_and_normalize spec to match retry_with_backoff ([823a929](https://github.com/MaxPayne89/klass-hero/commit/823a929f82e7d41b3342f4d1f6ffe4009fc5c2a8))


### Code Refactoring

* clarify retry_and_normalize docstring ([454810f](https://github.com/MaxPayne89/klass-hero/commit/454810f035731c5fcd3561102e770db117cd6fca))
* extract retry_and_normalize/2 into RetryHelpers ([1700373](https://github.com/MaxPayne89/klass-hero/commit/17003737d6cd30e411d07b28325f6266f8b2712d))
* extract retry_and_normalize/2 into RetryHelpers ([b335e6a](https://github.com/MaxPayne89/klass-hero/commit/b335e6a0230aa37d989b69024bc3a16dba41ed01)), closes [#421](https://github.com/MaxPayne89/klass-hero/issues/421)
* **messaging:** route use case calls through Messaging facade ([199b838](https://github.com/MaxPayne89/klass-hero/commit/199b838fd29b2957f91a173ad9a1e762e1c47550))
* **messaging:** simplify broadcast reply code ([712ba67](https://github.com/MaxPayne89/klass-hero/commit/712ba678e7af26f46660396443df68e3e2c6c119))

## [0.5.1](https://github.com/MaxPayne89/klass-hero/compare/v0.5.0...v0.5.1) (2026-03-15)


### Bug Fixes

* address PR review comments on concurrent enrollment test ([e36e4b7](https://github.com/MaxPayne89/klass-hero/commit/e36e4b7b9bc041b9532dc475e3cd3b2ecda7566e))
* use valid UUID format in RepositoryHelpers docstring examples ([3a3dd49](https://github.com/MaxPayne89/klass-hero/commit/3a3dd49613be0fccf524dd627e13dae9f8d98a9b))


### Performance Improvements

* eliminate duplicate parent lookup in BookingLive mount ([7a383aa](https://github.com/MaxPayne89/klass-hero/commit/7a383aa5524113ba95e18a8244ec15ca7e476d95))
* eliminate duplicate parent lookup in BookingLive mount ([e78025d](https://github.com/MaxPayne89/klass-hero/commit/e78025ded2520e66d85dee5671dd26205f8c6ee8))


### Code Refactoring

* alias nested module references in Participation context ([64bd11a](https://github.com/MaxPayne89/klass-hero/commit/64bd11aaf05ffe8d022d11197a6b9257b3e9be5a))
* extract RepositoryHelpers.get_by_id/3 to eliminate duplicate Repo.get pattern ([33887b6](https://github.com/MaxPayne89/klass-hero/commit/33887b62a763f39171c83c8c7f55fbd862b74d3d))
* extract RepositoryHelpers.get_by_id/3 to eliminate duplicate Repo.get pattern ([cf88f24](https://github.com/MaxPayne89/klass-hero/commit/cf88f242b4d5365f22281accdd678c4c3163db41))

## [0.5.0](https://github.com/MaxPayne89/klass-hero/compare/v0.4.0...v0.5.0) (2026-03-14)


### Features

* add empty state message to admin sessions list ([9a9d017](https://github.com/MaxPayne89/klass-hero/commit/9a9d01775cf4dd2c425069c3c0149ae9859e732e))
* add empty state message to admin sessions list ([5e35d83](https://github.com/MaxPayne89/klass-hero/commit/5e35d83b4af403779cecddcbe5612dc593027d06))


### Bug Fixes

* correct changeset error assertions in ParticipantPolicyForm tests ([c288a1e](https://github.com/MaxPayne89/klass-hero/commit/c288a1eae173cc04c3ed7237e0f0a0288b777e35))
* harden dashboard mount resilience and fix misleading param name ([a440150](https://github.com/MaxPayne89/klass-hero/commit/a44015040c6d7f9ef549a977754174dc94d14902))


### Performance Improvements

* eliminate duplicate parent lookup and parallelize children + programs in parent dashboard mount ([070a07d](https://github.com/MaxPayne89/klass-hero/commit/070a07d0bf37ce8a2a661b9cbb80e47b2822fcb1))
* reuse resolved parent in booking usage to eliminate duplicate DB lookup ([7781a57](https://github.com/MaxPayne89/klass-hero/commit/7781a57cf88127fa6b9a31dbc52a7725dd075820))

## [0.4.0](https://github.com/MaxPayne89/klass-hero/compare/v0.3.0...v0.4.0) (2026-03-13)


### Features

* add admin sessions LiveView with today mode and roster display ([5c78eca](https://github.com/MaxPayne89/klass-hero/commit/5c78ecaddd7e5e5812a6fbb4d5e5b0f701ab3b8b))
* add admin sessions route and sidebar item ([5240ea1](https://github.com/MaxPayne89/klass-hero/commit/5240ea18b626ffcb94abcdb5eba6557f20932939))
* add admin_correct/2 to ParticipationRecord for admin corrections ([df62dc8](https://github.com/MaxPayne89/klass-hero/commit/df62dc8ff33366ad7736363cd58495fd3ef39ee8))
* add Admin.Queries.list_providers_for_select/0 ([8f19a70](https://github.com/MaxPayne89/klass-hero/commit/8f19a70179942d66e179fb5380d9471811353b0c))
* add CorrectAttendance use case for admin attendance fixes ([a5fca75](https://github.com/MaxPayne89/klass-hero/commit/a5fca75cfbba39af6f3bf28bd179783eed114ab2))
* add German translations for admin sessions dashboard ([aad0c3b](https://github.com/MaxPayne89/klass-hero/commit/aad0c3b681a7e811d20a5aa9629b4358eb79d810))
* add list_admin_sessions/1 with enriched data for admin dashboard ([13b562a](https://github.com/MaxPayne89/klass-hero/commit/13b562a7a5fcbeaef0503d2266bc65383e96baf1))
* add participation session management to admin dashboard ([b8b7f20](https://github.com/MaxPayne89/klass-hero/commit/b8b7f206e9153de6e585f86e22d23a35dd642e0b))
* add SearchableSelect LiveComponent with basic rendering ([49943af](https://github.com/MaxPayne89/klass-hero/commit/49943af4fdb12be2cc7577c286a0218a43fe7670))
* expose list_admin_sessions through participation context facade ([b6707b9](https://github.com/MaxPayne89/klass-hero/commit/b6707b98d2f5dea3cdda1ae0dd9d31aac46de8c7))
* replace mode toggle with unified filter bar in admin sessions ([c9720b8](https://github.com/MaxPayne89/klass-hero/commit/c9720b8d4537f3023e5af6d019f2a8a6422d2b48))


### Bug Fixes

* address Copilot PR review comments ([#1](https://github.com/MaxPayne89/klass-hero/issues/1), [#2](https://github.com/MaxPayne89/klass-hero/issues/2), [#3](https://github.com/MaxPayne89/klass-hero/issues/3), [#7](https://github.com/MaxPayne89/klass-hero/issues/7)) ([f89a0e2](https://github.com/MaxPayne89/klass-hero/commit/f89a0e2bfac3629bbff0f774431e9f8e27da9cec))
* address critical PR review issues (C1-C3) ([1999748](https://github.com/MaxPayne89/klass-hero/commit/19997481ffef7f9bcec11a3a61265388b4d2a544))
* address PR review suggestions (S11-S15) ([c388a2e](https://github.com/MaxPayne89/klass-hero/commit/c388a2e0357256f29b6ca8b8ddd963261a8a9e8c))
* export Admin.Queries from KlassHero boundary ([c6b0fc4](https://github.com/MaxPayne89/klass-hero/commit/c6b0fc40dc5a35eecf48a5115183ed73e408f737))
* resolve admin layout rendering and boundary violation regressions ([476d246](https://github.com/MaxPayne89/klass-hero/commit/476d246ed9e2fb5a2045abec7192677f4cf7fd7a))


### Code Refactoring

* extract filter_options/2 and fix open event in SearchableSelect ([d84e60e](https://github.com/MaxPayne89/klass-hero/commit/d84e60e8cf2c26c8820f416bd37635d0c096ad6a))
* simplify admin sessions code after review ([3b2a212](https://github.com/MaxPayne89/klass-hero/commit/3b2a2129679a5cc6a7e03252ad9b8319136f99ad))
* simplify SearchableSelect state and use domain status references ([d91a4e8](https://github.com/MaxPayne89/klass-hero/commit/d91a4e8c38bcdd2b9cc7bfd03cd6bc3d77c9e8b6))

## [0.3.0](https://github.com/MaxPayne89/klass-hero/compare/v0.2.0...v0.3.0) (2026-03-13)


### Features

* add ConsentStatusFilter for admin consents ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([7599a8a](https://github.com/MaxPayne89/klass-hero/commit/7599a8a7117021eca937d554c731cdbdd97e6ddc))
* add ConsentTypeFilter for admin consents ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([35ee8a4](https://github.com/MaxPayne89/klass-hero/commit/35ee8a414c62f6a24a68703fca949374d89bdfac))
* add read-only admin consent overview with Backpex ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([8195263](https://github.com/MaxPayne89/klass-hero/commit/81952630c8112c9edfd4b27b37accdd0ba3ea15b))
* add read-only admin consents overview ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([1bf091d](https://github.com/MaxPayne89/klass-hero/commit/1bf091d98a7e7fcebd0636d37470c0ee865a3e3d))


### Bug Fixes

* add Consents link to admin sidebar navigation ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([9e66a20](https://github.com/MaxPayne89/klass-hero/commit/9e66a2085ff41da5aa2ff53483192ba65ea201fa))
* add DB connection pool resilience for Fly.io suspend/resume ([4ffd420](https://github.com/MaxPayne89/klass-hero/commit/4ffd4202dab33807de21e9e8a9fabf1c72c3a1e6))
* add DB connection pool resilience for Fly.io suspend/resume ([6bb4129](https://github.com/MaxPayne89/klass-hero/commit/6bb41291e047f7d4421bfd129dca8bada3179ce2)), closes [#395](https://github.com/MaxPayne89/klass-hero/issues/395)
* address PR review — add filter tests, fix test names, update spec ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([012dd9d](https://github.com/MaxPayne89/klass-hero/commit/012dd9dfd99c30592e758eb8a6748c62acd19a7d))
* harden admin consent view — nil parent render, catch-all filter, tighter tests ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([e47af47](https://github.com/MaxPayne89/klass-hero/commit/e47af476ca6d3e6c82d61b5506badcd894df5909))


### Code Refactoring

* add belongs_to associations and admin_changeset to ConsentSchema ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([f539e13](https://github.com/MaxPayne89/klass-hero/commit/f539e136b057f623412bfe4e2738a9b4712d1678))
* deduplicate humanize helper, fix missing [@impl](https://github.com/impl), simplify tests ([#341](https://github.com/MaxPayne89/klass-hero/issues/341)) ([983a3ce](https://github.com/MaxPayne89/klass-hero/commit/983a3ce8e9d61daf1d5d5301749936092d4801eb))
* extract duplicate unique constraint check to shared EctoErrorHelpers ([ec112e5](https://github.com/MaxPayne89/klass-hero/commit/ec112e54694507ee89152db581da5700728f874d))
* extract duplicate unique constraint check to shared EctoErrorHelpers ([8447ea9](https://github.com/MaxPayne89/klass-hero/commit/8447ea9bdf24dc5cabc57f2f1d3c24065b66efe3)), closes [#403](https://github.com/MaxPayne89/klass-hero/issues/403)

## [0.2.0](https://github.com/MaxPayne89/klass-hero/compare/v0.1.15...v0.2.0) (2026-03-12)


### Features

* add account overview to admin dashboard ([6ae5481](https://github.com/MaxPayne89/klass-hero/commit/6ae54810f8e0ea3aef3aac22656f55e5d0550686))
* add has_one associations for parent/provider profiles on User schema ([837d138](https://github.com/MaxPayne89/klass-hero/commit/837d138ce13105408490108b40bd1d88c2a24887))
* add roles badges to admin account overview ([d3dc31f](https://github.com/MaxPayne89/klass-hero/commit/d3dc31f8a79a8aa9a0f734f614614846ebd27b2c))
* add subscription tier badges to admin account overview ([2b3e048](https://github.com/MaxPayne89/klass-hero/commit/2b3e0489de0baf033678912a868c63ba9b96e557))
* finalize admin account overview field layout ([0ceede0](https://github.com/MaxPayne89/klass-hero/commit/0ceede0d17b56deea6e30dadf1ba065264a1fd2f))


### Code Refactoring

* address PR review findings for admin account overview ([eed2799](https://github.com/MaxPayne89/klass-hero/commit/eed27999dc70e8df86a269e3cd01d02caa932441))
* fix credo --strict issues across 4 files ([4b81fc1](https://github.com/MaxPayne89/klass-hero/commit/4b81fc133495ed9b83adeee97b2a902e14548bd6))
* rename admin UserLive to AccountLive ([dd90dcb](https://github.com/MaxPayne89/klass-hero/commit/dd90dcbeb6d9c701d93447377ad0b5217b867e0b))

## [0.1.15](https://github.com/MaxPayne89/klass-hero/compare/v0.1.14...v0.1.15) (2026-03-12)


### Bug Fixes

* address PR review comments on ReferralCodeGenerator tests ([ce5cba1](https://github.com/MaxPayne89/klass-hero/commit/ce5cba1d6c55fe1c22bb9ae5820cc131a86af701))
* allow minor version bumps for feat commits in pre-1.0 ([de4c12c](https://github.com/MaxPayne89/klass-hero/commit/de4c12c427f4daba8faa601ba3816a790006d97e))
* allow minor version bumps for feat commits in pre-1.0 ([768c2a2](https://github.com/MaxPayne89/klass-hero/commit/768c2a2e3beeca94bfe0419fde9921e51824bba2))

## [0.1.14](https://github.com/MaxPayne89/klass-hero/compare/v0.1.13...v0.1.14) (2026-03-12)


### Bug Fixes

* update Debian base image tag to available version ([03722e8](https://github.com/MaxPayne89/klass-hero/commit/03722e8cfc93ed7c0cbcf36fa23cf8db76b3d4a5))
* update Debian base image tag to available version ([3c91af6](https://github.com/MaxPayne89/klass-hero/commit/3c91af6b9f6ed666e76381743cc2ec33122a2a64))

## [0.1.13](https://github.com/MaxPayne89/klass-hero/compare/v0.1.12...v0.1.13) (2026-03-12)


### Bug Fixes

* address PR review — extract shared helper and add enrollment summary tests ([978b0ab](https://github.com/MaxPayne89/klass-hero/commit/978b0ab91af39ed1b58b72e6ebb452781763d657))
* address PR review — misleading comment and missing assertion ([9ead52e](https://github.com/MaxPayne89/klass-hero/commit/9ead52e34084a3841e3b52df054eb0ec71270287))
* align security workflow with Elixir 1.20.0-rc.3 and OTP 28.4 ([d4f6442](https://github.com/MaxPayne89/klass-hero/commit/d4f64426732e271b471af1397638fc9ebb9a9d3f))
* remove tests that referenced deleted CSV template ([ed0b80e](https://github.com/MaxPayne89/klass-hero/commit/ed0b80ef695a23e93e3b8dd8bbb56d804a64f6ee))
* resolve Elixir 1.20 type checker warnings ([ad41134](https://github.com/MaxPayne89/klass-hero/commit/ad4113477c233f3a4f9c306f0a76b7343af0c504))
* update stale version references in README ([ccf1d6b](https://github.com/MaxPayne89/klass-hero/commit/ccf1d6bba5e3741bc83e93424b23a3369e106af6))


### Performance Improvements

* eliminate redundant active-enrollment count query on provider dashboard ([944620e](https://github.com/MaxPayne89/klass-hero/commit/944620ec77efa716528e7534d5dd51585713e53f))
* parallelize programs + staff DB queries in provider dashboard mount ([2183eab](https://github.com/MaxPayne89/klass-hero/commit/2183eab3194fb7472228b31c6d3465711341aa88))
* parallelize programs + staff DB queries in provider dashboard mount ([ba639cc](https://github.com/MaxPayne89/klass-hero/commit/ba639cc0acd11012a3c1b13b779ae2a615808ae1))

## [0.1.12](https://github.com/MaxPayne89/klass-hero/compare/v0.1.11...v0.1.12) (2026-03-11)


### Features

* add bookings admin dashboard with cancel action ([4afb68f](https://github.com/MaxPayne89/klass-hero/commit/4afb68fb87f374d401295f9fa48939059be47735))
* add CriticalEventDispatcher with handler_ref/1 ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([9cb3f36](https://github.com/MaxPayne89/klass-hero/commit/9cb3f36bfd344d30c05a35e45024c05312d0db65))
* add CriticalEventDispatcher.execute/3 with transactional idempotency ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([e45d33b](https://github.com/MaxPayne89/klass-hero/commit/e45d33bd6d5d72c68aae1e61fdc01279125f058e))
* add CriticalEventDispatcher.mark_processed/2 ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([73c30fa](https://github.com/MaxPayne89/klass-hero/commit/73c30fac05f3271b2c78adb68ef6dfcf775d5e4e))
* add CriticalEventHandlerRegistry and critical_events Oban queue ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([e8ffddd](https://github.com/MaxPayne89/klass-hero/commit/e8ffddd13dc88e9874426315d2fde2664a3813d5))
* add CriticalEventSerializer for event struct JSON round-trip ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([c245af5](https://github.com/MaxPayne89/klass-hero/commit/c245af57e4464d8826422bf40d154ac009f097e4))
* add CriticalEventWorker Oban worker for durable event delivery ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([b15fb0b](https://github.com/MaxPayne89/klass-hero/commit/b15fb0b9c34d667a1d069c1576696339f99c7469))
* add DomainEventBus.dispatch_critical/2 with per-handler identity ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([2691fff](https://github.com/MaxPayne89/klass-hero/commit/2691fff54280e6da2beda9be46eabdfc2feb77c2))
* add dual delivery for critical integration events in PubSubIntegrationEventPublisher ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([a834341](https://github.com/MaxPayne89/klass-hero/commit/a8343416073ad87e5e5a4d7168291d3862b5c821))
* add Oban Web dashboard with admin-only access ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([0d1b8e0](https://github.com/MaxPayne89/klass-hero/commit/0d1b8e070601e8384a7aa5f71ba117783147ced4))
* add persistent critical events with exactly-once delivery ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([ba73d12](https://github.com/MaxPayne89/klass-hero/commit/ba73d12c8a43ba21d28c0b385c94cd6ee35ba240))
* add processed_events table and schema for critical event idempotency ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([95f2771](https://github.com/MaxPayne89/klass-hero/commit/95f277105027bb8eebff9e3440b95c89f0de3868))
* **admin:** add BookingLive Backpex resource with cancel action and status filter ([13c1a52](https://github.com/MaxPayne89/klass-hero/commit/13c1a526bc6653f505de981b059d5b0f9faf11b5))
* **admin:** add CancelBookingAction item action with reason modal ([5fe264d](https://github.com/MaxPayne89/klass-hero/commit/5fe264d9c057973eeb1d3a3c49470f1064437eb1))
* **admin:** add StatusFilter for enrollment status filtering ([0d383e4](https://github.com/MaxPayne89/klass-hero/commit/0d383e418b6df19f1aa47344f46073e1325882cf))
* **enrollment:** add belongs_to associations and admin_changeset to EnrollmentSchema ([c60485f](https://github.com/MaxPayne89/klass-hero/commit/c60485ff09112b53522e1ae961283fef12c425d3))
* **enrollment:** add CancelEnrollmentByAdmin use case with event dispatch ([5a74e49](https://github.com/MaxPayne89/klass-hero/commit/5a74e498b20c2a28ea927ffb19c2161cba479031))
* **enrollment:** add enrollment_cancelled domain event factory ([87fd2a1](https://github.com/MaxPayne89/klass-hero/commit/87fd2a1b86ecbb17e58505bdfbb62fa3266b30c6))
* **enrollment:** add enrollment_cancelled integration event factory ([cc1a05c](https://github.com/MaxPayne89/klass-hero/commit/cc1a05c123227be2f801086ac8bb1227c2c00fc5))
* **enrollment:** add update/2 to enrollment port and repository ([4c8907a](https://github.com/MaxPayne89/klass-hero/commit/4c8907ae47130f9964b5c8e72eb679cc0442c8c6))
* **enrollment:** promote enrollment_cancelled to integration event ([942c3f0](https://github.com/MaxPayne89/klass-hero/commit/942c3f0261be221bd32fa09adad1bf0808212f24))
* wire critical domain events through CriticalEventDispatcher in EventDispatchHelper ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([8b7208f](https://github.com/MaxPayne89/klass-hero/commit/8b7208f8710a70affa840f1e1f3baae14bd2468d))
* wrap critical integration events in CriticalEventDispatcher in EventSubscriber ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([24508e0](https://github.com/MaxPayne89/klass-hero/commit/24508e0cff3b9567aecb2dc27eef0b7ba16c5565))


### Bug Fixes

* address PR review — typespecs accuracy ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([79444b9](https://github.com/MaxPayne89/klass-hero/commit/79444b97932a370c162c44a7c5e0efcd427e5288))
* **admin:** add Bookings sidebar nav link and shorten date format ([57d1d40](https://github.com/MaxPayne89/klass-hero/commit/57d1d4061bb72e24804aecd74c112f90021a4c43))
* **admin:** propagate event dispatch errors and improve cancel action feedback ([87a311b](https://github.com/MaxPayne89/klass-hero/commit/87a311b3a14a6aebd649361d89fe501dfa2abd99))
* **enrollment:** remove adapter-layer dependency from CancelEnrollmentByAdmin ([1c2e77c](https://github.com/MaxPayne89/klass-hero/commit/1c2e77c47c66fa190b1f33a00c0d0d90c1527894))
* **enrollment:** validate non-empty reason in CancelEnrollmentByAdmin ([36d3378](https://github.com/MaxPayne89/klass-hero/commit/36d3378d99ef81a522b88bd4e2e9a2c08d00da36))
* harden error handling, logging, and test coverage for critical events ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([31d1437](https://github.com/MaxPayne89/klass-hero/commit/31d14374c4c3f2fd3f1b7695c2faa8e0b19cc438))
* improve docs, error messages, and test coverage for critical events ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([017b8b1](https://github.com/MaxPayne89/klass-hero/commit/017b8b14ffd088c515aacaf44f3e2a02c8d5f1c4))
* resolve credo strict issues — add admin_id metadata, reduce mount nesting ([1136207](https://github.com/MaxPayne89/klass-hero/commit/11362073bd6996f89574e840afdfdb4a6e5c3c26))
* show "You're just getting started!" at 0% weekly activity goal ([ecd1567](https://github.com/MaxPayne89/klass-hero/commit/ecd1567d130dcb9c128b329071017776e720ac72)), closes [#226](https://github.com/MaxPayne89/klass-hero/issues/226)
* show starter message at 0% weekly activity goal ([3c22864](https://github.com/MaxPayne89/klass-hero/commit/3c22864040cfecd54427006863dd2e32c9849041))


### Code Refactoring

* **enrollment:** simplify CancelEnrollmentByAdmin use case ([a12fe8a](https://github.com/MaxPayne89/klass-hero/commit/a12fe8a7347586ac77a7b1279a10d3f641191363))
* extract infrastructure from domain service, fix critical event error handling ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([768b3ba](https://github.com/MaxPayne89/klass-hero/commit/768b3ba665b401c4c7194fbf9d05fd0ecc319636))
* simplify critical event infrastructure ([#325](https://github.com/MaxPayne89/klass-hero/issues/325)) ([6dac34d](https://github.com/MaxPayne89/klass-hero/commit/6dac34d63d4c5e00e733fcd55c4c58384c0ac9d8))

## [0.1.11](https://github.com/MaxPayne89/klass-hero/compare/v0.1.10...v0.1.11) (2026-03-10)


### Features

* add admin_changeset/3 to StaffMemberSchema ([#339](https://github.com/MaxPayne89/klass-hero/issues/339)) ([7d7ce76](https://github.com/MaxPayne89/klass-hero/commit/7d7ce7645d151bacc43d4d9b834e3db36f811c77))
* add staff members to admin dashboard ([f743a2b](https://github.com/MaxPayne89/klass-hero/commit/f743a2bdf24501b34abda52dfe6c4a788716da50))
* add staff members to admin dashboard ([#339](https://github.com/MaxPayne89/klass-hero/issues/339)) ([edbd3db](https://github.com/MaxPayne89/klass-hero/commit/edbd3dba52a03b227683ba935897a1222f985096))


### Bug Fixes

* address PR review - test use cases directly instead of facade ([6e81c5e](https://github.com/MaxPayne89/klass-hero/commit/6e81c5e571a7ab8aa790859d598ae086e35d1c87))
* hide provider field from staff member edit form ([55f9f37](https://github.com/MaxPayne89/klass-hero/commit/55f9f3729e0ae9e560b12b5188dac16b19f7712c))
* use divide-* class instead of border-* for conversation list dividers ([8bed751](https://github.com/MaxPayne89/klass-hero/commit/8bed7516eb9884b0191c23a851ca2c1442f33b05))


### Performance Improvements

* eliminate duplicate staff query on provider dashboard mount ([b4f7c9f](https://github.com/MaxPayne89/klass-hero/commit/b4f7c9fb619958f363c7e8fcd9a41ff281c9c8d7))
* eliminate duplicate staff query on provider dashboard mount ([13b02f8](https://github.com/MaxPayne89/klass-hero/commit/13b02f8dc7d2515bae155e880a67197e0d283e21))


### Code Refactoring

* extract shared messaging templates ([#349](https://github.com/MaxPayne89/klass-hero/issues/349)) ([4a6ff8f](https://github.com/MaxPayne89/klass-hero/commit/4a6ff8f1a1c6578a2d775edcf4fd4f78ac7f74d0))
* extract shared messaging templates into MessagingComponents ([#349](https://github.com/MaxPayne89/klass-hero/issues/349)) ([d2fdafb](https://github.com/MaxPayne89/klass-hero/commit/d2fdafb0fece9b1e3b7fffd90fd3491b4bef5bc2))
* replace staff_member provider_id field with belongs_to association ([a972cee](https://github.com/MaxPayne89/klass-hero/commit/a972ceeee0737200c42d1f60d1f029028127d79c))
* simplify instructor options with for comprehension and extract helper ([dd1023a](https://github.com/MaxPayne89/klass-hero/commit/dd1023a34b54b3ef5ca34d2f6d53a55213d7e052))

## [0.1.10](https://github.com/MaxPayne89/klass-hero/compare/v0.1.9...v0.1.10) (2026-03-10)


### Bug Fixes

* replace raw SVG back arrow with icon component in provider MessagesLive.Show ([7407b3b](https://github.com/MaxPayne89/klass-hero/commit/7407b3bcbe9d565a898aba4a38eed98b6a5247b9))
* replace raw SVG back arrow with icon component in provider MessagesLive.Show ([954d6ea](https://github.com/MaxPayne89/klass-hero/commit/954d6ea63f5d499b14327eaaac527567056ee438))
* resolve flaky ChangeSubscriptionTierTest caused by global event bus leak ([9fe9f3d](https://github.com/MaxPayne89/klass-hero/commit/9fe9f3d5cbcded06542a5b730ba90d8f3e1b561f))
* unify assertion style in ListEnrolledIdentityIds tests ([d152558](https://github.com/MaxPayne89/klass-hero/commit/d15255883ed54970592494b9ab77bb70a14a5195))


### Performance Improvements

* parallelize independent DB queries in ProgramDetailLive mount ([a943ef4](https://github.com/MaxPayne89/klass-hero/commit/a943ef4748731473beb710215dbb53de77536620))

## [0.1.9](https://github.com/MaxPayne89/klass-hero/compare/v0.1.8...v0.1.9) (2026-03-09)


### Features

* add admin_changeset to ProviderProfileSchema ([8b413d6](https://github.com/MaxPayne89/klass-hero/commit/8b413d62b515a9c8b25473cbcf1679c660e5a98d))
* add provider profiles Backpex admin resource ([9aa9bc4](https://github.com/MaxPayne89/klass-hero/commit/9aa9bc404b5eb5f25bc6e1677625afb82f273cdf)), closes [#338](https://github.com/MaxPayne89/klass-hero/issues/338)
* add provider profiles to admin dashboard ([bb058ac](https://github.com/MaxPayne89/klass-hero/commit/bb058aca7c257bbd6d41a3c47598b8cbb717bbf5))
* add providers link to admin sidebar ([cac9f66](https://github.com/MaxPayne89/klass-hero/commit/cac9f660d91eb2ff8e1825e93bc597ee02b59734))
* fix categories display and add verified filter ([3c1b5d5](https://github.com/MaxPayne89/klass-hero/commit/3c1b5d539e7df0415e9d4d9f8e18f5e3dc8d5fdf))
* rebrand instructor section to Hero terminology ([4caa119](https://github.com/MaxPayne89/klass-hero/commit/4caa119a463069ab4236968264c8bba8f776e92b))
* rebrand instructor section to Hero terminology ([bf05af8](https://github.com/MaxPayne89/klass-hero/commit/bf05af8ee6d9dcefccb8bce5e47a283cdc523e0f)), closes [#297](https://github.com/MaxPayne89/klass-hero/issues/297)
* standardize font usage across all pages ([932a3bc](https://github.com/MaxPayne89/klass-hero/commit/932a3bcce83c52f8594a07c4bd3292ce7ba1ac61))
* standardize font usage across all pages ([#347](https://github.com/MaxPayne89/klass-hero/issues/347)) ([76cb706](https://github.com/MaxPayne89/klass-hero/commit/76cb7064b6bf7740a10a6f01fbcd6e88581d252a))


### Bug Fixes

* address PR review comments on lint_typography ([59d6a8f](https://github.com/MaxPayne89/klass-hero/commit/59d6a8f07fcdd070ebbde6618b3cddc9b8b71a5d))
* display featured programs using data-driven component ([c8dfebd](https://github.com/MaxPayne89/klass-hero/commit/c8dfebdbad95b1797745122734372ec7b1b42481))
* hide age range row in program card when nil ([059cc2b](https://github.com/MaxPayne89/klass-hero/commit/059cc2b5082939c742961208f74da2fde4b0a335))
* lint_typography off-by-one bug, broaden glob and exclusion ([12b39ce](https://github.com/MaxPayne89/klass-hero/commit/12b39ce1e0d267f3efb2aea807dd75aa208b87c2))
* publish domain/integration events from admin provider updates ([a22ae27](https://github.com/MaxPayne89/klass-hero/commit/a22ae27dec5e38e6c2f751b66b83b3b01f6634ff))
* replace hardcoded featured program cards with data-driven component ([078eb6d](https://github.com/MaxPayne89/klass-hero/commit/078eb6daef2cd446e86368bb7b6fbfe350fe5947))
* use Text field for website (URL lacks readonly support) ([29efd0c](https://github.com/MaxPayne89/klass-hero/commit/29efd0cdf29bb4a6d0d1f98f5f2313240d8b8ac1))


### Code Refactoring

* deduplicate check-in/check-out attendance pipeline ([dea884e](https://github.com/MaxPayne89/klass-hero/commit/dea884e9f3596a5b1de5b5daaad6d4fd9fa012a3))
* deduplicate check-in/check-out attendance pipeline into Shared ([fd58df0](https://github.com/MaxPayne89/klass-hero/commit/fd58df056476cd17820790fb493dcb745e961b4f)), closes [#310](https://github.com/MaxPayne89/klass-hero/issues/310)
* derive subscription tier values from SubscriptionTiers ([718a17e](https://github.com/MaxPayne89/klass-hero/commit/718a17e62d6998a9bc75b6ef0bab7c6cf3384090))
* extract publish-and-log boilerplate from PromoteIntegrationEvents ([66720d9](https://github.com/MaxPayne89/klass-hero/commit/66720d90131b92e58a813a55f5812d2361c9e1c5))
* extract publish-and-log boilerplate into shared helpers ([#323](https://github.com/MaxPayne89/klass-hero/issues/323)) ([bd1cb4d](https://github.com/MaxPayne89/klass-hero/commit/bd1cb4dec474585641fdd4f14b639782a605595b))
* extract shared document_page component from legal pages ([d9b35ad](https://github.com/MaxPayne89/klass-hero/commit/d9b35ada9361b3ee6a80aad84f921957ba45c5b2))
* extract shared document_page component from legal pages ([d3bcea4](https://github.com/MaxPayne89/klass-hero/commit/d3bcea4cd7814779ea88ff319653463839c1af3f)), closes [#300](https://github.com/MaxPayne89/klass-hero/issues/300)
* extract shared helpers to ProgramPresenter ([aeb46df](https://github.com/MaxPayne89/klass-hero/commit/aeb46df899f65d013558770d9ca4007cd8c62b62))
* rename gradient to gradient_class in document_page component ([483db53](https://github.com/MaxPayne89/klass-hero/commit/483db5355d925909bfced3a2bdd6bd8efb69a61d))
* use ngettext for Hero heading and add plural test ([32915be](https://github.com/MaxPayne89/klass-hero/commit/32915beb4c31b8185a8235a2680b4226f0517119))

## [0.1.8](https://github.com/MaxPayne89/klass-hero/compare/v0.1.7...v0.1.8) (2026-03-09)


### Features

* update homepage FAQ content (`[#312](https://github.com/MaxPayne89/klass-hero/issues/312)`) ([28a3314](https://github.com/MaxPayne89/klass-hero/commit/28a33142e5b0292bfdb4fa83e4c21175e50194a5))


### Bug Fixes

* match FAQ content exactly to issue [#312](https://github.com/MaxPayne89/klass-hero/issues/312) and add missing items ([39580fb](https://github.com/MaxPayne89/klass-hero/commit/39580fb253bc5e8b6b059617f2aabadc0cfb978b))


### Performance Improvements

* eliminate redundant DB query in ParticipationHistoryLive ([9410a6d](https://github.com/MaxPayne89/klass-hero/commit/9410a6d8d3b3581ca085bbd2a740f2533508bf41))


### Code Refactoring

* remove unused parent_id param from apply_history/4 ([83b7ed6](https://github.com/MaxPayne89/klass-hero/commit/83b7ed6fd03cd7df7b7b4c69d377d5b0ed860217))

## [0.1.7](https://github.com/MaxPayne89/klass-hero/compare/v0.1.6...v0.1.7) (2026-03-08)


### Features

* add broadcast button to roster modal ([1cee319](https://github.com/MaxPayne89/klass-hero/commit/1cee319d7cecdf8cbb2d40700352f4fe3e263fba))
* add broadcast button to roster modal with disabled state ([3f80dee](https://github.com/MaxPayne89/klass-hero/commit/3f80dee6a4849e36c9dd4ffe7c1926869849237b)), closes [#317](https://github.com/MaxPayne89/klass-hero/issues/317)
* add bulk parent profile lookup by IDs to Family context ([de8082d](https://github.com/MaxPayne89/klass-hero/commit/de8082d33654c61457607cdd6fb96de0e3303c7f))
* add ForResolvingParentInfo ACL port and adapter ([b334fac](https://github.com/MaxPayne89/klass-hero/commit/b334facdb81747d4deb46e9ab3365be213e956b8))
* add send individual message button to roster modal ([c35f843](https://github.com/MaxPayne89/klass-hero/commit/c35f8434223b4e44a15a90ecb502bb2a42effd47))
* add send message button to roster with entitlement gating ([9e097a6](https://github.com/MaxPayne89/klass-hero/commit/9e097a64f04ed3824b14ab4354c10cf429b517be))
* include parent_id and parent_user_id in roster entries ([0c8303f](https://github.com/MaxPayne89/klass-hero/commit/0c8303ffe0334a3baf3dd0706d28aa6bb592bdef))


### Bug Fixes

* address PR [#324](https://github.com/MaxPayne89/klass-hero/issues/324) accessibility and HTML validity review comments ([0368979](https://github.com/MaxPayne89/klass-hero/commit/036897987a1bb0d1721684c11e237146fd5cf55a))
* reset session_replication_role after FK bypass in test ([61fdb82](https://github.com/MaxPayne89/klass-hero/commit/61fdb82f1f3628bbee7f18f7580c31e6480da89c))
* validate parent_user_id server-side and add starter tier test ([6c987d2](https://github.com/MaxPayne89/klass-hero/commit/6c987d289d89b10a0220c416511d4113810aaa0d))


### Code Refactoring

* tighten broadcast button comment and test assertions ([2f7676c](https://github.com/MaxPayne89/klass-hero/commit/2f7676c7994e4fe683ca56c93c7fcff04520576f))

## [0.1.6](https://github.com/MaxPayne89/klass-hero/compare/v0.1.5...v0.1.6) (2026-03-08)


### Features

* add admin dashboard link to app navigation ([4121f40](https://github.com/MaxPayne89/klass-hero/commit/4121f40af922f5398431072d6d484adeb28cec9a))
* add admin dashboard with Backpex user management ([e7d5a6c](https://github.com/MaxPayne89/klass-hero/commit/e7d5a6c58efd24e1b97d8fd7c3067f40049ef236))
* add admin layout with Backpex app shell ([47d660f](https://github.com/MaxPayne89/klass-hero/commit/47d660f55148b2c4200a4464d62a6e898799d331))
* add Backpex admin routes and User LiveResource ([3296807](https://github.com/MaxPayne89/klass-hero/commit/3296807077b61544808a074258ec3f5a9200c101))
* add Backpex ThemeSelectorPlug to browser pipeline ([d9bdfb5](https://github.com/MaxPayne89/klass-hero/commit/d9bdfb5e38783168911434b4f4e3f2ea91c59978))
* integrate Backpex CSS sources and JS hooks ([91c8810](https://github.com/MaxPayne89/klass-hero/commit/91c8810442170bf8a52a6af130cf191b04fb41f6))


### Bug Fixes

* address Copilot PR review comments ([ce73fca](https://github.com/MaxPayne89/klass-hero/commit/ce73fca5d465227644fd38a3615db01ae39d1d5a))
* remove duplicate mount_current_scope from admin on_mount ([274175a](https://github.com/MaxPayne89/klass-hero/commit/274175a7499143731634860005dcfb8988cec613))
* scope ThemeSelectorPlug to admin routes only ([31f66c6](https://github.com/MaxPayne89/klass-hero/commit/31f66c6f35460c09d904dcb59ebff2ea7255ded6))


### Code Refactoring

* address admin dashboard review findings ([0aef4e0](https://github.com/MaxPayne89/klass-hero/commit/0aef4e02fae0173ddb30cf4a2b27074b0001a04e))


### Dependencies

* add backpex for admin dashboard ([7f7af12](https://github.com/MaxPayne89/klass-hero/commit/7f7af12a268d62b100caee87548f4c741ee4c60a))

## [0.1.5](https://github.com/MaxPayne89/klass-hero/compare/v0.1.4...v0.1.5) (2026-03-07)


### Bug Fixes

* address PR review comments for get_by_ids/1 ([c368027](https://github.com/MaxPayne89/klass-hero/commit/c36802704dea2be508de31574d79573a486bf11c))
* remove unsupported caller-provided ID test ([a15fe5e](https://github.com/MaxPayne89/klass-hero/commit/a15fe5e123f40642ef3f6869805f63ac503ee093))
* replace brittle String.contains? assertions with non-empty list checks ([291a5f7](https://github.com/MaxPayne89/klass-hero/commit/291a5f7504f3c1b0534f046a271ee3cdb5535b15))
* share provider_id in batch test to validate record_ids scoping ([4f493d5](https://github.com/MaxPayne89/klass-hero/commit/4f493d573e5fa8a7759e6fa3544bb9d663c6111a))


### Performance Improvements

* add LiveView telemetry metrics to LiveDashboard ([1c95353](https://github.com/MaxPayne89/klass-hero/commit/1c953535b6d44b7516cf998f1d80dddf68de63b5))
* batch-load programs in DashboardLive to eliminate N+1 ([e019fc1](https://github.com/MaxPayne89/klass-hero/commit/e019fc129de51e64dbb37a622a56e27b38eb2f3f))
* drop :event tag from handle_event telemetry metric ([258aba5](https://github.com/MaxPayne89/klass-hero/commit/258aba5e87e06cc30b92fe9ea740d2ad26d41d28))

## [0.1.4](https://github.com/MaxPayne89/klass-hero/compare/v0.1.3...v0.1.4) (2026-03-07)


### Features

* **family:** handle cross-context cleanup in DeleteChild ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([6582629](https://github.com/MaxPayne89/klass-hero/commit/65826293a784b7dd723788a530a27c43ab2ba687))
* **liveview:** two-step child deletion with enrollment warning ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([567e3a0](https://github.com/MaxPayne89/klass-hero/commit/567e3a04bfd22d867a3826173d1c592c5671d253))


### Bug Fixes

* add error handling and observability for child deletion ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([af78e18](https://github.com/MaxPayne89/klass-hero/commit/af78e18ec9586441087b9b280d7dd7ce1669a791))
* address architecture review findings for child deletion ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([4b4f860](https://github.com/MaxPayne89/klass-hero/commit/4b4f8601f32fd87b073087d46c4199e535d177e5))
* address critical architecture review findings ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([780bc54](https://github.com/MaxPayne89/klass-hero/commit/780bc549ce3426e6c8335c7aa99413b188ca9a65))
* address important review findings for invite claim processing ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([f2e41a2](https://github.com/MaxPayne89/klass-hero/commit/f2e41a276a670903c01c252fab4a79e1258157ea))
* address PR [#304](https://github.com/MaxPayne89/klass-hero/issues/304) review comments for child deletion ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([de6e214](https://github.com/MaxPayne89/klass-hero/commit/de6e214c02a4840361c394fed600ad3da0f6ef1a))
* address PR review comments for invite claim processing ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([73e5161](https://github.com/MaxPayne89/klass-hero/commit/73e51615cd2e3a865887b58945f1e4af11f3259f))
* address PR review suggestions for child deletion ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([e51960f](https://github.com/MaxPayne89/klass-hero/commit/e51960f03e5088f578f95a6a306c199fb60bdc0c))
* address suggestion-level review findings ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([0a7636f](https://github.com/MaxPayne89/klass-hero/commit/0a7636f9b15aeb36f9865aad8071419047752926))
* cast binary UUIDs to string in remediation script output ([5ae1b76](https://github.com/MaxPayne89/klass-hero/commit/5ae1b76cd8773468db8203786603c7e6a546cb42))
* cast binary UUIDs to string in remediation script output ([3aeb7d7](https://github.com/MaxPayne89/klass-hero/commit/3aeb7d7eef08ccdaa479c42690957277bc757132))
* guard against nil delete_candidate in confirm handler ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([077fc96](https://github.com/MaxPayne89/klass-hero/commit/077fc96373c1570d9bd42f9eed76c9255ee36b4c))
* prevent duplicate child records on invite claim ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([ed9086b](https://github.com/MaxPayne89/klass-hero/commit/ed9086bcd20288d0b5c5e56424851adbb2da2d63))
* two-step child deletion with enrollment cleanup ([#298](https://github.com/MaxPayne89/klass-hero/issues/298)) ([7359d97](https://github.com/MaxPayne89/klass-hero/commit/7359d97059b89dfb1b0bc2ad499aaeb427cdd8ae))


### Code Refactoring

* cleanup post-review for invite claim processing ([#299](https://github.com/MaxPayne89/klass-hero/issues/299)) ([5b9404e](https://github.com/MaxPayne89/klass-hero/commit/5b9404eaf07eef36b5a67fd0e867daf52951f868))

## [0.1.3](https://github.com/MaxPayne89/klass-hero/compare/v0.1.2...v0.1.3) (2026-03-06)


### Features

* add skeleton Trust & Safety page with route and test ([#250](https://github.com/MaxPayne89/klass-hero/issues/250)) ([74cc92e](https://github.com/MaxPayne89/klass-hero/commit/74cc92e284090472164a6ee80454fd552998c4f8))
* add Trust & Safety links to navbar, sidebar, and footer ([#250](https://github.com/MaxPayne89/klass-hero/issues/250)) ([cd5fea5](https://github.com/MaxPayne89/klass-hero/commit/cd5fea534bd2c21f14249a9e3c5523725e7e8272))
* add Trust & Safety page ([#250](https://github.com/MaxPayne89/klass-hero/issues/250)) ([453b726](https://github.com/MaxPayne89/klass-hero/commit/453b7260949e8cd077606abd7bcfadbe8fa35bc3))
* implement full Trust & Safety page content ([#250](https://github.com/MaxPayne89/klass-hero/issues/250)) ([ccc40a5](https://github.com/MaxPayne89/klass-hero/commit/ccc40a57eeb044c02d2e970d9d57b8f0be43eb91))
* update provider vetting to 6-step process across all pages ([98d7879](https://github.com/MaxPayne89/klass-hero/commit/98d78794ad278ddad36ae6d4563775abd47279ca))
* update provider vetting to 6-step process across all pages ([#251](https://github.com/MaxPayne89/klass-hero/issues/251)) ([dfd757e](https://github.com/MaxPayne89/klass-hero/commit/dfd757e87ec9e6f95bd097270009dc1fa80ee0d0))


### Bug Fixes

* address PR review comments for vetting steps ([#251](https://github.com/MaxPayne89/klass-hero/issues/251)) ([10644e8](https://github.com/MaxPayne89/klass-hero/commit/10644e83c768c9fdc4f950cd637ebe75ae5d7be6))
* use consistent Unicode bullet in footer separator ([#250](https://github.com/MaxPayne89/klass-hero/issues/250)) ([e5c3f7c](https://github.com/MaxPayne89/klass-hero/commit/e5c3f7c4f3253976b6722cb7185e4da5e655836f))


### Code Refactoring

* extract repeated icon gradient to module attribute ([#250](https://github.com/MaxPayne89/klass-hero/issues/250)) ([382a2fc](https://github.com/MaxPayne89/klass-hero/commit/382a2fce6460dfa24dc77b929c511b699268721e))

## [0.1.2](https://github.com/MaxPayne89/klass-hero/compare/v0.1.1...v0.1.2) (2026-03-06)


### Bug Fixes

* handle HH:MM:SS time format in program save ([b4d17dc](https://github.com/MaxPayne89/klass-hero/commit/b4d17dc1a0f2f6129d2e58bbd9f5bbf41fe24932))
* handle HH:MM:SS time format in program save ([#282](https://github.com/MaxPayne89/klass-hero/issues/282)) ([3e85491](https://github.com/MaxPayne89/klass-hero/commit/3e854912d62f645a9fe8bc5ce6054b4ac90d03bd))
* normalize qualifications params in save error paths ([e2c2b1f](https://github.com/MaxPayne89/klass-hero/commit/e2c2b1f29bf65ccb6fe9441838958e10f3b817f0))
* normalize qualifications params in save error paths ([57fc0c5](https://github.com/MaxPayne89/klass-hero/commit/57fc0c5cd3782ae73a49072ec3d594bb109b2c28)), closes [#141](https://github.com/MaxPayne89/klass-hero/issues/141)

## [0.1.1](https://github.com/MaxPayne89/klass-hero/compare/v0.1.0...v0.1.1) (2026-03-05)


### Features

* **accounts:** add generate_magic_link_token for invite flow ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([0284584](https://github.com/MaxPayne89/klass-hero/commit/028458417dbde95337c07292d9387ca0d208aebe))
* add ACL adapters bridging Family and ProgramCatalog into Enrollment ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([d33c493](https://github.com/MaxPayne89/klass-hero/commit/d33c493bc9b0c49e450768378251230a860aaf1b))
* add bulk_assign_tokens/1 to invite repository ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([1a5c3f0](https://github.com/MaxPayne89/klass-hero/commit/1a5c3f0d01a601ab09f9f873c3c1365b3cc1f097))
* add bulk_invites_imported event factory ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([5f7d84a](https://github.com/MaxPayne89/klass-hero/commit/5f7d84a35a49149f1198d66679f3537f38359196))
* add BulkEnrollmentInvite domain model ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([4ea1393](https://github.com/MaxPayne89/klass-hero/commit/4ea13937687bbc0a71d6d649f4838ee6d1dfa4a8))
* add BulkEnrollmentInvite mapper ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([22c6815](https://github.com/MaxPayne89/klass-hero/commit/22c681563afb4fbebdc9f5d3b097d5309819a55b))
* add centralized contact info config and helper ([d235dd8](https://github.com/MaxPayne89/klass-hero/commit/d235dd832010c4405220802527686f2cdeaac82d))
* add change_subscription_tier/2 to Provider facade ([00dce82](https://github.com/MaxPayne89/klass-hero/commit/00dce8239d60e8a2fd267dc78b7461761eedbba3))
* add change_tier/2 to ProviderProfile domain model ([afb555c](https://github.com/MaxPayne89/klass-hero/commit/afb555c52ffbc99a58a93e1e98cb42dab9f28071))
* add ChangeSubscriptionTier use case ([302366b](https://github.com/MaxPayne89/klass-hero/commit/302366b7f8a3065d8d880afa0b24ef36e7fa905d))
* add CheckParticipantEligibility use case ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([a4b9711](https://github.com/MaxPayne89/klass-hero/commit/a4b9711db5209ffc8a31fa65e8f237bf0085d416))
* add CheckProviderVerificationStatus domain event handler ([fbd5d5e](https://github.com/MaxPayne89/klass-hero/commit/fbd5d5ed819bfa540ee06369536852f289bde650))
* add ChildInfoACL adapter with DI config ([#145](https://github.com/MaxPayne89/klass-hero/issues/145)) ([00ff136](https://github.com/MaxPayne89/klass-hero/commit/00ff136a75d5261662bf0dc321f2b97c52d4a208))
* add CQRS denormalized read models for ProgramCatalog and Messaging ([291e396](https://github.com/MaxPayne89/klass-hero/commit/291e396636f1b59ab7908a6232689008797a1306))
* add Edit, View Roster, and Preview actions to provider dashboard ([8ae65da](https://github.com/MaxPayne89/klass-hero/commit/8ae65dab0d914b9226bc9ddbfbfd4ddcba5dfb68))
* add enrollment capacity fields to provider program form ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([6835add](https://github.com/MaxPayne89/klass-hero/commit/6835addb2afc734d74245d603b82f1c990eeb2d1))
* add enrollment capacity management ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([299a66e](https://github.com/MaxPayne89/klass-hero/commit/299a66e6fd8ed90896afe5168305dffdcb575e73))
* add EnrollmentCapacityACL for program catalog capacity display ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([71a82b7](https://github.com/MaxPayne89/klass-hero/commit/71a82b73ebbd99c6d304143a8cce433c81a435a0))
* add EnrollmentPolicy domain model ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([867cded](https://github.com/MaxPayne89/klass-hero/commit/867cded265c6424789aee8e2ebc0ce49a1dafc78))
* add EnrollmentPolicy persistence layer ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([c025630](https://github.com/MaxPayne89/klass-hero/commit/c0256308196e1dffadc556a6eacac65357d8df37))
* add event handler to enqueue invite emails after import ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([e3eb650](https://github.com/MaxPayne89/klass-hero/commit/e3eb650661a192d1415ca898a381391df35af3e9))
* add event publishing to Enrollment context for participant policies ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([c2cbd53](https://github.com/MaxPayne89/klass-hero/commit/c2cbd53f7756de17710c9c6d68291e76af1e7665))
* add Family Programs section to parent dashboard ([f5db2f4](https://github.com/MaxPayne89/klass-hero/commit/f5db2f4d7af3fda44833dcc2e0c437a2add1cd98))
* add Family Programs section to parent dashboard ([#154](https://github.com/MaxPayne89/klass-hero/issues/154)) ([1d408e8](https://github.com/MaxPayne89/klass-hero/commit/1d408e88aeb37caab2cce13d3a836fb61d693a1a))
* add ForManagingEnrollmentPolicies port ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([9007dfd](https://github.com/MaxPayne89/klass-hero/commit/9007dfd49e7af7e0f39beaa4229381bb595cf7e1))
* add ForResolvingChildInfo ACL port + list_by_program repo method ([#145](https://github.com/MaxPayne89/klass-hero/issues/145)) ([b21bfdd](https://github.com/MaxPayne89/klass-hero/commit/b21bfdd554986447c7458f35ae0a2641eb81db32))
* add founder section to homepage ([#179](https://github.com/MaxPayne89/klass-hero/issues/179)) ([d94d2b2](https://github.com/MaxPayne89/klass-hero/commit/d94d2b2c1bf4cfe4be845664bcddf4de4929e793))
* add founding story to About page ([#180](https://github.com/MaxPayne89/klass-hero/issues/180)) ([3066b29](https://github.com/MaxPayne89/klass-hero/commit/3066b2976182e9542eff10d1cc09284b8c4e5436))
* add gender and school grade fields to children settings ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([0e20f9b](https://github.com/MaxPayne89/klass-hero/commit/0e20f9bf32324bb21220336ce05a68a945630b2c))
* add gender and school_grade fields to Child ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([ffe2eed](https://github.com/MaxPayne89/klass-hero/commit/ffe2eedfb59679fb7ece0eee7e304db4e651ea0f))
* add get_by_id/1 to invite repository ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([1d2a2fd](https://github.com/MaxPayne89/klass-hero/commit/1d2a2fdc0e871a3db2049f54235cc74387889d29))
* add icon_name/1 mapping categories to heroicons ([a79302d](https://github.com/MaxPayne89/klass-hero/commit/a79302d1a72f63fcc4d27e0b040d2d4415232e54))
* add invite email port and notifier adapter ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([b0ecacb](https://github.com/MaxPayne89/klass-hero/commit/b0ecacb9ed749f712b9b15b07e69e3f633841b8e))
* add list_pending_without_token/1 to invite repository ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([f57e01e](https://github.com/MaxPayne89/klass-hero/commit/f57e01e4e33b214324bca899af6ee2637052ebbb))
* add ListProgramEnrollments use case with TDD tests ([#145](https://github.com/MaxPayne89/klass-hero/issues/145)) ([b2730a0](https://github.com/MaxPayne89/klass-hero/commit/b2730a00f6d8f72414a69bac2c844cae458bf5c8))
* add Oban worker for sending invite emails ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([59d14fc](https://github.com/MaxPayne89/klass-hero/commit/59d14fc30292c9406920115b7cdd64376e95e5e9))
* add participant restrictions form to provider dashboard ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([49506bb](https://github.com/MaxPayne89/klass-hero/commit/49506bb17ce19445ad2607ffc6e873de37eb5b5d))
* add ParticipantPolicy domain model with eligibility logic ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([0cab7af](https://github.com/MaxPayne89/klass-hero/commit/0cab7af1543b5591c5f74ba48b7a11ef6ccf443e))
* add ParticipantPolicy persistence layer ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([877374f](https://github.com/MaxPayne89/klass-hero/commit/877374f93300840c98b7f9de5b611b56c5d45057))
* add program_schedule_updated event and update event payloads ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([7dec257](https://github.com/MaxPayne89/klass-hero/commit/7dec257db596decd7e429203158d87a852e1d42e))
* add Program.create/1 factory and apply_changes/2 with business invariant validation ([b755857](https://github.com/MaxPayne89/klass-hero/commit/b755857c23bcdbf4d24e2323b41cb31255c2f2a9))
* add provider subscription management page ([58e07fc](https://github.com/MaxPayne89/klass-hero/commit/58e07fc17f5bf43f6d76aa97417e3dfe890d0d58))
* add registration period fields to programs schema ([#147](https://github.com/MaxPayne89/klass-hero/issues/147)) ([220ef8c](https://github.com/MaxPayne89/klass-hero/commit/220ef8ca72787d08af72b048b09e4f7d47bc7a3d))
* add registration period for programs ([#147](https://github.com/MaxPayne89/klass-hero/issues/147)) ([2982769](https://github.com/MaxPayne89/klass-hero/commit/298276977def074945f30091a548e4fe44f05354))
* add registration period inputs to provider program form ([#147](https://github.com/MaxPayne89/klass-hero/issues/147)) ([4b0c3d0](https://github.com/MaxPayne89/klass-hero/commit/4b0c3d017f529d893c880fdab192bbd02f69b32a))
* add registration_period to Program domain model ([#147](https://github.com/MaxPayne89/klass-hero/issues/147)) ([515e923](https://github.com/MaxPayne89/klass-hero/commit/515e9235bc1d7544d7be0376aade8abe67488a40))
* add RegistrationPeriod value object ([#147](https://github.com/MaxPayne89/klass-hero/issues/147)) ([61a9e2d](https://github.com/MaxPayne89/klass-hero/commit/61a9e2d5fde3f1ded1ba51e58dcb44acc713c03d))
* add schedule formatting to ProgramPresenter ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([7ed4967](https://github.com/MaxPayne89/klass-hero/commit/7ed49679f3d92380671fb74c135032ff29b4e268))
* add scheduling fields migration ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([6538603](https://github.com/MaxPayne89/klass-hero/commit/6538603a77960508e7677a2dd6afd378fbff2ba7))
* add scheduling fields to Program domain model ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([eb5a006](https://github.com/MaxPayne89/klass-hero/commit/eb5a0063bd22844196afc76aad61f256f5f50bde))
* add scheduling fields to ProgramSchema ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([eadaff9](https://github.com/MaxPayne89/klass-hero/commit/eadaff92c8018fc5bef12ec40b53bbffe0ca0764))
* add scheduling fields to provider program form ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([7a3e1b4](https://github.com/MaxPayne89/klass-hero/commit/7a3e1b4cd19dcaeb67e4fa6b2780ca2b458faa56))
* add structured scheduling fields to programs ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([3f11f5c](https://github.com/MaxPayne89/klass-hero/commit/3f11f5c9e3ea63c09d419cb5d81c4373af967268))
* add subscription CTA banner to provider dashboard ([562e038](https://github.com/MaxPayne89/klass-hero/commit/562e038891e8212c05ef5fc681b162e7b0958789))
* add subscription upgrade path for providers ([cf7ed19](https://github.com/MaxPayne89/klass-hero/commit/cf7ed198aae24faf1ab18820ce5b97bbd5dc0096))
* add tier selector to provider registration flow ([5fa952d](https://github.com/MaxPayne89/klass-hero/commit/5fa952db590b648d2ccc8325c29c970524d641bc))
* add to_card_view/1 to ProgramPresenter ([#154](https://github.com/MaxPayne89/klass-hero/issues/154)) ([cb9456b](https://github.com/MaxPayne89/klass-hero/commit/cb9456bd2b2507c8b515a866d2a5050466e5cbd3))
* add transition_status/2 to invite repository ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([5d67a2f](https://github.com/MaxPayne89/klass-hero/commit/5d67a2f5f1559cbbbc316f9b04c8ad37f6257850))
* add UpdateProgram use case, update dashboard for aggregate pattern, fix test breakage ([3f338e0](https://github.com/MaxPayne89/klass-hero/commit/3f338e09e31c1d0160382b7c7b48a64168e8a470))
* add View Roster modal with enrollment display ([#145](https://github.com/MaxPayne89/klass-hero/issues/145)) ([65ebe1e](https://github.com/MaxPayne89/klass-hero/commit/65ebe1eb974a0c242a7e4238a31ae531364d3683))
* **app:** wire invite claim saga handlers in supervision tree ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([4264846](https://github.com/MaxPayne89/klass-hero/commit/42648460ffb43a9acc079dee95b359021792a244))
* BookingLive uses enrollment capacity instead of spots_available ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([9746215](https://github.com/MaxPayne89/klass-hero/commit/97462151dc4725ac0e86c41cc9d716afa10883dc))
* bulk enrollment invite email pipeline ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([52956a4](https://github.com/MaxPayne89/klass-hero/commit/52956a4ba33ac96c0149059d27a77c4fb37d5303))
* dispatch domain event on document approval ([061f539](https://github.com/MaxPayne89/klass-hero/commit/061f539e545b8fa2cfbbfd8f8321fdf6d2e6be35))
* dispatch domain event on document rejection ([950ba80](https://github.com/MaxPayne89/klass-hero/commit/950ba80227c4ddefdc467cdf13a1b368d7551146))
* display participant restrictions on program detail page ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([e6f37a7](https://github.com/MaxPayne89/klass-hero/commit/e6f37a7b9e512743b045774f50f69085c5260e32))
* enforce max capacity in CreateEnrollment use case ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([0fdd50b](https://github.com/MaxPayne89/klass-hero/commit/0fdd50b04026318692fe1d6f82da4eb00cb85382))
* enforce participant eligibility in CreateEnrollment ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([d2a0eee](https://github.com/MaxPayne89/klass-hero/commit/d2a0eeed2adb5020a2fa36f8c98c59e73b385499))
* **enrollment:** add BulkEnrollmentInvite schema ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([743fd73](https://github.com/MaxPayne89/klass-hero/commit/743fd73a9d149b18d7c181bb0d9a2b61f3da2018))
* **enrollment:** add BulkEnrollmentInviteRepository adapter ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([9ae88bc](https://github.com/MaxPayne89/klass-hero/commit/9ae88bc94d4460276405a6b49866e70bc3d26652))
* **enrollment:** add claim_invite to public API ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([e344f00](https://github.com/MaxPayne89/klass-hero/commit/e344f00791e682080402b3fc1030039996e2d4a5))
* **enrollment:** add ClaimInvite use case ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([bdf1777](https://github.com/MaxPayne89/klass-hero/commit/bdf1777db33021acdf0133defa3c4f0cab15bc5a))
* **enrollment:** add count_by_program and delete to invite repository ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([601b849](https://github.com/MaxPayne89/klass-hero/commit/601b8494560618d92a9065ef4b78519c4f1f37cb))
* **enrollment:** add CSV import controller endpoint ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([e583d46](https://github.com/MaxPayne89/klass-hero/commit/e583d46b53caaa119fda7831b9d9d364ef86299e))
* **enrollment:** add CSV import template for download ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([8cf23e9](https://github.com/MaxPayne89/klass-hero/commit/8cf23e95ba28162fcf58f5262a4af2e00a7fb274))
* **enrollment:** add CsvParser domain service ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([fc20cb4](https://github.com/MaxPayne89/klass-hero/commit/fc20cb49a7e5c65af30d9b5b886a95165d98bd5b))
* **enrollment:** add DeleteInvite use case ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([466359e](https://github.com/MaxPayne89/klass-hero/commit/466359ed79dd17a5d1abda3fee3368313aede685))
* **enrollment:** add get_by_token to invite repository ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([a5553d6](https://github.com/MaxPayne89/klass-hero/commit/a5553d60e886d8d5e1f56c527ea0a216284cb0f5))
* **enrollment:** add import_changeset and transition_changeset with state machine ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([f83a5eb](https://github.com/MaxPayne89/klass-hero/commit/f83a5eb34052dab6af84e3383da6c167d0fd5b3f))
* **enrollment:** add ImportEnrollmentCsv use case ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([d65395c](https://github.com/MaxPayne89/klass-hero/commit/d65395c33ffc08bf2a6009fb81d2b18fd5f0b3fe))
* **enrollment:** add ImportRowValidator domain service ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([2c58d00](https://github.com/MaxPayne89/klass-hero/commit/2c58d0060f17336221851b286d5135c5742dff10))
* **enrollment:** add invite_claimed domain + integration events ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([d6435ff](https://github.com/MaxPayne89/klass-hero/commit/d6435ff4f1bff68322a5e5861a951ad48e55be0c))
* **enrollment:** add InviteFamilyReadyHandler for enrollment creation ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([c5d814b](https://github.com/MaxPayne89/klass-hero/commit/c5d814b92e7d636fb970e2fa4f6eaf8812459807))
* **enrollment:** add list_by_program to invite repository ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([9076882](https://github.com/MaxPayne89/klass-hero/commit/9076882bfccf5c5b9fe16d652a80b43b455e5ced))
* **enrollment:** add ListProgramInvites use case ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([e2e8305](https://github.com/MaxPayne89/klass-hero/commit/e2e8305c602304b6b29a899827ebed576aecbae0))
* **enrollment:** add MarkInviteRegistered domain event handler ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([c7efbdb](https://github.com/MaxPayne89/klass-hero/commit/c7efbdb6495499902b4f4a19c80dd2a5ee8a79f2))
* **enrollment:** add password note to invite email template ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([bdab6a3](https://github.com/MaxPayne89/klass-hero/commit/bdab6a3d74b44db22f465a503ab34d553529204d))
* **enrollment:** add ports for bulk invite storage and program catalog lookup ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([816fcc0](https://github.com/MaxPayne89/klass-hero/commit/816fcc0de82b74a3d6179245c1bbcff76cee28bc))
* **enrollment:** add ProgramCatalogACL for cross-context program lookup ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([1e48232](https://github.com/MaxPayne89/klass-hero/commit/1e482323c698eb347de82289531a7acddf1bef29))
* **enrollment:** add ResendInvite use case ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([550437a](https://github.com/MaxPayne89/klass-hero/commit/550437a5dda8d0292f509a63476d62f1970d44df))
* **enrollment:** add reset_for_resend to invite repository ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([98da02d](https://github.com/MaxPayne89/klass-hero/commit/98da02d7f0982926849c801d0485a52dd1348a45))
* **enrollment:** bulk enrollment invite management UI ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([6e00600](https://github.com/MaxPayne89/klass-hero/commit/6e00600d5d250b8fc0c499d47ee086bb0905926a))
* **enrollment:** CSV bulk import backend ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([dc868d8](https://github.com/MaxPayne89/klass-hero/commit/dc868d8b32c943c6eb9dba2614a64dba257c806c))
* **enrollment:** expose import_enrollment_csv on context facade ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([d5419d3](https://github.com/MaxPayne89/klass-hero/commit/d5419d3a7fabc3ebbf42b8d3cd50e6997bbb8997))
* **enrollment:** expose invite management functions on facade ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([e8a2a63](https://github.com/MaxPayne89/klass-hero/commit/e8a2a63164f74bcb79c4e16d88d768ef0bdb8c70))
* **enrollment:** promote invite_claimed to integration event ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([39a0906](https://github.com/MaxPayne89/klass-hero/commit/39a090605da2be1261e6d2cf8e7cc91107e08796))
* extend program_card with expired/contact attrs and date range display ([b12ccb7](https://github.com/MaxPayne89/klass-hero/commit/b12ccb7f7c45e3a1d872c75b727fe7058c20d29c)), closes [#154](https://github.com/MaxPayne89/klass-hero/issues/154)
* **family:** add children_guardians join table ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([7b5732d](https://github.com/MaxPayne89/klass-hero/commit/7b5732d1b510cf9df2a65c016dadb3448998cfca))
* **family:** add invite_family_ready domain + integration events ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([ef3a7d6](https://github.com/MaxPayne89/klass-hero/commit/ef3a7d6d6f2ef2c1bb47563df01035a701d3bf74))
* **family:** add InviteClaimedHandler for child creation from invite ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([e0f2846](https://github.com/MaxPayne89/klass-hero/commit/e0f28461ce4f63958d9bd7fbc7b039a7721f9512))
* **family:** add primary guardian uniqueness and relationship constraints ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([3eb2365](https://github.com/MaxPayne89/klass-hero/commit/3eb2365b7ef7fc0c713e4bd67cda2db5189281a7))
* **family:** add school_name field to Child ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([db772ae](https://github.com/MaxPayne89/klass-hero/commit/db772aebd232c63b0e78ecd49f99c5784ba5b1fd))
* **family:** promote invite_family_ready to integration event ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([9d46f52](https://github.com/MaxPayne89/klass-hero/commit/9d46f52b30b8cdef116f4eea9e336a9bd7f21ddb))
* **family:** split photo consent into photo_marketing and photo_social_media ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([9ae608e](https://github.com/MaxPayne89/klass-hero/commit/9ae608e46ab9721a57c330def9a32ff8fcf7fa9f))
* gate booking flow on registration period ([#147](https://github.com/MaxPayne89/klass-hero/issues/147)) ([cfec8e8](https://github.com/MaxPayne89/klass-hero/commit/cfec8e8cec50d1ed87fe8833c1d82335f9947998))
* invite claim & auto-registration saga ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([9bd1f2f](https://github.com/MaxPayne89/klass-hero/commit/9bd1f2f85cb257dce2b0f1305c7b47a04010878d))
* map registration period between domain and schema ([#147](https://github.com/MaxPayne89/klass-hero/issues/147)) ([b4d2571](https://github.com/MaxPayne89/klass-hero/commit/b4d2571c088a6941c1f0441694bdfb0002bb2dda))
* **messaging:** add conversation_summaries read model table ([2f6f9ee](https://github.com/MaxPayne89/klass-hero/commit/2f6f9ee8bb036ba9cf8ea886062ce69bbfcd2f21))
* **messaging:** add ConversationSummariesProjection GenServer ([876a99b](https://github.com/MaxPayne89/klass-hero/commit/876a99bda48015a4d228c2ef4f192ab9e5a7af69))
* **messaging:** add ConversationSummary read DTO and Ecto schema ([3280ab5](https://github.com/MaxPayne89/klass-hero/commit/3280ab50e2b22f2659bd8eb5f8f70bddf73be43e))
* **messaging:** add integration event promotions for CQRS projections ([60644b3](https://github.com/MaxPayne89/klass-hero/commit/60644b3ea9e5caf4d65920df8eb0d351fed87ff3))
* **messaging:** add read port and ConversationSummariesRepository ([185c256](https://github.com/MaxPayne89/klass-hero/commit/185c256b60caab0bbc85d88bcb41b6dc88862ec2))
* pass subscription tier through registration event to provider creation ([cd4d190](https://github.com/MaxPayne89/klass-hero/commit/cd4d19086163684a0bf81f2a49606abf3a3117d6))
* **program_catalog:** add season field to Program ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([a7f22b9](https://github.com/MaxPayne89/klass-hero/commit/a7f22b91b3ae47d7f1c2ff97a7960616049fad06))
* **program-catalog:** add program_listings read model table ([ab21638](https://github.com/MaxPayne89/klass-hero/commit/ab21638ad110da7abb87a925f8ed1ec239e8f76d))
* **program-catalog:** add program_updated domain event for CQRS projections ([c262d1b](https://github.com/MaxPayne89/klass-hero/commit/c262d1b1cc8dc094891ecf2b5e56563c22f2c3a3))
* **program-catalog:** add program_updated integration event promotion ([69877ce](https://github.com/MaxPayne89/klass-hero/commit/69877ceaf10d15d85ab7c61b8baf5c1347a8a085))
* **program-catalog:** add ProgramListing read DTO and Ecto schema ([e88e1ba](https://github.com/MaxPayne89/klass-hero/commit/e88e1bafb5bf98c36cfd8e22b028e315f14c8204))
* **program-catalog:** add ProgramListingsProjection GenServer ([b5ba209](https://github.com/MaxPayne89/klass-hero/commit/b5ba209d5340de806666a83d1be4ed10ec95ff88))
* **program-catalog:** add read port and ProgramListingsRepository ([e61069e](https://github.com/MaxPayne89/klass-hero/commit/e61069e13993ebc0c12b00fff02b0897b99c96e1))
* publish bulk_invites_imported event after CSV import ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([194be2f](https://github.com/MaxPayne89/klass-hero/commit/194be2f9b45256fc21087e7dc3ef60f0ed382cda))
* publish domain event on subscription tier change ([a7b4968](https://github.com/MaxPayne89/klass-hero/commit/a7b4968e53d66f6267e0dcaff57c5ae3784361ed))
* publish domain event on subscription tier change ([#271](https://github.com/MaxPayne89/klass-hero/issues/271)) ([53f3e10](https://github.com/MaxPayne89/klass-hero/commit/53f3e10a19901c6619bded3614b7d1ab8b6b5275))
* register invite email handler on enrollment event bus ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([cd9bf85](https://github.com/MaxPayne89/klass-hero/commit/cd9bf85bb9aaf29bd8bfdd2d3d70d5d1714b67a0))
* register verification status handlers on Provider DomainEventBus ([3c08d87](https://github.com/MaxPayne89/klass-hero/commit/3c08d870db772ee48a6507007e2a8f49569584b0))
* render cover image in program detail hero with gradient fallback ([99b45b3](https://github.com/MaxPayne89/klass-hero/commit/99b45b35ba0b5ce7011ff3614470ca4ee0bc4f1d))
* render cover image on program card with gradient fallback ([b8b28b6](https://github.com/MaxPayne89/klass-hero/commit/b8b28b6eeceb798c256230252bb924e1e0c08ecf)), closes [#196](https://github.com/MaxPayne89/klass-hero/issues/196)
* show eligibility feedback in booking flow ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([dd1f2e7](https://github.com/MaxPayne89/klass-hero/commit/dd1f2e74779f635925818e21620d48e584e8251f))
* show registration status on program detail page ([#147](https://github.com/MaxPayne89/klass-hero/issues/147)) ([16446ca](https://github.com/MaxPayne89/klass-hero/commit/16446ca5a10ad04d3475a7f7a3ad46c6828dccc2))
* switch read use cases to CQRS read models ([581c283](https://github.com/MaxPayne89/klass-hero/commit/581c2836fe9f010f4bfe5746337205cff9caa110))
* update program display to use structured scheduling fields ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([3b363f0](https://github.com/MaxPayne89/klass-hero/commit/3b363f01fb9b6ac266543158c33d6b5a99d6fa01))
* update ProgramMapper for scheduling fields ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([5e6fb91](https://github.com/MaxPayne89/klass-hero/commit/5e6fb91a2447c9619a84fab20979af608cdcbd99))
* update test factories for scheduling fields ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([3bc86d6](https://github.com/MaxPayne89/klass-hero/commit/3bc86d667139fd65288df17e103cdf727f30ca4f))
* **web:** add InviteClaimController and /invites/:token route ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([12eab68](https://github.com/MaxPayne89/klass-hero/commit/12eab68689987862cf723bde310097bde28d66e8))
* **web:** add tabbed roster modal with invites, CSV upload, and actions ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([752934f](https://github.com/MaxPayne89/klass-hero/commit/752934f31e3ba357621b581379353e5bbf17ad6b))
* wire Edit button with modal reuse and UpdateProgram ([#145](https://github.com/MaxPayne89/klass-hero/issues/145)) ([51c0fdb](https://github.com/MaxPayne89/klass-hero/commit/51c0fdb24a49eadbdb776d9756e5d3fb319285b0))
* wire EnrollmentPolicy into config and context facade ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([aa1bb29](https://github.com/MaxPayne89/klass-hero/commit/aa1bb29b1caf8bf3c27f6269c9cd8d0ab260a95a))
* wire Preview link, add phx-click to Edit/Roster, remove Duplicate ([#145](https://github.com/MaxPayne89/klass-hero/issues/145)) ([7cba154](https://github.com/MaxPayne89/klass-hero/commit/7cba154a449ce71fe6d126d709ef8a0b94f75e62))


### Bug Fixes

* add :warning flash kind to fix silently swallowed warnings ([7fb7697](https://github.com/MaxPayne89/klass-hero/commit/7fb76975adf037e671ea2e0e96dcb6cfc1fec085))
* add active-state feedback to provider dashboard buttons ([3a212ee](https://github.com/MaxPayne89/klass-hero/commit/3a212eeb88b22213e3982f1e8e98447d0e3b98b5))
* add active-state press feedback to provider dashboard buttons ([b7e30b6](https://github.com/MaxPayne89/klass-hero/commit/b7e30b6a0c3c72350705d4242e5d4eebeecd9930)), closes [#143](https://github.com/MaxPayne89/klass-hero/issues/143)
* add case-collision detection and gettext field labels in CSV import ([58869f8](https://github.com/MaxPayne89/klass-hero/commit/58869f846f3a7660e830e09594535b87658b02a9))
* add contents read permission to Security workflow ([f7f01d2](https://github.com/MaxPayne89/klass-hero/commit/f7f01d2936512c7f36fc29d77424abcf6235719a))
* add downloads dir to static paths for CSV template serving ([c3c1731](https://github.com/MaxPayne89/klass-hero/commit/c3c1731e1b1cfd3e756f761acb3183f23743aa26)), closes [#224](https://github.com/MaxPayne89/klass-hero/issues/224)
* add missing Logger metadata keys for enrollment import ([bac8c86](https://github.com/MaxPayne89/klass-hero/commit/bac8c8627804fd90edca0a1f0b1683320e51f0eb))
* add missing Logger metadata keys for upload crash logging ([d3e01eb](https://github.com/MaxPayne89/klass-hero/commit/d3e01ebf7114eb17459ef31eeeab07fb79ccb242))
* add missing Logger metadata keys to formatter whitelist ([c47df3d](https://github.com/MaxPayne89/klass-hero/commit/c47df3d171d3e6271a5d45734443f015d0baf5fa))
* add nil guards for booking config and price formatting ([cb7ec12](https://github.com/MaxPayne89/klass-hero/commit/cb7ec123272d2db4fc471e19594e2c834bde5e30))
* add security-events write permission to Security workflow ([e17d85f](https://github.com/MaxPayne89/klass-hero/commit/e17d85f03c468687d9b6c93064a7db9907fbedba))
* add security-events write permission to Security workflow ([4605aef](https://github.com/MaxPayne89/klass-hero/commit/4605aefb815a03c574a6bcc78382e57984035a73)), closes [#268](https://github.com/MaxPayne89/klass-hero/issues/268)
* address CQRS review issues I1–I10 ([c66b612](https://github.com/MaxPayne89/klass-hero/commit/c66b612e1225d9ce0ab7cecd7c556e2b2d4b019d))
* address CQRS review suggestions S2–S8 ([8436d27](https://github.com/MaxPayne89/klass-hero/commit/8436d27a141bd9f57242ca55de690d71510e8251))
* address critical and important architecture review findings ([91c0834](https://github.com/MaxPayne89/klass-hero/commit/91c083434ce6b2d4653f814fc4a0e59e79ad6799))
* address PR [#197](https://github.com/MaxPayne89/klass-hero/issues/197) review comments on invite email pipeline ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([1bc431d](https://github.com/MaxPayne89/klass-hero/commit/1bc431d378f8d46bf5cfd5fb007a53fdcdd8e333))
* address PR [#210](https://github.com/MaxPayne89/klass-hero/issues/210) review comments on CQRS projections ([efc1f1f](https://github.com/MaxPayne89/klass-hero/commit/efc1f1f0ee8e10b8c9f450edf047e308e7e02c69))
* address PR [#252](https://github.com/MaxPayne89/klass-hero/issues/252) review comments ([18d2f64](https://github.com/MaxPayne89/klass-hero/commit/18d2f6424aa3be59ab6bbe307a10060cbc4f5276))
* address PR review — add tier error display and use shared test helper ([8f02fb9](https://github.com/MaxPayne89/klass-hero/commit/8f02fb9e34579347073ad629d5eececd766dc8b4))
* address PR review — guard tier functions and fix i18n in format_media ([b0708e2](https://github.com/MaxPayne89/klass-hero/commit/b0708e23a6144845cdb4ab65fa51c75bccd5697a))
* address PR review feedback for invite claim saga ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([649e4fd](https://github.com/MaxPayne89/klass-hero/commit/649e4fdc4f2d3e9285b1e47af3b35214d965dd89))
* address PR review feedback on icon_path removal ([4940490](https://github.com/MaxPayne89/klass-hero/commit/4940490aedf6935954f43be15ccfa0532dc5db47))
* address PR review feedback on icon_path removal ([ffed2ad](https://github.com/MaxPayne89/klass-hero/commit/ffed2ad8c08a6397a42bcf906f400c7d71912cdf))
* address suggestion-level architecture review findings ([#8](https://github.com/MaxPayne89/klass-hero/issues/8)-25) ([3e99e08](https://github.com/MaxPayne89/klass-hero/commit/3e99e080e8db56241d24a28a9cf5f913f9e35b80))
* align test names with assertions in dashboard tests ([0e8e866](https://github.com/MaxPayne89/klass-hero/commit/0e8e86610b531ae314269a6085d95bd1acbc74f5))
* auto-verify/unverify provider on document review ([3b3a306](https://github.com/MaxPayne89/klass-hero/commit/3b3a306ee0af8d730cf780e86e5fdbd2e1a7ebc5))
* clear textarea after sending message ([5c8169f](https://github.com/MaxPayne89/klass-hero/commit/5c8169f0fffa080725a86d2a1381a46e3c0ea441))
* clear textarea value after sending message ([747c26b](https://github.com/MaxPayne89/klass-hero/commit/747c26bdf06d507b3f28631de66edb1017dca7f3)), closes [#228](https://github.com/MaxPayne89/klass-hero/issues/228)
* consolidate nil fallback and untrack beads backup artifacts ([14d2c3b](https://github.com/MaxPayne89/klass-hero/commit/14d2c3bee11c99d255c831a0e5acfaa31c6c2fe8))
* CSV template download returns 404 ([13d2abe](https://github.com/MaxPayne89/klass-hero/commit/13d2abe9d4ad25e0e9a1aed54fb339784f8728ae))
* display cover image on program cards and detail page ([22a12ae](https://github.com/MaxPayne89/klass-hero/commit/22a12ae05fd461179dcb72671a34fca95a1fc3be))
* eliminate SQL string interpolation in bulk_assign_tokens ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([463894c](https://github.com/MaxPayne89/klass-hero/commit/463894cd953dd311bffff7b6ba27965b8f536795))
* **enrollment:** address PR [#199](https://github.com/MaxPayne89/klass-hero/issues/199) review comments — authz, scoping, docs ([0dc3d68](https://github.com/MaxPayne89/klass-hero/commit/0dc3d684710e8ea336b7051b19877976f55c858c))
* **enrollment:** address PR review findings ([#195](https://github.com/MaxPayne89/klass-hero/issues/195)) ([49a6716](https://github.com/MaxPayne89/klass-hero/commit/49a6716e8281cc800a3601111ac55f7449dd66f5))
* **enrollment:** address test-drive findings — mobile table, dev URLs, CSV hint ([37180b3](https://github.com/MaxPayne89/klass-hero/commit/37180b3be2cd506b9af29ca48a62290afd3f6268))
* **enrollment:** correct behaviour, aggregate type, and handler priority in invite claim saga ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([be9fe20](https://github.com/MaxPayne89/klass-hero/commit/be9fe200ffc2a4e60a1e6940ca13caf9bad5c610))
* **enrollment:** handle malformed CSV and case-insensitive booleans ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([8cc16a3](https://github.com/MaxPayne89/klass-hero/commit/8cc16a3c3a0d042e5af6cfc0782cadf9cb09b716))
* **enrollment:** harden CSV import helpers with tagged tuples and UUID guard ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([adee78a](https://github.com/MaxPayne89/klass-hero/commit/adee78a6e2d3eb2cc1ba55e5b87207fa66ec3218))
* **enrollment:** harden error handling, config, and event semantics ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([88933dc](https://github.com/MaxPayne89/klass-hero/commit/88933dc7c987c8ec51e3b2a62997f2f0641b5f3f))
* **enrollment:** make bulk invite unique index case-insensitive ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([2f7cd12](https://github.com/MaxPayne89/klass-hero/commit/2f7cd124aa6f3aea75eebf499061012e0c422c4e))
* **enrollment:** preserve row index in batch errors, guard empty programs ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([e4718c4](https://github.com/MaxPayne89/klass-hero/commit/e4718c47b3d0f2b2bbf2ce4abbf41d15b58728ad))
* **enrollment:** remove silent nil fallback on program.price ([#195](https://github.com/MaxPayne89/klass-hero/issues/195)) ([631e3da](https://github.com/MaxPayne89/klass-hero/commit/631e3da3bca11cc4b8c869bd39e83a125cf5dace))
* **enrollment:** replace bare pattern matches with proper error handling ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([a3ef4e9](https://github.com/MaxPayne89/klass-hero/commit/a3ef4e90b3882eb48f9de0ca91ff805693592676))
* **enrollment:** simplify pricing to use program.price directly ([#195](https://github.com/MaxPayne89/klass-hero/issues/195)) ([5a53b0d](https://github.com/MaxPayne89/klass-hero/commit/5a53b0d0e57c3e16c500420d73a8485db1bdf0c0))
* **enrollment:** use program.price directly as total ([#195](https://github.com/MaxPayne89/klass-hero/issues/195)) ([053fb26](https://github.com/MaxPayne89/klass-hero/commit/053fb26ad225356cd68337df3a792f17e416b86e))
* export shared NotifyLiveViews from Shared boundary ([3c05883](https://github.com/MaxPayne89/klass-hero/commit/3c05883ab4a9cfea794348d9866f45d138669664))
* flash messages hidden under navbar ([80b25d6](https://github.com/MaxPayne89/klass-hero/commit/80b25d679769a374f9a2f05a3b73009ca1d9cd7c))
* handle BOM, case-insensitive programs, and error labels in CSV import ([e0def48](https://github.com/MaxPayne89/klass-hero/commit/e0def4847ff6f2283ee6677bc080dc6ca1817665))
* handle BOM, case-insensitive programs, and error labels in CSV import ([caafdf5](https://github.com/MaxPayne89/klass-hero/commit/caafdf51a17712f45485f8397df1ac1731f15922)), closes [#243](https://github.com/MaxPayne89/klass-hero/issues/243)
* handle nil other_participant_name in conversation_card component ([70c13a6](https://github.com/MaxPayne89/klass-hero/commit/70c13a670f920f310c08f6fff3c26c26707a7b58))
* handle nil other_participant_name in conversation_card component ([787510e](https://github.com/MaxPayne89/klass-hero/commit/787510e88b4cacf9e3a0534f09eae2f125d5d861)), closes [#241](https://github.com/MaxPayne89/klass-hero/issues/241)
* harden CQRS projections against data loss, crashes, and unsafe ops ([3d64dec](https://github.com/MaxPayne89/klass-hero/commit/3d64decd314c2a456a6bcb28cd38deef55bf1be5))
* improve date range display and whitespace handling ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([dd43034](https://github.com/MaxPayne89/klass-hero/commit/dd430346cadd40380fad7c95f7e394b540378c97))
* improve observability for silent failure locations ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([212dce5](https://github.com/MaxPayne89/klass-hero/commit/212dce586ca187e2ca6176bce3fb82e664794a1c))
* include cover_image_url in programs listing map ([f1d9926](https://github.com/MaxPayne89/klass-hero/commit/f1d99267190340c2d10601e07c0e66603bb25639))
* include headshot_url in staff member edit changeset ([#231](https://github.com/MaxPayne89/klass-hero/issues/231)) ([eb8bf20](https://github.com/MaxPayne89/klass-hero/commit/eb8bf20a5b7b545ec0dc9e5b87b2a015cbdd75c9))
* log nil subscription tier fallback and test same_tier handler ([7d31dfb](https://github.com/MaxPayne89/klass-hero/commit/7d31dfb7e23128bab16449ddad41965bb9e1958e))
* **messaging:** exclude own messages from unread count in bootstrap ([3da5778](https://github.com/MaxPayne89/klass-hero/commit/3da5778364d58e6dab7267c0d3d5b12e9cdfa86c))
* move extracted staff helpers after all handle_event clauses ([bedde02](https://github.com/MaxPayne89/klass-hero/commit/bedde02105cc4b88b2d051cf45afbb9f63b1c2a8))
* normalize qualifications string before changeset in validate_staff ([c6c75b5](https://github.com/MaxPayne89/klass-hero/commit/c6c75b510b7122e2cc85431d0980a76cabac9ebd))
* normalize qualifications string before changeset in validate_staff ([08ef58e](https://github.com/MaxPayne89/klass-hero/commit/08ef58ee224727b97b29f23d97178c4950227442)), closes [#142](https://github.com/MaxPayne89/klass-hero/issues/142)
* preserve enrollment count after program edit ([#145](https://github.com/MaxPayne89/klass-hero/issues/145)) ([c40c361](https://github.com/MaxPayne89/klass-hero/commit/c40c361560db8bb60fa88360720f4d3962b5aaea))
* prevent phantom capacity display on failed policy save ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([b46b4b4](https://github.com/MaxPayne89/klass-hero/commit/b46b4b40d2be98e18f4205a20ce8a1fd05df70db))
* **program-catalog:** use VerifiedProviders for bootstrap provider_verified ([ea4492a](https://github.com/MaxPayne89/klass-hero/commit/ea4492a3dd49c41b882debb447892dd39e9065db))
* propagate handler errors + dedup test fixtures ([9d7bca8](https://github.com/MaxPayne89/klass-hero/commit/9d7bca8d08784d416ae72df7441d9231bcb4d48d))
* remove catch-all handle_info from messaging LiveView macros ([632b64d](https://github.com/MaxPayne89/klass-hero/commit/632b64d57f3dacacbcc0ce73db53c5a7415ca15c))
* remove dead [@current](https://github.com/current)_user assign from BookingLive ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([46bed14](https://github.com/MaxPayne89/klass-hero/commit/46bed14c4298226754c975bf4f401061df724abd))
* remove Ecto.Changeset type from domain port ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([3ef9bd5](https://github.com/MaxPayne89/klass-hero/commit/3ef9bd5b22b1a99e2e36a4e6dd812930c92434fd))
* remove stacking context trapping flash messages under navbar ([b4d843c](https://github.com/MaxPayne89/klass-hero/commit/b4d843c2892d9ee0461e78ea970f6db813504138)), closes [#232](https://github.com/MaxPayne89/klass-hero/issues/232)
* replace hero-blue-500 with hero-blue-600 for WCAG AA contrast ([f49e734](https://github.com/MaxPayne89/klass-hero/commit/f49e734526f65fad2c5c3cde99f34e8e78c7d8b4)), closes [#227](https://github.com/MaxPayne89/klass-hero/issues/227)
* replace stale prime-cyan/magenta/yellow classes with brand colors ([a0f81b7](https://github.com/MaxPayne89/klass-hero/commit/a0f81b7a661f2f513418d2ff3f8ff5e0c860826b)), closes [#227](https://github.com/MaxPayne89/klass-hero/issues/227)
* replace String.to_existing_atom with safe tier cast ([b7e00e5](https://github.com/MaxPayne89/klass-hero/commit/b7e00e58207b66d915436d93f4d12f8bbae4b21f))
* require status change in transition_changeset/2 ([297ee1c](https://github.com/MaxPayne89/klass-hero/commit/297ee1c1536ccc63478b54034d2bfecad9da412c))
* resolve architecture review issues for enrollment capacity ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([8e0b04d](https://github.com/MaxPayne89/klass-hero/commit/8e0b04d88c1092843de8d4c1428dfc1ba91a398c))
* resolve architecture review suggestions [#12](https://github.com/MaxPayne89/klass-hero/issues/12)-14 ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([7455943](https://github.com/MaxPayne89/klass-hero/commit/7455943b403773458b8080a355855547dbb50623))
* resolve CI failure and warnings in invite claim and test mocks ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([20a3067](https://github.com/MaxPayne89/klass-hero/commit/20a306784784878caa11bb9b23052c77cfe7da94))
* resolve credo --strict warnings for logger metadata and list assertion ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([987b0aa](https://github.com/MaxPayne89/klass-hero/commit/987b0aa74d77aad85a003e0eb08090f0dece8d64))
* resolve critical runtime bugs in Family Programs section ([#154](https://github.com/MaxPayne89/klass-hero/issues/154)) ([8b289a7](https://github.com/MaxPayne89/klass-hero/commit/8b289a72cb4e3e03860d879cad2b2fd43757f849))
* resolve important architecture review issues [#4](https://github.com/MaxPayne89/klass-hero/issues/4)-8 ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([a2fd39b](https://github.com/MaxPayne89/klass-hero/commit/a2fd39b2d9376c9c4b306ca066c52dc8c7b64cca))
* resolve parent profile for enrollment queries and add integration tests ([#154](https://github.com/MaxPayne89/klass-hero/issues/154)) ([7dddab8](https://github.com/MaxPayne89/klass-hero/commit/7dddab8b15e70d60f2d86ad2309b2d56793a1be9))
* resolve saga test race condition and add missing subscription tests ([a2de0de](https://github.com/MaxPayne89/klass-hero/commit/a2de0deff4c5cd7b9f8db9c9ffeff018a32ac86a))
* resolve scheduling architecture issues ([#146](https://github.com/MaxPayne89/klass-hero/issues/146)) ([171a1a1](https://github.com/MaxPayne89/klass-hero/commit/171a1a1d516c4497a4f95f296b53f7d2b7bfdaf8))
* resolve TODO comments and update dependencies ([be60e88](https://github.com/MaxPayne89/klass-hero/commit/be60e88caf9651ad9d3de22eda3075d8f959272a))
* show warning flash on cover upload failure instead of blocking save ([0a8e856](https://github.com/MaxPayne89/klass-hero/commit/0a8e856fc0048d83cd30363fb6e0b81db004c3d7))
* staff member headshot not updating on edit ([dd12a19](https://github.com/MaxPayne89/klass-hero/commit/dd12a19f61a46ce5de6ad324311cafb48ead4ae3))
* suppress sobelow Traversal.FileModule false positives ([7aac9a6](https://github.com/MaxPayne89/klass-hero/commit/7aac9a698516fbab44320d235f4256fdff7ee2e6))
* **test:** disable VerifiedProviders projection in test env ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([2e11355](https://github.com/MaxPayne89/klass-hero/commit/2e11355646560a802f9505a5959d9d9206eeb47c))
* **test:** isolate child, provider, and verification document tests from pre-existing data ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([23b88e6](https://github.com/MaxPayne89/klass-hero/commit/23b88e6210b1301ec90d364e02d18a13c2b0e368))
* **test:** isolate paginated program tests from pre-existing data ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([a614076](https://github.com/MaxPayne89/klass-hero/commit/a614076c8863770156523a04c9d180e7f98865f5))
* unread message count badge not visible ([9d092c6](https://github.com/MaxPayne89/klass-hero/commit/9d092c635f796d5d19aa68db84dad19a95999224))
* unwrap consume_uploaded_entries results and add crash protection ([454ef7f](https://github.com/MaxPayne89/klass-hero/commit/454ef7f9f5c6587425aca1197ba61ea9e89da75f))
* unwrap upload results and add crash protection ([c76f891](https://github.com/MaxPayne89/klass-hero/commit/c76f891e2b57459b57e846dab96f0aafe2d6096b))
* use current_scope.user.id for check-in/out FK integrity ([2f0a540](https://github.com/MaxPayne89/klass-hero/commit/2f0a5403f885d3d4e21e13ddda411a911fe847b8))
* use DaisyUI theme colors for unread message count badges ([3d858c3](https://github.com/MaxPayne89/klass-hero/commit/3d858c3df592b43973fbf82a06dcd98d1ca703cc)), closes [#229](https://github.com/MaxPayne89/klass-hero/issues/229)
* use program price directly as enrollment total ([c6986b2](https://github.com/MaxPayne89/klass-hero/commit/c6986b2d49f05e0b79b574ec6f458e53428fb806))
* use push_event to clear textarea after message send ([a5cb636](https://github.com/MaxPayne89/klass-hero/commit/a5cb636e60a890e58d9ab8d60509a23bef93fe65)), closes [#228](https://github.com/MaxPayne89/klass-hero/issues/228)
* use realistic UUIDs in MessagingLiveHelper tests ([1358886](https://github.com/MaxPayne89/klass-hero/commit/1358886344cef499b61449d755da628f534a9b22))
* use registration_period struct for edit form population ([#145](https://github.com/MaxPayne89/klass-hero/issues/145)) ([1b2f45e](https://github.com/MaxPayne89/klass-hero/commit/1b2f45e8bec27ab0700382768f9edca874aabedf))
* use tagged error tuples in cast_provider_tier and remove tier_label catch-all ([415c675](https://github.com/MaxPayne89/klass-hero/commit/415c675cbc1cd8c6523295bcf8b4d76ce5d9c520))
* use text-error-content instead of text-white on unread badges ([27a39f7](https://github.com/MaxPayne89/klass-hero/commit/27a39f742683b0d2048c43d2102b84927a228871))
* white-on-white text in message bubbles ([2bcc023](https://github.com/MaxPayne89/klass-hero/commit/2bcc023c44c46eadaa8fa6f91610e1cbd9b658d4))
* wire up Add Child button and View All link on parent dashboard ([197d3d7](https://github.com/MaxPayne89/klass-hero/commit/197d3d761f234bb4ab8bf87615de22b402ecce50)), closes [#225](https://github.com/MaxPayne89/klass-hero/issues/225)
* wire up Add Child button on parent dashboard ([fe17b36](https://github.com/MaxPayne89/klass-hero/commit/fe17b3668077bd9e8abf74aa03a8ddddbe1ced6d))


### Code Refactoring

* convert family programs to LiveView stream ([#154](https://github.com/MaxPayne89/klass-hero/issues/154)) ([9efe84c](https://github.com/MaxPayne89/klass-hero/commit/9efe84ce99ed0abff2ce5e285c668c42bba288f3))
* deduplicate messaging LiveView callbacks ([1f29df6](https://github.com/MaxPayne89/klass-hero/commit/1f29df6fb5f59880aa46be328f545ee0a54f930c))
* deduplicate messaging LiveView callbacks via __using__ macro ([61af8b2](https://github.com/MaxPayne89/klass-hero/commit/61af8b2b4dbbff27807d4320ca3c4cc291cac02a)), closes [#266](https://github.com/MaxPayne89/klass-hero/issues/266)
* **enrollment,family:** extract user accounts port and centralize dispatch error handling ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([dda818f](https://github.com/MaxPayne89/klass-hero/commit/dda818f359598ec07e0d88cb3354120178a6cf67))
* **enrollment:** extract helpers to fix Credo nesting-depth violations ([263675d](https://github.com/MaxPayne89/klass-hero/commit/263675d58b382ffa42e6872f311e720b59ba9193))
* **enrollment:** remove dead fee calculation code ([#195](https://github.com/MaxPayne89/klass-hero/issues/195)) ([4d94097](https://github.com/MaxPayne89/klass-hero/commit/4d940970eea4af11753cfa757cf959edebb29090))
* extract check_title_collisions/1 to flatten nesting in build_context/1 ([9fb84d3](https://github.com/MaxPayne89/klass-hero/commit/9fb84d3ca573dec8bd0394a0c13914a239315519))
* extract duplicated to_domain_list into MapperHelpers ([2727a48](https://github.com/MaxPayne89/klass-hero/commit/2727a487560af247f69a8dc7150626771128ea6b))
* extract duplicated to_domain_list/1 into MapperHelpers ([c02c66c](https://github.com/MaxPayne89/klass-hero/commit/c02c66cc9d9cf3cde858dfedc265885046a4c112)), closes [#239](https://github.com/MaxPayne89/klass-hero/issues/239)
* extract EnqueueInviteEmails use case from event handler ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([6b9e769](https://github.com/MaxPayne89/klass-hero/commit/6b9e769b04e89d326e1362a509388e43d9436929))
* extract EnrollmentClassifier domain service ([#154](https://github.com/MaxPayne89/klass-hero/issues/154)) ([5de95bf](https://github.com/MaxPayne89/klass-hero/commit/5de95bf9c91cc0e0a0b293f5fcb44944b3558375))
* extract save_staff branches to reduce complexity and nesting ([d209571](https://github.com/MaxPayne89/klass-hero/commit/d2095719a1b73de8cc2bd0c41e4005cf283e1908))
* extract shared badge and hero overlay components ([2703f07](https://github.com/MaxPayne89/klass-hero/commit/2703f070209f23e295318adf5222ecee847e7725))
* extract shared MapperHelpers ([37d4690](https://github.com/MaxPayne89/klass-hero/commit/37d469026ad8b235058ba90009dad5ed62f409a1))
* extract shared MapperHelpers from Family/Provider/Enrollment ([a78af2e](https://github.com/MaxPayne89/klass-hero/commit/a78af2ec39b50563b0bbdc9927cbaf5faba6b115)), closes [#214](https://github.com/MaxPayne89/klass-hero/issues/214)
* extract shared normalize_subscription_tier from repositories ([91eeb67](https://github.com/MaxPayne89/klass-hero/commit/91eeb670899b0d99339c4a00ee69756e1a351dc4))
* extract shared normalize_subscription_tier from repositories ([337942c](https://github.com/MaxPayne89/klass-hero/commit/337942c1b2688ceba101841d744c7a3dafe117dc)), closes [#220](https://github.com/MaxPayne89/klass-hero/issues/220)
* extract shared NotifyLiveViews handler to eliminate duplication ([f3b7e25](https://github.com/MaxPayne89/klass-hero/commit/f3b7e2561ed7baf8e576597ff6bee7db1d992e63))
* extract shared NotifyLiveViews handler to eliminate duplication ([8fdd19d](https://github.com/MaxPayne89/klass-hero/commit/8fdd19d8bcf28f8a1827a6455a43b391cebb4cf1)), closes [#253](https://github.com/MaxPayne89/klass-hero/issues/253)
* extract shared TierPresenter for tier display data ([2613ea9](https://github.com/MaxPayne89/klass-hero/commit/2613ea953b0d36cbb8a1f857555866e1211779a0)), closes [#270](https://github.com/MaxPayne89/klass-hero/issues/270)
* extract shared TierPresenter to eliminate duplicated tier display data ([419666d](https://github.com/MaxPayne89/klass-hero/commit/419666d63c315c97bc76caf4351b45a28e112b81))
* **family:** route guardian operations through port ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([e7e5eec](https://github.com/MaxPayne89/klass-hero/commit/e7e5eec6d0e3218baf4c6a0d2f1c14d5cea0168d))
* fix architecture review findings for registration period ([#147](https://github.com/MaxPayne89/klass-hero/issues/147)) ([eb15af3](https://github.com/MaxPayne89/klass-hero/commit/eb15af30e716a69384f93b9f8de3ce14712809c1))
* fix architecture review issues for participant restrictions ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([8d10dad](https://github.com/MaxPayne89/klass-hero/commit/8d10dada872a0a8abd09c45cf80b83b59e177a15))
* fix credo --strict issues ([d008038](https://github.com/MaxPayne89/klass-hero/commit/d0080384749ab9b798dca3934ab0a331cebc133d))
* fix credo --strict issues in enrollment and dashboard ([#151](https://github.com/MaxPayne89/klass-hero/issues/151)) ([23bc3f4](https://github.com/MaxPayne89/klass-hero/commit/23bc3f40a4df9660f9e3a93aee32db1a06f4d061))
* fix credo complexity issues in roster and edit handlers ([#145](https://github.com/MaxPayne89/klass-hero/issues/145)) ([483f921](https://github.com/MaxPayne89/klass-hero/commit/483f92128a9cea6e516aca78c5093ae23a77c73b))
* hide pricing section on homepage ([#178](https://github.com/MaxPayne89/klass-hero/issues/178)) ([61e5a65](https://github.com/MaxPayne89/klass-hero/commit/61e5a658032a2dcfc562e529d737a1925bd53f58))
* improve readability of compile_env! calls in ListProgramEnrollments ([#145](https://github.com/MaxPayne89/klass-hero/issues/145)) ([e38c52e](https://github.com/MaxPayne89/klass-hero/commit/e38c52e1257c12d01748f6c4fd658552420e7084))
* loosen typespec on MapperHelpers.to_domain_list/2 ([fc2c7f5](https://github.com/MaxPayne89/klass-hero/commit/fc2c7f58c23b1fc47e653b017f6edb01696cdf10))
* make port contracts type-safe and extend ProgramMapper.to_schema/1 with provider_id ([90cb430](https://github.com/MaxPayne89/klass-hero/commit/90cb430295a932c508c881ea89da125759b9a88f))
* move icon_name/1 from Shared.Categories to ProgramPresenter ([688a708](https://github.com/MaxPayne89/klass-hero/commit/688a708f53c4dde35b3631ad2671c2aaa3dcbd8d))
* remove hardcoded data and wire to config/domain ([65099ad](https://github.com/MaxPayne89/klass-hero/commit/65099ad6a2b6bcde51a2163f1e5e35d00b075491))
* remove icon_path from Program domain model ([d1cb115](https://github.com/MaxPayne89/klass-hero/commit/d1cb1150666272cdc8836b99451c68ac750e8971))
* remove icon_path from read model, schemas, projections, and repository ([412c650](https://github.com/MaxPayne89/klass-hero/commit/412c650197e21c0915e5208a1a2adf681e3aa46d))
* remove icon_path, derive program icons from category ([1dc1999](https://github.com/MaxPayne89/klass-hero/commit/1dc19992fe369ef0489873f1c53e54221dbc89d8))
* remove spots_available from Program, migrate to enrollment policies ([#149](https://github.com/MaxPayne89/klass-hero/issues/149)) ([55940cd](https://github.com/MaxPayne89/klass-hero/commit/55940cdf85f485c816b8fc11ae17534c6d2d4de3))
* replace child parent_id with children_guardians join table ([c4387fe](https://github.com/MaxPayne89/klass-hero/commit/c4387fe261210b870014954d7cd0e26fe168ff13))
* replace icon_path SVG rendering with heroicon components ([e88ec0d](https://github.com/MaxPayne89/klass-hero/commit/e88ec0d2225f15c97d528ddc0061ba8244418384))
* return domain models from invite repository ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([1754a97](https://github.com/MaxPayne89/klass-hero/commit/1754a97141b122fd73a4ae3469c3af42988e7883))
* route CreateProgram use case through Program aggregate, update repository and integration tests ([9270f7f](https://github.com/MaxPayne89/klass-hero/commit/9270f7f25ed3143f9a61b95939d01f907ddae130))
* use compile_env! for DI in ListProgramEnrollments ([#145](https://github.com/MaxPayne89/klass-hero/issues/145)) ([b55e214](https://github.com/MaxPayne89/klass-hero/commit/b55e214eeaaaa2af8fe7afe45052dff21e334f90))
* use compile_env! module attributes in enrollment use cases ([e3a7f05](https://github.com/MaxPayne89/klass-hero/commit/e3a7f05f19c50dbb54f589a59c9c1e362e25b650))
* use compile_env! module attributes in enrollment use cases ([39a3422](https://github.com/MaxPayne89/klass-hero/commit/39a342213e6e9939a4cccba7166d5909ca39805f))
* use domain model in SendInviteEmailWorker ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([03c251e](https://github.com/MaxPayne89/klass-hero/commit/03c251e7bad70cb2e7df946dd228e49f013082f7))
* use shared mailer_defaults config in UserNotifier ([#176](https://github.com/MaxPayne89/klass-hero/issues/176)) ([9d093c0](https://github.com/MaxPayne89/klass-hero/commit/9d093c0a58408247f3a2f1dc19123194a17e4054))


### Dependencies

* update credo, ecto_sql, error_tracker, phoenix_live_view ([051889b](https://github.com/MaxPayne89/klass-hero/commit/051889b2a9494df2fac82fa3fdd473827ba43b38))

## [Unreleased]

## [0.2.0] - 2024-09-11

### Fixed
- **Mobile Mockups**: Resolved header icon visibility in iPhone 14 mockup frame
  - Removed problematic margin-right causing bell and gear icons to overflow
  - Added responsive sizing with clamp() for dynamic icon scaling (36-44px)
  - Implemented flex-shrink: 0 to prevent icon compression
  - Updated header padding system for consistent mobile spacing
  - Icons now remain fully visible across all phone frame sizes (300-375px)

### Added
- **Documentation**: Comprehensive non-developer friendly mockup viewing guide
- **Documentation**: Quick start instructions for accessing app mockups
- **README**: Step-by-step mockup navigation guide for stakeholders

### Enhanced
- **Mobile Mockups**: Improved responsive design system for better cross-device compatibility
- **User Experience**: Better touch targets and mobile-first responsive design

## [0.1.0] - 2024-09-10

### Added
- **Mobile Mockups**: Complete responsive phone mockup system with sleek scaling
- **Design System**: Comprehensive UI system with interactive tooling
- **UI Components**: Advanced interactions and dark mode support
- **Navigation**: Improved spacing and visual hierarchy with vibrant borders
- **Mockup System**: Interactive phone frame with multiple screen demonstrations
- **Theme System**: Dark/light mode toggle with persistent storage
- **Responsive Design**: Mobile-first approach with clamp() sizing functions
- **Animation System**: Smooth transitions and micro-interactions

### Infrastructure
- **Project Setup**: Initial monorepo structure with backend and mobile directories
- **Build System**: Basic development environment with CSS/JS organization
- **Documentation**: Foundational README and project structure documentation
