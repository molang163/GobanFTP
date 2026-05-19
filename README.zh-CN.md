# GobanFTP

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

这是一份面向中文读者的入口页。协议名、命令、路径和环境变量按仓库原样保留；发布声明和协议边界以英文 `README.md` 为准。

GobanFTP 是一个把围棋落子编码进目录列表的 `GOFTP/1` 实验。它不把棋局交给数据库，也不把棋局藏进文件内容。

一盘棋由一组公开、可列举的名字复原。对 FTP 来说，这组名字就是目录列表里的文件名。

![Perl 5.34+](https://img.shields.io/badge/Perl-5.34%2B-39457E)
![Version 1.000](https://img.shields.io/badge/version-1.000-333333)
![License Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)
![Showcase check](https://img.shields.io/badge/showcase-prove--lr%20t%2Fshowcase--demo.t-success)

Current line: `v1.0/package 1.000` release source.

[三分钟证明](#three-minute-proof) · [终端下棋](#terminal-play) ·
[静态标本页](#static-witness-specimen) · [协议契约](#the-contract)

可以先按下面这几句理解：

> 落子是文件名。目录列表就是读取。棋盘只是投影。SGF 是见证输出。
> 对象为真，棋盘为相，SGF 为经，FTP 为仪式！
> FTP 是仪式，不是真相本身。

它故意长得不像普通围棋程序。这里没有隐藏的游戏状态；只要读取到同一组 event 文件名，就应该得到同一盘棋。

这些名字可以来自本地目录、FTP、Git tree、DNS record-file 或 WebDAV。substrate 可以变，replay 边界不变。

README 里会反复出现几个词：

- basename：路径最后一段名字，不含父目录。`events/foo` 的 basename 是 `foo`。
- fixture：仓库里固化的可复现样本，用来证明协议边界没有漂移。
- witness：由协议输入生成的见证输出；它可以证明一次读取看到什么，但不是新的输入。
- projection：从 replay 重建出来的显示层，例如棋盘文本、SGF、网页棋盘。
- sidecar：附属说明材料。它可以解释，不能决定。
- replay：从这些名字重新验证并推出棋局状态。
- DAG：由所有已知落子组成的有向无环图；race 会在这里变成 fork。
- event_set_root：同一组已接受 event basenames 的摘要根，用来比较不同系统看到的是否是同一盘棋。

## 先看什么

先看四张图。它们都是同一条边界的不同视图：只有 `events/` 下面的 direct child basenames 决定棋局。

### 1. 协议对象，不是应用状态

![GobanFTP 协议对象：game descriptor 目录、event basenames、sidecar、projections 和 tmp 残留。](docs/assets/readme-01-protocol-object.png)

最外层目录名描述这盘棋。`events/` 里的 basename 描述每一步。`sidecar/` 可以放解释材料，`projections/` 可以放棋盘和 SGF，`tmp/` 可以留下发布残渣。

replay 只使用这两类名字：

```text
game descriptor directory basename
direct child basenames under events/
```

### 2. 并发不会被顺序掩盖

![GobanFTP race shrine 的 replay 输出，显示一个可见的 fork diagnostic。](docs/assets/readme-04-race-fork.png)

如果两个客户端同时从同一个父节点下棋，FTP 的 listing order 不能决定哪一步成立。GobanFTP 会把这种情况显示成 fork，并在 conservative replay 下停住。

在这里，不可信目录列表只负责暴露名字，不负责裁决分支。

### 3. 终端里可以下棋

![GobanFTP 终端下棋界面，支持键盘和可选 SGR mouse 二段确认。](docs/assets/readme-02-tui.png)

`play --tui` 是本地终端界面。它可以用键盘，也可以在支持 SGR mouse 的终端里用鼠标。

它不是点一下就直接发布：

```text
select -> confirm -> publishing_locked -> published
```

第一次选择，第二次确认。开始发布后输入会被锁住，一次成功发布后会话结束。

### 4. 静态标本页，不是网站后台

![GobanFTP 静态 witness 标本页，显示 9x9 棋盘和证明面板。](docs/assets/readme-03-witness-specimen.png)

`examples/static/witness-specimen.html` 是一个可以直接打开的静态标本页。它没有脚本，没有服务端，也没有网络请求。

static HTML 不是 hosted Web UI。它只是把 witness fields 和棋盘 projection 展示出来。真相仍然在 event basenames 里。

<a id="the-contract"></a>

## 协议契约

`GOFTP/1` 只承认两个输入：

```text
game descriptor directory basename
direct child basenames under events/
```

一盘棋由这些公开 basename 决定。

下面这些东西不会决定 replay：

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

文件内容不是棋局。mtime 不是棋局。服务器返回顺序不是棋局。sidecar 和 projection 也不是棋局。

改文件内容，棋局不变。改 mtime，棋局不变。打乱 listing 顺序，棋局不变。改 event basename，棋局必须改变，或者被稳定拒绝。

event id 来自文件名上下文，不来自文件内容。它绑定 game descriptor basename，
以及去掉末尾 `.h-<event_id>` 后的 event basename。

可见 event id 是 lowercase base32hex SHA-256 的前 16 个字符。

一条棋路是一条 hash chain。所有已知落子组成 DAG。如果出现 race，就形成可见 fork，而不是被 FTP 顺序偷偷解决。

协议名字只允许：

```text
[a-z0-9._-]
```

不要把秘密放进文件名。文件名是公开协议包。

<a id="three-minute-proof"></a>

## 三分钟证明

先跑这条本地检查：

```sh
prove -lr t/showcase-demo.t
```

它会检查：干净棋局、race/fork 样本、source-art oracle 的 smoke 检查、
unsigned `local-goftp1` witness，以及静态检查输出。

打开示例棋局：

```text
examples/fixtures/ftp-shrine/
```

运行：

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp play --once g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

你应该看到类似这样的棋盘：

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

再打开 race fixture：

```text
examples/fixtures/ftp-race-shrine/
```

运行：

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-race-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

这个命令会以 `3` 退出，并显示 fork：

```text
diagnostic ... code=fork parent_id=hihat4p8r6gaeuts
gobanftp.replay=fork
events=4
event_set_count=4
canonical_moves=1
legal_moves=3
canonical_ids=hihat4p8r6gaeuts
```

这里的退出码不是普通崩溃；它表示 race 被保留下来，没有被 listing order 悄悄改写。

<a id="terminal-play"></a>

## 终端下棋

本地终端对局：

```sh
tmp="$(mktemp -d)"
src="$(find examples/fixtures/ftp-shrine -maxdepth 1 -type d -name 'g1.id-ftp-shrine*' | head -n 1)"
cp -R -- "$src" "$tmp/"
GOBANFTP_ROOT="$tmp" perl -Ilib script/gobanftp play --tui "$(basename "$src")"
```

控制方式：方向键或 `hjkl` 移动光标；`Enter` 选择，已选中同一点时确认发布；
支持 SGR mouse 时，鼠标点击也走同样的两步确认。`P` 选择 `pass`，`R` 选择
`resign`，`r` 刷新，`q` 退出。

`play --tui` 不拥有规则、root、diagnostics 或 event acceptance。它只是同一套 replay 和 publish callbacks 之上的本地输入/显示层。

<a id="static-witness-specimen"></a>

## 静态标本页

直接打开：

```text
examples/static/witness-specimen.html
```

这个页面适合用来解释项目，因为它把棋盘 projection、event/root 证明面板和原始
projection 文本摆在一起。

它只是展示层。棋盘皮肤不参与验证；验证材料来自 event basenames replay 后得到的 witness。

## 目录标本

示例棋局长这样：

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

读法很直接：`g1.../` 命名这盘棋；`events/` 命名落子和确认；`sidecar/`
可以解释，但不能决定；`projections/` 可以显示，但不能作证；`tmp/` 是发布残留。

建议先看：

```text
examples/fixtures/ftp-shrine/README.md
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/events/
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/oracle/listing.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/board/current.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/sgf/main.sgf
oracle/goban.pl
```

SGF 是 witness，不是 source of truth。

`projections/oracle/listing.txt` 是给读者看的 transcript。它展示
`NLST events/` 如何暴露 event basenames，也明确 `RETR`、`SIZE`、`MDTM`
留在 `GOFTP/1` replay 之外。

## 现在实现了什么

v1.0/package 1.000 已实现：

- 共识核心：filename grammar、event ids、`event_set_root`、DAG replay、
  `chinese-area-v1` rules、SGF witness，以及 ack-assisted fork recovery。
- 存储后端：local、FTP、WebDAV、read-only Git tree profile，以及 read-only
  DNS record-file profile。
- 展示层：`play --tui`、text / html / terminal witness surfaces、
  static witness specimen，以及 source-art oracle smoke。
- 检查材料：signed-HMAC fixture/preflight checks、attack fixtures，以及
  cross-substrate golden vectors。

v1.0 明确不声称：hosted Web UI、final scoring/result events、live DNS / AXFR /
DNSSEC trust / provider API、Git publish or fetch integration、生产级认证
（production auth）、生产级密钥生命周期（production key lifecycle）、真实写入授权
（real writer authorization），或 live FTP auth/integrity/deployment safety。

`git-tree-goftp1` 和 `dns-record-goftp1` 目前是只读 profile。DNS record-file 是本地或显式声明的记录文件，不是 live DNS。

本 release 里的 signed-HMAC material 是 verifier-local fixture/preflight evidence。
它不是生产级认证（production auth）、生产级写入授权（production writer
authorization）或生产级密钥生命周期（production key lifecycle）。

Unsigned `GOFTP/1` 仍然有效且不变。signed/auth profile 只有在显式选择时才会拒绝 events；sidecar signatures 不会改变 unsigned replay。

## 代码画 / Source Art

`oracle/goban.pl` 是可以执行的代码画。它可以看起来像棋盘和祭坛，但它不能拥有协议真相。

```sh
perl -c oracle/goban.pl
perl oracle/goban.pl --smoke
```

期望看到：

```text
oracle/goban.pl syntax OK
gobanftp.oracle=ok
rules.move=ok
```

source art / C / asm / Web UI / TUI -> cannot change truth

空白、注释、POD、C hook、asm-like surface、网页和终端界面都不能改变 event id、DAG replay、规则合法性、SGF 或 diagnostics。

## 安装和测试

运行需要：

```text
Perl 5.34+
Digest::SHA
HTTP::Tiny
MIME::Base64
Net::FTP
```

构建和测试需要：

```text
make
```

可选：

```text
Inline
Inline::C
```

普通测试：

```sh
perl Makefile.PL
make
make test
```

完整本地测试：

```sh
prove -lr t
```

创建一次临时棋局：

```sh
tmp="$(mktemp -d)"
export GOBANFTP_ROOT="$tmp"

perl -Ilib script/gobanftp create-game --id demo --size 9 --black alice --white bob
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob aa
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob play-bb
perl -Ilib script/gobanftp play --once g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
```

查看真正的协议包：

```sh
find "$GOBANFTP_ROOT" -path '*/events/*' -exec basename {} \; | sort
```

这些名字就是棋局。文件内容不是。

## 存储后端 / Stores

默认 store 是本地目录。FTP、WebDAV、read-only Git tree 和 read-only DNS record-file 都被规整到同一条 listing-first 边界。

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

DNS record-file 只读取本地或显式声明的记录文件，由
`GOBANFTP_DNS_RECORD_FILE` 提供。它不是 live DNS：不查询 resolver，不请求
AXFR，不验证 DNSSEC trust，不调用 provider API，也不 publish records。TTL、
record order、answer order、cache age、DNSSEC status、authoritative server
identity 和 provider metadata 都不进入 `event_set_root`。

FTP publish 的默认路径是：在 `tmp/` 下上传 zero-byte temporary entry，用 `RNTO` 重命名到 `events/<event-name>`，再通过 listing 确认可见。它不声明 live FTP auth/integrity 或 production FTP deployment safety。

WebDAV publish 类似：写入 `tmp/`，移动到 `events/<event-name>`，再用新的 `PROPFIND` 确认可见。

Projection writes 目前只支持 local。Nonlocal `project` 和 `sgf --write` 会被拒绝；普通 `sgf`、`verify`、`replay`、`play`、`watch` 可以读取 nonlocal listings。

## 发布检查 / Release Checks

常用检查命令：

```sh
prove -lr t/showcase-demo.t
prove -lr t
```

可选 disposable live FTP smoke：

```sh
script/live-ftp-smoke
```

## License

除非另有说明，本仓库中的代码、协议文档、示例、fixtures、test vectors、
projections 和静态标本页都按 Apache License, Version 2.0 授权。

Copyright 2026 GobanFTP contributors.

这项许可只覆盖仓库内容。它不授权你访问、测试或发布到第三方 FTP、WebDAV、
DNS、Git 或其他系统，也不是生产安全认证。

P14 release 记录在 `docs/P14_RELEASE_GATE.md`。

最终 artifact identity、version decision 和 tag preconditions 记录在 `docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md`。

## v1.0/P14 范围

GobanFTP v1.0 不是围棋服务器。它实现的是一个小型 filename protocol，用来从若干可枚举的存储表面重放同一盘棋。

release 检查会比较 event basenames、`event_set_root`、DAG、canonical prefix、
board projection、SGF，以及同一可观察逻辑故障的 diagnostic class。

这些不变量需要保持：

```text
modify mtime       -> unchanged
modify file bytes  -> unchanged
modify LIST order  -> unchanged
add sidecar        -> unchanged
change basename    -> changed
bad signed profile -> rejected by that signed profile
source art / C / asm / Web UI / TUI -> cannot change truth
```

`v0.1` 冻结 `GOFTP/1` consensus boundary。`v1.0/P14` 在 package 1.000 中把这条边界应用到 local、FTP、WebDAV、read-only Git tree 和 read-only DNS record-file。

## 文档

常用入口：

```text
Showcase:     docs/SHOWCASE.md
Protocol:     docs/PROTOCOL.md
Profiles:     docs/PROFILES.md
Grammar:      docs/GRAMMAR.md
Attacks:      docs/ATTACKS.md
v1.0 DoD:     docs/V1_DOD.md
P14 release:  docs/P14_RELEASE_GATE.md
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

仓库结构：

```text
.
|-- README.md              English README
|-- README.zh-CN.md        this text
|-- README.ja.md           Japanese README
|-- docs/                  protocol, roadmap, decisions, release records
|-- oracle/goban.pl        executable source-art smoke wrapper
|-- lib/GobanFTP/          Perl implementation modules
|-- script/gobanftp        CLI entry point
|-- examples/fixtures/     browsable mirrored games
`-- t/                     tests and attack galleries
```

改协议行为之前，先读：

1. `docs/PROTOCOL.md`
2. `docs/ARCHITECTURE.md`
3. `docs/ALGORITHMS.md`
4. `docs/RULES.md`
5. `docs/ROADMAP.md`
6. `docs/DECISIONS.md`

新增 profile 或规则前，先读现有协议文档。
