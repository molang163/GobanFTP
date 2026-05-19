# GobanFTP

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

これは日本語の入口です。リリース上の正式な主張とプロトコル境界は、英語版
`README.md` を基準にします。

GobanFTP は、囲碁の一局を「信頼できない listing（名前一覧）」から復元する
`GOFTP/1` の検証用の仕組みです。普通の対局アプリでも、ゲームサーバでも
ありません。着手はファイル名です。replay はファイル本文ではなく名前を読みます。
盤面と SGF は replay から再生成される projection（再生成表示）や witness
（検証用の証跡）です。Web と Terminal は、それらを表示するための面です。

![Perl 5.34+](https://img.shields.io/badge/Perl-5.34%2B-39457E)
![Version 1.000](https://img.shields.io/badge/version-1.000-333333)
![License perl_5](https://img.shields.io/badge/license-perl__5-blue)
![Showcase check](https://img.shields.io/badge/showcase-prove--lr%20t%2Fshowcase--demo.t-success)

ファイルの中身を変えても、mtime を変えても、listing order を変えても、
補足情報である sidecar や projection を足しても、replay は変わりません。
変わるのは basename、つまりディレクトリやファイルの最後の名前の部分です。

Current line: `v1.0/package 1.000` release source.

[3分で確認する](#three-minute-proof) · [端末で打つ](#terminal-play) ·
[静的標本ページ](#static-witness-specimen) · [契約](#the-contract)

はじめに、この README で使う言葉を置きます。

- `basename`: path の最後の名前です。GobanFTP では game descriptor directory
  basename と event basename が protocol packet になります。
- `listing`: サーバや保存先から見える名前一覧です。GobanFTP はこの一覧を読みます。
- `replay`: 名前から状態を再生し、検証する処理です。
- `surface`: 表示や入力の面です。見せることはできますが、replay の入力にはなりません。
- `fixture`: テストや説明のために固定された標本データです。live service の
  実行結果ではありません。
- `witness`: replay から得た検証用の証跡です。root、hash、status、diagnostic
  などを外から読める形にします。
- `projection`: replay から再生成できる表示物です。盤面、SGF、oracle transcript
  などです。表示はできますが、決定はしません。
- `sidecar`: 補足情報を置く場所です。説明はできますが、replay の判断には
  入りません。
- `event_set_root`: accepted event basenames の集合を比較するための root です。

以降の例は、この読み方を前提にしています。

```text
Names are packets.
The listing is the read.
The board is projection.
SGF is witness.
FTP is the altar, not the authority.
```

source-art、terminal play、static witness HTML、fixture の証跡は補助的な表示です。
replay の決定には使いません。

ローカルで入口を確認するなら、まずこれです。

```sh
perl Makefile.PL
make test
prove -lr t/showcase-demo.t
```

## まず見るもの

四つの画像は同じ境界を別の角度から見せています。どれもアプリケーション状態ではなく、
event basenames から復元された状態の見え方です。

### 1. アプリ状態ではなく、プロトコルオブジェクト

![GobanFTP のプロトコルオブジェクト。game descriptor directory、event basenames、sidecar、projections、tmp residue が見える。](docs/assets/readme-01-protocol-object.png)

一局はディレクトリ名と `events/` 直下の名前で表されます。`sidecar/` は補足、
`projections/` は表示、`tmp/` は公開途中の residue です。replay が読むのは
game descriptor directory basename と direct `events/` basenames だけです。

### 2. race は fork として見える

![GobanFTP race shrine の replay 出力。visible fork diagnostic が表示されている。](docs/assets/readme-04-race-fork.png)

二つの着手が同じ親から同時に出たとき、listing order に勝者を選ばせません。
GobanFTP は race を fork として見せます。既定では保守的に replay し、明示的な
ack-assisted recovery がない限り fork で止まります。

### 3. terminal play は公開前に lock する

![GobanFTP の terminal play。keyboard と optional SGR mouse による二段確認がある。](docs/assets/readme-02-tui.png)

`play --tui` はローカル端末の input/display layer です。keyboard と、対応端末での
optional SGR mouse は、まず candidate を選びます。二度目の Enter/click で
publish を確認します。publishing 中は input を lock します。

### 4. 静的標本であって hosted UI ではない

![GobanFTP の static witness specimen。9x9 board と検証パネルが表示されている。](docs/assets/readme-03-witness-specimen.png)

`examples/static/witness-specimen.html` は直接開く static specimen です。script も
server も network fetch もありません。static HTML は hosted Web UI では
ありません。supplied witness fields と projection text を見せるだけで、protocol
上の事実は event basenames に残ります。

<a id="the-contract"></a>

## 契約

`GOFTP/1` が入力として採用するものは二つだけです。

```text
game descriptor directory basename
direct child basenames under events/
```

中核の replay は次を無視します。

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

`RETR`、`SIZE`、`MDTM`、HTTP resource bodies、cache validators、server metadata
は replay の一部ではありません。すべての projection を消しても、一局は残ります。

event id は file contents からではなく、canonical filename context から作られます。
hash input は game descriptor basename と、末尾の `.h-<event_id>` を除いた event
basename を bind します。見えている event id は lowercase base32hex SHA-256 の
先頭 16 characters です。

一つの進行は hash chain です。既知の play 全体は DAG です。network race は FTP
ordering に隠れず、visible fork になります。保守的な replay は、明示的な
ack-assisted path がない限り fork で止まります。

protocol names は退屈でよいものです。

```text
[a-z0-9._-]
```

secret を filename に置いてはいけません。filenames は public です。

<a id="three-minute-proof"></a>

## 3分で確認する

showcase の確認を実行します。

```sh
prove -lr t/showcase-demo.t
```

これは clean shrine、race shrine、source-art oracle smoke、unsigned
`local-goftp1` v1 witness、静的な表示出力を確認します。static HTML は hosted Web UI ではありません。`--surface terminal`
は local `play --tui` input/display layer ではありません。
local terminal play は `gobanftp play --tui` で使えますが、replay と publish
callbacks の上にある input/display layer にとどまります。

clean shrine を開きます。

```text
examples/fixtures/ftp-shrine/
```

実行します。

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp play --once g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

主要な形はこうなります。

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

次に race fixture を開きます。

```text
examples/fixtures/ftp-race-shrine/
```

実行します。

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-race-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

この fixture では exit code `3` が期待値です。fork が見つかったことを表します。

```text
diagnostic ... code=fork parent_id=hihat4p8r6gaeuts
gobanftp.replay=fork
events=4
event_set_count=4
canonical_moves=1
legal_moves=3
canonical_ids=hihat4p8r6gaeuts
```

この fixture では、race が fork として残ります。listing order は勝者を選びません。

<a id="terminal-play"></a>

## 端末で打つ

`gobanftp play --tui` は、同じ replay と publish callbacks の上で動くローカル端末
の input/display layer です。rules、roots、diagnostics、event acceptance を所有しません。

サンプルを一時ディレクトリにコピーして試せます。

```sh
tmp="$(mktemp -d)"
src="$(find examples/fixtures/ftp-shrine -maxdepth 1 -type d -name 'g1.id-ftp-shrine*' | head -n 1)"
cp -R -- "$src" "$tmp/game"
perl -Ilib script/gobanftp play --tui "$tmp/game"
```

状態は明示的に進みます。

```text
select -> confirm -> publishing_locked -> published
```

操作は次の通りです。

```text
arrow keys / hjkl  cursor move
Enter              select; same point again confirms publish
mouse click        SGR mouse capable terminals only; same point again confirms
P                  pass
R                  resign
r                  refresh
q                  quit
```

keyboard が fallback path です。SGR mouse は terminal が対応する場合だけ使います。
一度 publish に成功すると session は終了します。

<a id="static-witness-specimen"></a>

## 静的標本ページ

直接開けます。

```text
examples/static/witness-specimen.html
```

これは hosted UI ではありません。direct-open の specimen です。script、network
fetch、server process、hosted Web UI behavior はありません。

ページが見せるのは、supplied witness fields、visual board skin、raw projection
text、SGF excerpt です。visual board は projection skin です。検証の根拠にはならず、
表示だけを行います。

## Shrine Fixture（標本）

`ftp-shrine` は、repository 内でそのまま読める fixture です。live server ではなく、
説明とテストのための標本です。

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

読み方はこの通りです。

```text
g1.../         names the game
events/       names the moves and acknowledgements
sidecar/      説明はできるが、決定はしない
projections/  表示はできるが、証明はしない
tmp/          publish 中に残るもの
```

最初に見る file と directory です。

```text
examples/fixtures/ftp-shrine/README.md
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/events/
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/oracle/listing.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/board/current.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/sgf/main.sgf
oracle/goban.pl
```

`projections/oracle/listing.txt` は reader-facing transcript です。`NLST events/`
が event basenames を露出し、`RETR`、`SIZE`、`MDTM` は `GOFTP/1` replay の外に
残ることを見せます。

SGF は witness です。正本ではありません。

## いま動く範囲

v1.0/package 1.000 で実装済みの範囲です。

- 中核: filename grammar、event ids、`event_set_root`、DAG replay、
  `chinese-area-v1` rules、SGF、ack-assisted fork recovery。
- 保存先: local、FTP、WebDAV、read-only Git tree、read-only DNS record-file
  admission。
- 表示と入力: `play --tui`、witness text/html/terminal、projections、direct-open
  static specimen、executable source-art oracle smoke。
- profiles: unsigned `GOFTP/1`、declared substrate profiles、explicit
  signed-HMAC witness/preflight checks。
- 検証材料: showcase check、attack fixtures、cross-substrate golden vectors、
  profile publish fixtures。

v1.0/package 1.000 の範囲は次の通りです。

- `git-tree-goftp1` は runtime で read-only です。publish commands は storage
  boundary で失敗します。
- `dns-record-goftp1` はローカル、または明示的に指定された record file input の
  read-only normalization です。live DNS を問い合わせず、AXFR を実行せず、
  DNSSEC を信頼根拠として扱わず、provider APIs を呼ばず、records を publish しません。
- TTL、answer order、cache age、DNSSEC status、authoritative server identity、
  provider metadata は consensus の外です。
- static HTML の witness 出力は hosted Web UI ではありません。`--surface terminal`
  は local `play --tui` input/display layer ではありません。
- verifier-local HMAC key files、explicit verifier-supplied lifecycle status、
  fixture publish-token/preflight semantics は production key lifecycle、
  production auth、real writer authorization ではありません。
- final scoring/result events は `GOFTP/1` の外です。

FTP listing-shadow public poison-vector coverage は fixture/listing 上の検証材料だけです。
`RETR`、`SIZE`、`MDTM`、live FTP auth、live FTP integrity、production FTP deployment
safety は扱いません。`ftp-goftp1` tmp+rename publish path は別に declared
され、mock FTP tests と optional disposable live smoke coverage で扱われます。

この release の signed-HMAC material は verifier-local fixture/preflight の検証材料
です。production writer authorization でも production key lifecycle でもありません。
`signed-hmac-goftp1` は明示的に選んだ profile の検査であり、unsigned `GOFTP/1`
replay を置き換えるものではありません。

Unsigned `GOFTP/1` は有効なままです。signed/auth profile は、その explicit profile
が選ばれた場合だけ events を reject できます。sidecar signatures は unsigned replay
を変えません。

## Source Art の境界

`oracle/goban.pl` は囲碁盤のように見えます。それでも実行できる Perl であり、
テスト対象 module を呼び出す wrapper です。

```sh
perl -c oracle/goban.pl
perl oracle/goban.pl --smoke
```

期待される出力には次が含まれます。

```text
oracle/goban.pl syntax OK
gobanftp.oracle=ok
rules.move=ok
```

source art は表示用の wrapper です。filename grammar、event id、DAG replay、
rule legality、storage behavior、SGF、diagnostics は通常の module 側にあります。

```text
source art / C / asm / Web UI / TUI -> cannot change truth
```

## 動かす

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

通常の確認:

```sh
perl Makefile.PL
make
make test
```

ローカルで全体を確認:

```sh
prove -lr t
```

一時的な game を作ります。

```sh
tmp="$(mktemp -d)"
export GOBANFTP_ROOT="$tmp"

perl -Ilib script/gobanftp create-game --id demo --size 9 --black alice --white bob
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob aa
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob play-bb
perl -Ilib script/gobanftp play --once g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
```

採用される packet を見ます。

```sh
find "$GOBANFTP_ROOT" -path '*/events/*' -exec basename {} \; | sort
```

この名前群が一局です。file contents ではありません。

## 保存先

既定の保存先は local filesystem です。FTP、read-only Git tree、read-only DNS
record-file admission、WebDAV は、event file contents、blob bytes、resource bodies、
DNS transport metadata を読まずに、同じ「名前一覧を先に読む」境界へ正規化されます。

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

Git tree replay は `<treeish>:<game>/events` から direct child names を読みます。
blob bytes、commit metadata、refs、branches、tags、sidecars、projections、tmp
entries は無視します。Git tree mode は read-only であり、publish commands は
storage boundary で失敗します。

DNS record admission は、runtime で `GOBANFTP_DNS_RECORD_FILE` として与えられた
ローカル、または明示的に指定された record-file presentation だけを読みます。これは
live DNS resolver、AXFR client、DNSSEC validator、provider API client、dynamic
update client、publishing backend ではありません。TTLs、record order、answer
order、cache age、DNSSEC status、authoritative server identity、provider metadata
は `event_set_root` の前に無視されます。

WebDAV replay は `PROPFIND Depth: 1` で `events/` を読み、direct href basenames
だけを使います。publishing は `tmp/` に zero-byte temporary resource を書き、
`events/<event-name>` へ move し、fresh `PROPFIND` で visibility を確認します。

`ftp-goftp1` の default publishing は、`tmp/` の下に zero-byte temporary entry を
upload し、`RNTO` で `events/<event-name>` へ rename し、listing で visibility を
確認します。`GOBANFTP_FTP_PUBLISH_MODE=mkdir` は directory-shaped alternative として
残ります。

Projection writes は local-only です。nonlocal `project` と `sgf --write` は拒否
されます。plain `sgf`、`verify`、`replay`、`play`、`watch` は nonlocal listings
を読めます。

## Release Checks

主な確認コマンド:

```sh
prove -lr t/showcase-demo.t
prove -lr t
```

現在の P14 release 記録は `docs/P14_RELEASE_GATE.md` にあります。final release-source
の確認内容を記録し、external artifact/tag record plan を指します。final tarball
hash は source tree の外に置かれます。

final artifact identity、version decision、tag preconditions は
`docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md` で追跡されます。

optional disposable live FTP smoke:

```sh
script/live-ftp-smoke
```

## v1.0/P14 の形

GobanFTP v1.0 は game server ではありません。複数の「名前を列挙できる保存先」から、
同じ event basenames を使って一局を replay する Perl 実装です。

release source の確認では、profile、adapter、attack fixture、witness 出力、
signed-HMAC profile、表示出力を次の項目で比較します。

```text
same event basenames
same event_set_root
same DAG
same canonical prefix
same board projection
same SGF
same diagnostic class for the same logical failure where observable
```

必要な不変条件:

```text
modify mtime       -> unchanged
modify file bytes  -> unchanged
modify LIST order  -> unchanged
add sidecar        -> unchanged
change basename    -> changed
bad signed profile -> rejected by that signed profile
source art / C / asm / Web UI / TUI -> cannot change truth
```

`v0.1` は `GOFTP/1` consensus boundary を固定しました。`v1.0/P14` はその境界を
package 1.000 で、複数の substrate にまたがる検証の出発点にします。

## 資料

よく使う入口です。

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

repository map:

```text
.
|-- README.md              English README
|-- README.zh-CN.md        Simplified Chinese README
|-- README.ja.md           this text
|-- docs/                  protocol, roadmap, decisions, release records
|-- oracle/goban.pl        executable source-art smoke wrapper
|-- lib/GobanFTP/          Perl implementation modules
|-- script/gobanftp        CLI entry point
|-- examples/fixtures/     browsable mirrored games
`-- t/                     tests and attack galleries
```

プロトコル挙動を変える前に読むもの:

1. `docs/PROTOCOL.md`
2. `docs/ARCHITECTURE.md`
3. `docs/ALGORITHMS.md`
4. `docs/RULES.md`
5. `docs/ROADMAP.md`
6. `docs/DECISIONS.md`

新しい profile や rule を追加する前に、既存の protocol 文書を確認してください。
