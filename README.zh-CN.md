# GobanFTP

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

本译本跟随 `README.md`。release claim 以英文 README 为准。

一盘围棋，从敌意目录列表中复原。

![Perl 5.34+](https://img.shields.io/badge/Perl-5.34%2B-39457E)
![Version 1.000](https://img.shields.io/badge/version-1.000-333333)
![License perl_5](https://img.shields.io/badge/license-perl__5-blue)
![Showcase gate](https://img.shields.io/badge/showcase-prove--lr%20t%2Fshowcase--demo.t-success)

落子是文件名。重放不读文件内容。

改 basename，棋局改变。改 bytes、mtime、顺序、sidecars 或 projections，
棋局不动。

Current line: `v1.0/package 1.000` release source.

[三分钟证明](#three-minute-proof) · [终端对局](#terminal-play) ·
[静态 specimen](#static-witness-specimen) · [契约](#the-contract)

`v1.0/P14` 冻结一条规矩：同一组被接受的 event names 产生同一份
replay。source-art、terminal play、static witness HTML 和 fixture evidence
都是表面。它们不能增加真相。

```text
Names are packets.
The listing is the read.
The board is projection.
SGF is witness.
FTP is the altar, not the authority.
```

怪异的表面是故意的。replay contract 不可谈判。

先运行本地证明：

```sh
perl Makefile.PL
make test
prove -lr t/showcase-demo.t
```

## 第一眼

这些图只是同一条边界的不同视图。只有 event basenames 决定 replay。

### Protocol Object, Not App State

![GobanFTP protocol object: the game descriptor directory, event basenames, sidecar, projections, and tmp residue.](docs/assets/readme-01-protocol-object.png)

game descriptor basename 和直属 `events/` basenames 是 packets。`sidecar/`、
`projections/`、`tmp/` 不能决定 replay。

### Race Becomes Fork

![GobanFTP race shrine replay output showing a visible fork diagnostic.](docs/assets/readme-04-race-fork.png)

listing order 不能替任何一方赢棋。默认 conservative replay 在 fork 处停止；
只有显式请求 ack-assisted recovery 时才会尝试恢复。

### Terminal Play Locks Before Publish

![GobanFTP terminal play surface with keyboard and optional SGR mouse two-step confirmation.](docs/assets/readme-02-tui.png)

`play --tui` 是 replay 和 publish callbacks 之上的本地 input/display layer。
键盘和可用时的 SGR mouse 先选择；第二次 Enter/click 才确认；发布时输入锁定。

### Static Specimen, Not Hosted UI

![GobanFTP static witness specimen showing a visual 9x9 board and proof panel.](docs/assets/readme-03-witness-specimen.png)

static witness specimen 是可直接打开的文件：没有 script，没有 server，没有
hosted Web UI。它显示 supplied witness fields 和 projection text；协议真相仍在
event basenames 里。

<a id="the-contract"></a>

## 契约

`GOFTP/1` 有两个 authoritative inputs：

```text
game descriptor directory basename
direct child basenames under events/
```

Core replay ignores:

```text
entry type
file bytes
file size
listing order
server order
FTP mtime
WebDAV ETag
WebDAV Last-Modified
WebDAV locks
sidecar/**
projections/**
tmp/**
```

`RETR`、`SIZE`、`MDTM`、HTTP resource bodies、cache validators 和 server
metadata 都不是 replay 的一部分。删除所有 projection，棋局仍然存在。

event id 来自 canonical filename context，不来自 file contents。hash input
绑定 game descriptor basename，以及去掉最终 `.h-<event_id>` 字段后的 event
basename。可见 event id 是 lowercase base32hex SHA-256 的前 16 个字符。

一条棋路是一条 hash chain。所有已知落子组成 DAG。网络 race 不会被 FTP
ordering 遮住；它会变成可见 fork。Conservative replay 在 fork 处停止，除非
显式请求 ack-assisted path。

Protocol names 保持无聊：

```text
[a-z0-9._-]
```

秘密不属于 filename。Filenames 是公开的。

<a id="three-minute-proof"></a>

## 三分钟证明

运行本地 showcase gate：

```sh
prove -lr t/showcase-demo.t
```

它检查 clean shrine、race shrine、source-art oracle smoke、unsigned
`local-goftp1` v1 witness，以及 static inspection surfaces。这些 surfaces 是只读
inspection output：static HTML 不是 hosted Web UI，`--surface terminal` 也不是本地
`play --tui` input surface。本地 terminal play 通过 `gobanftp play --tui` 提供；
它仍只是 replay 和 publish callbacks 之上的 input/display layer。键盘和 SGR mouse
输入先选择 candidate，第二次 Enter/click 才发布，发布开始后输入锁定。

打开 shrine：

```text
examples/fixtures/ftp-shrine/
```

然后运行：

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp play --once g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

干净形状，节选：

```text
gobanftp.play=ok
events=7
canonical_moves=6
worldline.status=main
  a b c d e f g h i
9 . . . . . . . . .
8 . . . . . . . . .
7 . . . . . . . . .
6 . . . B . . . . .
5 . . . B . W . . .
4 . . . B W W . . .
3 . . . . . . . . .
2 . . . . . . . . .
1 . . . . . . . . .
```

打开 race fixture：

```text
examples/fixtures/ftp-race-shrine/
```

运行：

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-race-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

进程以 `3` 退出。race 形状，节选：

```text
diagnostic ... code=fork parent_id=hihat4p8r6gaeuts
gobanftp.replay=fork
events=4
event_set_count=4
canonical_moves=1
legal_moves=3
canonical_ids=hihat4p8r6gaeuts
```

这就是重点：race 仍然可见。没有 listing order 可以替它选出赢家。

<a id="terminal-play"></a>

## 终端对局

`gobanftp play --tui` 是同一套 replay 和 publish callbacks 之上的本地对局。
它不拥有 rules、roots、diagnostics 或 event acceptance。

```text
select -> confirm -> publishing_locked -> published
```

键盘是 fallback path。终端支持时使用 SGR mouse。一次成功 publish 会结束会话。

<a id="static-witness-specimen"></a>

## 静态 Witness Specimen

`examples/static/witness-specimen.html` 是 direct-open specimen。它没有 script，
没有 network fetch，没有 server process，也没有 hosted UI behavior。

visual board 是 raw projection text 旁边的一层 projection skin。它不能作证；
它只能显示。

## Shrine

browsable specimen 不是 screenshot。它是 protocol object：

```text
g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/
  events/
    m1.p000001.b.play-dd.pa-genesis.by-daemon.n-altar1.h-0agr68rv1sp5qi21
    ...
  sidecar/
  projections/
    board/current.txt
    oracle/listing.txt
    sgf/main.sgf
  tmp/
```

这样读这棵树：

```text
g1.../         names the game
events/       names the moves and acknowledgements
sidecar/      may explain, but cannot decide
projections/  may display, but cannot testify
tmp/          is publishing residue
```

先看这些文件：

```text
examples/fixtures/ftp-shrine/README.md
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/events/
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/oracle/listing.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/board/current.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/sgf/main.sgf
oracle/goban.pl
```

`projections/oracle/listing.txt` 是给读者看的 transcript。它展示
`NLST events/` 暴露 event basenames，而 `RETR`、`SIZE`、`MDTM` 留在
`GOFTP/1` replay 之外。

SGF 是 witness，不是 source of truth。

## 当前能跑什么

Implemented in v1.0/package 1.000:

- Consensus core: filename grammar、event ids、`event_set_root`、DAG replay、
  `chinese-area-v1` rules、SGF，以及 ack-assisted fork recovery。
- Stores: local、FTP、WebDAV、read-only Git tree，以及 read-only DNS
  record-file admission。
- Surfaces: `play --tui`、witness text/html/terminal、projections、
  direct-open static specimen，以及 executable source-art oracle smoke。
- Profiles: unsigned `GOFTP/1`、declared substrate profiles，以及 explicit
  signed-HMAC witness/preflight gates。
- Evidence: showcase gate、attack fixtures、cross-substrate golden vectors，
  以及 profile publish fixtures。

Boundary lines in v1.0/package 1.000:

- `git-tree-goftp1` 运行时只读；publish commands 在 storage boundary 失败。
- `dns-record-goftp1` 只对本地或另行声明的 record file 做 read-only
  normalization。DNS admission 不查询 live DNS，不运行 AXFR，不信任 DNSSEC，
  不调用 provider APIs，也不 publish records。
- TTL、answer order、cache age、DNSSEC status、authoritative server identity
  和 provider metadata 都留在 consensus 之外。
- Static HTML witness output 不是 hosted Web UI，`--surface terminal` 不是本地
  `play --tui` input surface。
- Verifier-local HMAC key files、显式 verifier-supplied lifecycle status，以及
  fixture publish-token/preflight semantics 不是 production key lifecycle、
  production auth 或 real writer authorization。
- Final scoring/result events 留在 `GOFTP/1` 之外。

FTP listing-shadow public poison-vector coverage 只是 fixture/listing evidence。
它不声明 `RETR`、`SIZE`、`MDTM`、live FTP auth、live FTP integrity 或 production
FTP deployment safety。`ftp-goftp1` tmp+rename publish path 另行声明，并由 mock
FTP tests 和可选 `script/live-ftp-smoke` 覆盖。

本 release 中的 signed/auth material 是 verifier-local fixture/preflight
evidence。它不是 production writer authorization，也不是 production key
lifecycle。

Unsigned `GOFTP/1` 仍然有效且不变。Signed/auth profile 只有在显式选择该 profile
时才能拒绝 events；sidecar signatures 不会改变 unsigned replay。

## Source Art Boundary

`oracle/goban.pl` 可以看起来像一张围棋盘。它仍必须能运行。

```sh
perl -c oracle/goban.pl
perl oracle/goban.pl --smoke
```

Expected output includes:

```text
oracle/goban.pl syntax OK
gobanftp.oracle=ok
rules.move=ok
```

source art 可以调度 tested modules。它不能拥有 protocol truth：filenames、
event ids、DAG replay、rule legality、storage behavior、SGF 和 diagnostics 都留在
drawing 之外。Whitespace、comments、POD、C hooks 和 asm-like surface 是 ritual
surface，永远不是 consensus input。

## 运行

Runtime requirements:

```text
Perl 5.34+
Digest::SHA
HTTP::Tiny
MIME::Base64
Net::FTP
```

Build and test requirements:

```text
make
```

Optional:

```text
Inline
Inline::C
```

Normal gate:

```sh
perl Makefile.PL
make
make test
```

Full local prove run:

```sh
prove -lr t
```

创建一次 disposable game：

```sh
tmp="$(mktemp -d)"
export GOBANFTP_ROOT="$tmp"

perl -Ilib script/gobanftp create-game --id demo --size 9 --black alice --white bob
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob aa
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob play-bb
perl -Ilib script/gobanftp play --once g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
```

检查 authoritative packets：

```sh
find "$GOBANFTP_ROOT" -path '*/events/*' -exec basename {} \; | sort
```

这些 names 就是棋局。file contents 不是。

## Stores

Local 是默认 store。FTP、read-only Git tree、read-only DNS record-file
admission 和 WebDAV 运行同一条 listing-first boundary，不读取 event file
contents、blob bytes、resource bodies 或 DNS transport metadata。

FTP mode:

```text
GOBANFTP_STORE=ftp
GOBANFTP_FTP_HOST
GOBANFTP_FTP_USER
GOBANFTP_FTP_PASSWORD
GOBANFTP_FTP_ROOT
GOBANFTP_FTP_PORT
GOBANFTP_FTP_PASSIVE
GOBANFTP_FTP_TIMEOUT
GOBANFTP_FTP_PUBLISH_MODE
```

WebDAV mode:

```text
GOBANFTP_STORE=webdav
GOBANFTP_WEBDAV_URL
GOBANFTP_WEBDAV_USER
GOBANFTP_WEBDAV_PASSWORD
GOBANFTP_WEBDAV_TOKEN
GOBANFTP_WEBDAV_TIMEOUT
GOBANFTP_WEBDAV_CLASS
GOBANFTP_WEBDAV_PUBLISH_MODE
```

Git tree mode:

```text
GOBANFTP_STORE=git-tree
GOBANFTP_GIT_REPO
GOBANFTP_GIT_TREEISH
GOBANFTP_GIT_BINARY
```

DNS record mode:

```text
GOBANFTP_STORE=dns-record
GOBANFTP_DNS_RECORD_FILE
GOBANFTP_DNS_OWNER_SUFFIX
```

Git tree replay 从 `<treeish>:<game>/events` 读取 direct child names，并忽略
blob bytes、commit metadata、refs、branches、tags、sidecars、projections 和
tmp entries。Git tree mode 目前只读；publish commands 在 storage boundary 失败。

DNS record admission 只读取本地或另行声明的 record-file presentation，用于
`dns-record-goftp1`，运行时由 `GOBANFTP_DNS_RECORD_FILE` 提供。它不是 live DNS
resolver、AXFR client、DNSSEC validator、provider API client、dynamic update
client 或 publishing backend。TTLs、record order、answer order、cache age、
DNSSEC status、authoritative server identity 和 provider metadata 在
`event_set_root` 之前被忽略。

WebDAV replay 用 `PROPFIND Depth: 1` 读取 `events/`，并且只使用 direct href
basenames。Publishing 会在 `tmp/` 下写入 zero-byte temporary resource，把它移动到
`events/<event-name>`，然后用新的 `PROPFIND` 确认可见。

对 `ftp-goftp1`，默认 publishing 会在 `tmp/` 下上传 zero-byte temporary entry，
用 `RNTO` 重命名到 `events/<event-name>`，再通过 listing 确认可见。
`GOBANFTP_FTP_PUBLISH_MODE=mkdir` 仍是 directory-shaped alternative。

Projection writes 目前只支持 local。Nonlocal `project` 和 `sgf --write` 会被拒绝；
普通 `sgf`、`verify`、`replay`、`play`、`watch` 可以读取 nonlocal listings。

## Proof Gates

Main gates:

```sh
prove -lr t/showcase-demo.t
prove -lr t
```

当前 P14 release-gate evidence 记录在 `docs/P14_RELEASE_GATE.md`。它记录最终
release-source evidence，并指向外部 artifact/tag record plan；最终 tarball hash
属于 source tree 之外。

最终 artifact identity、version decision 和 tag preconditions 记录在
`docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md`。

Optional disposable live FTP smoke:

```sh
script/live-ftp-smoke
```

## v1.0/P14 Shape

GobanFTP v1.0 不是 game server。它是 protocol-abuse proof machine，让一盘围棋从
untrusted enumerable substrates 中浮现。

release proof 要求 profile、adapter、attack、witness、auth 和 display gates 一致：

```text
same event basenames
same event_set_root
same DAG
same canonical prefix
same board projection
same SGF
same diagnostic class for the same logical failure where observable
```

Required invariants:

```text
modify mtime       -> unchanged
modify file bytes  -> unchanged
modify LIST order  -> unchanged
add sidecar        -> unchanged
change basename    -> changed
bad signed profile -> rejected by that signed profile
source art / C / asm / Web UI / TUI -> cannot change truth
```

`v0.1` 冻结了 `GOFTP/1` consensus boundary。`v1.0/P14` 把这条边界变成
package 1.000 的 cross-substrate proof source。

## 文档

Fast paths:

```text
Showcase:     docs/SHOWCASE.md
Protocol:     docs/PROTOCOL.md
Profiles:     docs/PROFILES.md
Grammar:      docs/GRAMMAR.md
Attacks:      docs/ATTACKS.md
v1.0 DoD:     docs/V1_DOD.md
P14 gate:     docs/P14_RELEASE_GATE.md
P14 tag plan: docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md
Algorithms:   docs/ALGORITHMS.md
Rules:        docs/RULES.md
Diagnostics:  docs/DIAGNOSTICS.md
Source art:   docs/SOURCE_ART.md
Build:        docs/BUILD.md
CLI:          docs/CLI.md
Roadmap:      docs/ROADMAP.md
Decisions:    docs/DECISIONS.md
```

Repository map:

```text
.
|-- README.md              English README
|-- README.zh-CN.md        this text
|-- README.ja.md           Japanese README
|-- docs/                  protocol, roadmap, decisions, gates
|-- oracle/goban.pl        executable source-art smoke wrapper
|-- lib/GobanFTP/          Perl implementation modules
|-- script/gobanftp        CLI entry point
|-- examples/fixtures/     browsable mirrored games
`-- t/                     tests and attack galleries
```

改变 protocol behavior 前，先读：

1. `docs/PROTOCOL.md`
2. `docs/ARCHITECTURE.md`
3. `docs/ALGORITHMS.md`
4. `docs/RULES.md`
5. `docs/ROADMAP.md`
6. `docs/DECISIONS.md`

先收紧现有 protocol，再发明新的。
