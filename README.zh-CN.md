# GobanFTP

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

GobanFTP 把一盘围棋存在目录列表里。文件名就是事件。

![Perl 5.34+](https://img.shields.io/badge/Perl-5.34%2B-39457E)
![Version 1.100_001](https://img.shields.io/badge/version-1.100_001-333333)
![License Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)
![Showcase check](https://img.shields.io/badge/showcase-prove--lr%20t%2Fshowcase--demo.t-success)

当前 beta 版本：`v1.1.0-beta.1/package 1.100_001`。

[文件名就是事件](#the-shape) · [分叉长什么样](#the-fork) ·
[为什么做这个](#why-this-exists) · [先看一眼](#see-it-first) · [适合用来做什么](#what-this-is-for) ·
[不适合用来做什么](#not-for) · [三分钟跑起来](#three-minute-proof) ·
[终端下棋](#terminal-play) · [静态标本页](#static-witness-specimen) ·
[协议契约](#the-contract)

> 名字为真，棋盘为相，SGF 为经，FTP 为仪式。
> 仪式可以展示，不能裁决。

<a id="the-shape"></a>

## 文件名就是事件

一个很小的棋局可以只是一组名字：

```text
g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob/
  events/
    m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m
    m1.p000002.w.play-bb.pa-khjclcui7pejbv3m.by-bob.n-chain2.h-bihb3re4k9hlucat
    m1.p000003.b.pass.pa-bihb3re4k9hlucat.by-alice.n-chain3.h-kcvtlonfje163p9q
```

没有“棋步内容”需要读取。文件名就是事件。

游戏目录的 basename 负责命名棋盘大小、规则、贴目和玩家。`events/` 下面的直接子 basename
负责命名已经被协议接受的事件。Replay 根据这些名字里的 parent id 串起棋局，不根据文件内容、
mtime 或目录返回顺序。其他文件可以存在，但只有被接受的 event basename 会参与 replay。

<a id="the-fork"></a>

## 分叉长什么样

如果两次发布尝试同时写出了同一个父节点下面的不同合法子节点，目录列表不能替协议选赢家：

```text
g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob/
  events/
    m1.p000001.b.play-aa.pa-genesis.by-alice.n-forkleft.h-q65v2mhef9t3em7l
    m1.p000001.b.play-bb.pa-genesis.by-alice.n-forkright.h-o5g8u5cu913nedng
```

这两个事件都声明了 `pa-genesis`。默认 replay 会报告一个可见 fork，而不是让 FTP、
WebDAV、Git、DNS、文件系统 listing 顺序、mtime、文件内容或 sidecar metadata 偷偷决定棋局。

<a id="why-this-exists"></a>

## 为什么做这个

GobanFTP 是一个 `GOFTP/1` 协议实验，也是一个可以跑的证明样本。它要检查的主张很窄：
如果两个系统能看到同一个游戏目录 basename 和同一组已接受的 event basename，就应该能回放出同一盘棋。

它最初的动机更像一次带玩心的协议滥用：让 FTP 这类可列目录的存储表面做一点本职之外的事。
重点不是做一个普通围棋服务器，而是把不可信但可枚举存储上的 replay 边界变得可见。

文件内容、大小、mtime、listing order、sidecar、projection、SGF、HTML、终端输出和代码画可以帮助人检查棋局，
但不能裁决棋局。

它不是在线围棋服务器，也不是托管 Web UI，也不是生产安全系统。

<a id="see-it-first"></a>

## 先看一眼

![GobanFTP 静态 witness 标本页，显示 9x9 棋盘和证明面板。](docs/assets/readme-03-witness-specimen.png)

Replay 之后，同一组已接受的名字可以被投影成棋盘和 witness 页面。

直接用浏览器打开：

```text
examples/static/witness-specimen.html
```

它没有脚本、服务端或网络请求。static HTML 不是 hosted Web UI；它只展示
replay 后生成的 witness 字段和棋盘投影。这个页面不是棋局来源；replay 仍然来自游戏目录名和 event 文件名。

<a id="what-this-is-for"></a>

## 适合用来做什么

如果你想看这些东西，GobanFTP 是一个合适的标本：

- 只从公开游戏目录名和 event 文件名做确定性回放
- 把目录列表当成 event log（事件日志）
- 两个写入者竞争时留下可见 fork
- 不可信但可枚举存储上的协议边界
- 能运行的协议艺术（protocol art）

<a id="not-for"></a>

## 不适合用来做什么

GobanFTP 不是：

- 普通在线围棋服务器
- 托管 Web UI
- 生产级认证系统
- 生产级 FTP 安全证明
- DNS resolver 或 provider 集成
- 完整的数目 / 胜负结算系统

<a id="three-minute-proof"></a>

## 三分钟跑起来

要求：Perl 5.34+ 和 `make`。这一步不需要 FTP 服务器；它使用仓库里的本地 fixture。

```sh
perl Makefile.PL
make
make test
prove -lr t/showcase-demo.t t/showcase-v1_1.t
perl -Ilib script/gobanftp showcase --out showcase-v1.1
```

这条检查会验证几件事：正常棋局能回放；并发冲突会显示成 fork；展示层、文件内容和元数据不会偷偷改变棋局。

`gobanftp showcase --out showcase-v1.1` 会从仓库里的 fixture 生成一个本地可直接打开的静态目录。
它只是本地检查用的展示输出，不是托管 Web UI，也不是 replay 输入。

直接跑示例棋局：

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp play --once g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

你会看到一张从文件名回放出来的棋盘：

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

再跑 race 样本：

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-race-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

这个命令会以 `3` 退出。这里不是崩溃，而是说明并发冲突被保留下来了：

```text
diagnostic ... code=fork parent_id=hihat4p8r6gaeuts
gobanftp.replay=fork
events=4
event_set_count=4
canonical_moves=1
legal_moves=3
canonical_ids=hihat4p8r6gaeuts
```

## 先懂五个词

- event 文件名：`events/` 下面代表一步棋或确认的一段文件名。
- 回放（replay）：从这些文件名重新验证并算出棋盘。
- fork：两个合法分支抢同一个父节点时留下的可见分叉。
- projection：从 replay 结果生成的展示，比如棋盘文本、SGF、HTML。
- witness：给人或测试看的证明材料，不是棋局真相本身。

## 再看三个视角

上面的静态标本页已经展示了棋盘和 witness 面板。下面三个视角看的是同一个对象：一盘棋由 game directory 的名字和 `events/` 下面的直接文件名决定。

### 1. 棋局长在目录里

![GobanFTP 协议对象：game descriptor 目录、event basenames、sidecar、projections 和 tmp 残留。](docs/assets/readme-01-protocol-object.png)

最外层目录名描述这盘棋。`events/` 里的文件名描述每一步。`sidecar/` 可以放解释材料，`projections/` 可以放棋盘和 SGF，`tmp/` 可以留下发布残渣。它们可以帮助人看懂，但不能决定棋局。

### 2. 并发会变成 fork

![GobanFTP race shrine 的 replay 输出，显示一个可见的 fork diagnostic。](docs/assets/readme-04-race-fork.png)

如果两个客户端同时从同一个父节点下棋，目录返回顺序不能替协议决定哪一步赢。GobanFTP 会显示 fork，并在默认回放下停住。

### 3. 终端里可以下棋

![GobanFTP 终端下棋界面，支持键盘和可选 SGR mouse 二段确认。](docs/assets/readme-02-tui.png)

`play --tui` 是本地终端界面。它支持键盘，也支持部分终端里的 SGR mouse。第一次选择，第二次确认；开始发布后输入会被锁住。

<a id="terminal-play"></a>

## 终端下棋

本地终端对局：

```sh
tmp="$(mktemp -d)"
src="$(find examples/fixtures/ftp-shrine -maxdepth 1 -type d -name 'g1.id-ftp-shrine*' | head -n 1)"
cp -R -- "$src" "$tmp/"
game="$tmp/$(basename "$src")"
perl -Ilib script/gobanftp play --tui "$game"
```

控制方式：方向键或 `hjkl`（Vim 风格）移动光标；`Enter` 选择，已选中同一点时确认发布；支持 SGR mouse 时，鼠标点击也走同样的两步确认。`P` 选择 `pass`，`R` 选择 `resign`，`r` 刷新，`q` 退出。

```text
select -> confirm -> publishing_locked -> published
```

`play --tui` 不拥有规则、root、diagnostics 或 event acceptance。它只是同一套 replay 和 publish callbacks 之上的本地输入/显示层。

只读 live-over-listing 观察可以用有界的 `watch --live` 或 `play --live`：

```sh
perl -Ilib script/gobanftp watch --live --max-polls 3 --interval 1 "$game"
perl -Ilib script/gobanftp watch --live --compact --max-polls 3 --interval 1 "$game"
```

live 模式遇到可见 fork 或 validation diagnostics 后会继续轮询。它不会选择胜者，也不会发布落子；它只会反复列出 `events/`，从文件名 replay，并展示当前 witness surface。`--compact` 会保留 event-set 和 worldline 字段，但省略棋盘绘制。

<a id="static-witness-specimen"></a>

## 静态标本页

直接打开：

```text
examples/static/witness-specimen.html
```

这个页面适合用来解释项目，因为它把棋盘投影、event/root 证明面板和原始投影文本摆在一起。

它只是展示层。棋盘皮肤不参与验证；验证材料来自 event 文件名 replay 后得到的 witness。

<a id="the-contract"></a>

## 协议契约

`GOFTP/1` 只承认两个输入：

| 真相 | 含义 |
| --- | --- |
| game descriptor directory basename | 最外层棋局目录名，描述棋局、规则和玩家 |
| `events/` 下面的直接文件名 | 描述落子和确认 |

下面这些东西不会决定 replay：

| 影子 | 例子 |
| --- | --- |
| 文件数据 | entry type、文件内容、文件大小 |
| 服务器元数据 | mtime、listing 顺序、server order |
| FTP 元数据 | `RETR`、`SIZE`、`MDTM` |
| WebDAV 元数据 | ETag、Last-Modified、locks、resource body |
| 辅助目录 | `sidecar/**`、`projections/**`、`tmp/**` |
| 展示结果 | SGF、static HTML、终端输出、代码画 |

删除 `projections/` 里的显示文件后，棋局仍然可以回放。改文件内容、mtime 或 listing 顺序，棋局不变。改 event 文件名，棋局必须改变，或者这个 event 必须被拒绝。

event id 来自规范化后的文件名上下文，不来自文件内容。所有已知落子组成 DAG。如果出现 race，就形成可见 fork，而不是被 FTP 或 WebDAV 的返回顺序偷偷解决。

协议名字只允许：

```text
[a-z0-9._-]
```

不要把秘密放进文件名。文件名是公开协议包。

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
可以解释，但不能决定；`projections/` 可以显示，但不能裁决；`tmp/` 是发布残留。

建议先看：

```text
examples/fixtures/ftp-shrine/README.md
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/events/
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/oracle/listing.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/board/current.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/sgf/main.sgf
oracle/goban.pl
```

SGF 是见证输出，不是棋局正本。

`projections/oracle/listing.txt` 是给读者看的 transcript。它展示
`NLST events/` 如何暴露 event basenames，也明确 `RETR`、`SIZE`、`MDTM`
留在 `GOFTP/1` replay 之外。

## 现在实现了什么

v1.1.0-beta.1/package 1.100_001 已实现：

- 共识核心：filename grammar、event ids、`event_set_root`、DAG replay、
  `chinese-area-v1` rules、SGF witness，以及 ack-assisted fork recovery。
- 存储后端：local、FTP、WebDAV、read-only Git tree profile，以及 read-only
  DNS record-file profile。
- 展示层：`play --tui`、只读 `watch --live` / `play --live` 观察、text /
  html / terminal witness surfaces、static witness specimen，以及 source-art
  oracle smoke。
- 检查材料：signed-HMAC fixture/preflight checks、attack fixtures，以及
  cross-substrate golden vectors。

v1.1.0-beta.1/package 1.100_001 明确不声称：hosted Web UI、final scoring/result events、live DNS / AXFR /
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

代码画 / C / asm / Web UI / TUI -> 不能改变协议真相

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
这些后端的共同点是：replay 只读取可枚举的名字，不读取文件内容或远端元数据。
本地参数如果是路径，只使用最后一段作为 game descriptor basename；这个 basename 必须是合法的 GOFTP game descriptor。

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

带认证的 WebDAV URL 必须使用 `https://`；Basic 和 Bearer 凭据会在 `http://` 上被拒绝。不带认证的 `http://` 保留给 mock/本地明文 fixture 使用，不是生产传输安全模式。

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

当前 beta source gate 在 `docs/V1_1_RELEASE_GATE.md`。它记录
`v1.1.0-beta.1/package 1.100_001` 的 fixture-local 检查，并明确省略
tag、push、upload、deploy 和 distribution 命令。

公开 beta release notes 在 `docs/V1_1_RELEASE_NOTES.md`。历史
`v1.0/P14` release 记录仍保留在 `docs/P14_RELEASE_GATE.md` 和
`docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md`；它们不是当前 beta 的
release/tag identity。

对 P1 fixture-local review scope 而言，live provider smoke、distribution
packaging、tag、upload 和 deploy 都在 P1 外；它们需要后续单独的 maintainer-run gate。

## License

除非另有说明，本仓库中的代码、协议文档、示例、fixtures、test vectors、
projections 和静态标本页都按 Apache License, Version 2.0 授权。

Copyright 2026 GobanFTP contributors.

这项许可只覆盖仓库内容。它不授权你访问、测试或发布到第三方 FTP、WebDAV、
DNS、Git 或其他系统，也不是生产安全认证。

## 发布不变量 / Release Invariants

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
代码画 / C / asm / Web UI / TUI -> 不能改变协议真相
```

`v0.1` 冻结 `GOFTP/1` consensus boundary。最初的 `v1.0/P14` package 1.000
release source 把这条边界应用到 local、FTP、WebDAV、read-only Git tree 和
read-only DNS record-file。当前 beta 发布线是 `v1.1.0-beta.1/package 1.100_001`。

## 文档

常用入口：

```text
Showcase:     docs/SHOWCASE.md
Protocol:     docs/PROTOCOL.md
Profiles:     docs/PROFILES.md
Grammar:      docs/GRAMMAR.md
Attacks:      docs/ATTACKS.md
v1.1 gate:    docs/V1_1_RELEASE_GATE.md
v1.1 notes:   docs/V1_1_RELEASE_NOTES.md
v1.0 DoD:     docs/V1_DOD.md
v1.0 history: docs/P14_RELEASE_GATE.md
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
