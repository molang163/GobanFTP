# GobanFTP

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

本訳は `README.md` に従う。release claim は英語 README を正とする。

敵対的なディレクトリ listing から復元される囲碁の対局。

![Perl 5.34+](https://img.shields.io/badge/Perl-5.34%2B-39457E)
![Version 1.000](https://img.shields.io/badge/version-1.000-333333)
![License perl_5](https://img.shields.io/badge/license-perl__5-blue)
![Showcase gate](https://img.shields.io/badge/showcase-prove--lr%20t%2Fshowcase--demo.t-success)

着手はファイル名である。Replay はファイル内容を読まない。

basename を変えれば対局は変わる。bytes、mtime、順序、sidecar、projection
を変えても、対局は変わらない。

Current line: `v1.0/package 1.000` release source.

[三分間の証明](#three-minute-proof) · [Terminal play](#terminal-play) ·
[Static specimen](#static-witness-specimen) · [The contract](#the-contract)

`v1.0/P14` が固定する規則は一つだけである。同じ accepted event names は、
同じ replay を生む。source-art、terminal play、static witness HTML、
fixture evidence はすべて surface であり、truth を追加しない。

```text
Names are packets.
The listing is the read.
The board is projection.
SGF is witness.
FTP is the altar, not the authority.
```

奇妙な表面は意図されたものだ。Replay contract は交渉しない。

ローカルの proof を実行する:

```sh
perl Makefile.PL
make test
prove -lr t/showcase-demo.t
```

## First Look

これらは同じ境界を見せる表示である。Replay を決めるのは event basenames
だけである。

### Protocol Object, Not App State

![GobanFTP protocol object: game descriptor directory, event basenames, sidecar, projections, and tmp residue.](docs/assets/readme-01-protocol-object.png)

game descriptor basename と direct `events/` basenames が packets である。
`sidecar/`、`projections/`、`tmp/` は replay を決められない。

### Race Becomes Fork

![GobanFTP race shrine replay output showing a visible fork diagnostic.](docs/assets/readme-04-race-fork.png)

listing order は勝者を選ばない。Default conservative replay は fork で止まる。
回復するには explicit ack-assisted recovery が必要である。

### Terminal Play Locks Before Publish

![GobanFTP terminal play surface with keyboard and optional SGR mouse two-step confirmation.](docs/assets/readme-02-tui.png)

`play --tui` は replay と publish callbacks の上にある local input/display
layer である。Keyboard と、利用可能な場合の SGR mouse は、まず candidate
を選択する。二度目の Enter/click が publish を確認し、publishing 中は input
が lock される。

### Static Specimen, Not Hosted UI

![GobanFTP static witness specimen showing a visual 9x9 board and proof panel.](docs/assets/readme-03-witness-specimen.png)

static witness specimen は直接開くファイルである。script なし、server なし、
hosted Web UI なし。supplied witness fields と projection text を表示するだけで、
protocol truth は event basenames に残る。

<a id="the-contract"></a>

## The Contract

`GOFTP/1` の authoritative inputs は二つだけである。

```text
game descriptor directory basename
direct child basenames under events/
```

Core replay が無視するもの:

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

`RETR`、`SIZE`、`MDTM`、HTTP resource bodies、cache validators、server
metadata は replay の一部ではない。すべての projection が削除されても対局は
生き残る。

event id は file contents ではなく、canonical filename context から導かれる。
hash input は game descriptor basename と、末尾の `.h-<event_id>` を除いた
event basename を bind する。visible event id は lowercase base32hex SHA-256
の先頭 16 characters である。

一つの進行は hash chain である。既知の play は DAG である。Network race は
FTP ordering に隠されず、visible fork になる。Conservative replay は、
explicit ack-assisted path が要求されない限り fork で止まる。

Protocol names は退屈でよい。

```text
[a-z0-9._-]
```

secret を filename に入れてはならない。Filenames は public である。

<a id="three-minute-proof"></a>

## 三分間の証明

local showcase gate を実行する:

```sh
prove -lr t/showcase-demo.t
```

これは clean shrine、race shrine、source-art oracle smoke、unsigned
`local-goftp1` v1 witness、static inspection surfaces を検査する。これらの
surfaces は read-only inspection output である。static HTML は hosted Web UI
ではなく、`--surface terminal` は local `play --tui` input surface ではない。
Local terminal play は `gobanftp play --tui` で利用できるが、replay と publish
callbacks の上の input/display layer にとどまる。Keyboard と SGR mouse input
はまず candidate を選び、二度目の Enter/click で publish を確認し、publishing
開始後は input を lock する。

shrine を開く:

```text
examples/fixtures/ftp-shrine/
```

そして実行する:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-shrine \
perl -Ilib script/gobanftp play --once g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

Expected clean shape, selected lines:

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

race fixture を開く:

```text
examples/fixtures/ftp-race-shrine/
```

実行する:

```sh
GOBANFTP_ROOT=examples/fixtures/ftp-race-shrine \
perl -Ilib script/gobanftp replay g1.id-ftp-race-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim
```

process は `3` で終了する。Expected race shape, selected lines:

```text
diagnostic ... code=fork parent_id=hihat4p8r6gaeuts
gobanftp.replay=fork
events=4
event_set_count=4
canonical_moves=1
legal_moves=3
canonical_ids=hihat4p8r6gaeuts
```

これが要点である。race は visible のまま残る。listing order に勝者を選ばせない。

<a id="terminal-play"></a>

## Terminal Play

`gobanftp play --tui` は、同じ replay と publish callbacks の上で動く local
play である。rules、roots、diagnostics、event acceptance を所有しない。

```text
select -> confirm -> publishing_locked -> published
```

Keyboard が fallback path である。SGR mouse は terminal が対応する場合に使う。
成功した publish は session を終了する。

<a id="static-witness-specimen"></a>

## Static Witness Specimen

`examples/static/witness-specimen.html` は direct-open specimen である。script、
network fetch、server process、hosted UI behavior はない。

visual board は raw projection text の横に置かれた projection skin である。
testify はできない。display だけができる。

## The Shrine

browsable specimen は screenshot ではない。Protocol object である。

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

tree はこう読む:

```text
g1.../         names the game
events/       names the moves and acknowledgements
sidecar/      may explain, but cannot decide
projections/  may display, but cannot testify
tmp/          is publishing residue
```

最初に読むとよい files:

```text
examples/fixtures/ftp-shrine/README.md
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/events/
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/oracle/listing.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/board/current.txt
examples/fixtures/ftp-shrine/g1.id-ftp-shrine.s9.r-chinese-area-v1.k7500.pb-daemon.pw-pilgrim/projections/sgf/main.sgf
oracle/goban.pl
```

`projections/oracle/listing.txt` は reader-facing transcript である。
`NLST events/` が event basenames を見せる一方で、`RETR`、`SIZE`、`MDTM`
は GOFTP/1 replay の外に残ることを示す。

SGF は witness であり、source of truth ではない。

## What Runs Now

v1.0/package 1.000 で実装済み:

- Consensus core: filename grammar、event ids、`event_set_root`、DAG replay、
  `chinese-area-v1` rules、SGF、ack-assisted fork recovery。
- Stores: local、FTP、WebDAV、read-only Git tree、read-only DNS record-file
  admission。
- Surfaces: `play --tui`、witness text/html/terminal、projections、direct-open
  static specimen、executable source-art oracle smoke。
- Profiles: unsigned `GOFTP/1`、declared substrate profiles、explicit
  signed-HMAC witness/preflight gates。
- Evidence: showcase gate、attack fixtures、cross-substrate golden vectors、
  profile publish fixtures。

v1.0/package 1.000 の boundary lines:

- `git-tree-goftp1` は runtime で read-only である。publish commands は
  storage boundary で失敗する。
- `dns-record-goftp1` は local または otherwise declared record file inputs
  の read-only normalization である。DNS admission は live DNS を query
  せず、AXFR を実行せず、DNSSEC を trust せず、provider APIs を呼ばず、
  records を publish しない。
- TTL、answer order、cache age、DNSSEC status、authoritative server identity、
  provider metadata は consensus の外に残る。
- Static HTML witness output は hosted Web UI ではなく、`--surface terminal`
  は local `play --tui` input surface ではない。
- Verifier-local HMAC key files、explicit verifier-supplied lifecycle status、
  fixture publish-token/preflight semantics は production key lifecycle、
  production auth、real writer authorization ではない。
- Final scoring/result events は `GOFTP/1` の外に残る。

FTP listing-shadow public poison-vector coverage は fixture/listing evidence
だけである。`RETR`、`SIZE`、`MDTM`、live FTP auth、live FTP integrity、
production FTP deployment safety を claim しない。`ftp-goftp1` tmp+rename
publish path は別に declared され、mock FTP tests と optional disposable
live smoke coverage で扱われる。

この release の signed/auth material は verifier-local fixture/preflight
evidence である。production writer authorization でも production key
lifecycle でもない。

Unsigned `GOFTP/1` は有効なまま変わらない。signed/auth profile は、その
explicit profile が選ばれた場合にだけ events を reject できる。sidecar
signatures は unsigned replay を変えない。

## Source Art Boundary

`oracle/goban.pl` は Go board のように見えてよい。それでも実行できなければならない。

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

source art は tested modules に dispatch してよい。ただし protocol truth を
所有してはならない。filenames、event ids、DAG replay、rule legality、storage
behavior、SGF、diagnostics は drawing の外に残る。Whitespace、comments、POD、
C hooks、asm-like surface は ritual surface であり、consensus input ではない。

## Run It

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

disposable game を作る:

```sh
tmp="$(mktemp -d)"
export GOBANFTP_ROOT="$tmp"

perl -Ilib script/gobanftp create-game --id demo --size 9 --black alice --white bob
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob aa
perl -Ilib script/gobanftp publish-move g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob play-bb
perl -Ilib script/gobanftp play --once g1.id-demo.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob
```

authoritative packets を inspect する:

```sh
find "$GOBANFTP_ROOT" -path '*/events/*' -exec basename {} \; | sort
```

その names が game である。file contents ではない。

## Stores

Local が default store である。FTP、read-only Git tree、read-only DNS
record-file admission、WebDAV は、event file contents、blob bytes、resource
bodies、DNS transport metadata を読まずに同じ listing-first boundary で動く。

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

Git tree replay は `<treeish>:<game>/events` から direct child names を読む。
blob bytes、commit metadata、refs、branches、tags、sidecars、projections、
tmp entries は無視する。Git tree mode は今のところ read-only であり、publish
commands は storage boundary で失敗する。

DNS record admission は、runtime で `GOBANFTP_DNS_RECORD_FILE` として与えられた
local または otherwise declared record-file presentation だけを読む。これは
live DNS resolver、AXFR client、DNSSEC validator、provider API client、
dynamic update client、publishing backend ではない。TTLs、record order、
answer order、cache age、DNSSEC status、authoritative server identity、
provider metadata は `event_set_root` の前に無視される。

WebDAV replay は `PROPFIND Depth: 1` で `events/` を読み、direct href basenames
だけを使う。Publishing は `tmp/` に zero-byte temporary resource を書き、
`events/<event-name>` へ move し、fresh `PROPFIND` で visibility を確認する。

`ftp-goftp1` では、default publishing は `tmp/` の下に zero-byte temporary
entry を upload し、`RNTO` で `events/<event-name>` へ rename し、listing で
visibility を確認する。`GOBANFTP_FTP_PUBLISH_MODE=mkdir` は directory-shaped
alternative として残る。

Projection writes は今のところ local-only である。Nonlocal `project` と
`sgf --write` は reject される。plain `sgf`、`verify`、`replay`、`play`、
`watch` は nonlocal listings を読める。

## Proof Gates

Main gates:

```sh
prove -lr t/showcase-demo.t
prove -lr t
```

current P14 release-gate evidence は `docs/P14_RELEASE_GATE.md` に記録されている。
これは final release-source evidence を記録し、external artifact/tag record plan
を指す。final tarball hash は source tree の外に属する。

final artifact identity、version decision、tag preconditions は
`docs/P14_RELEASE_MANIFEST_AND_TAG_PLAN.md` で追跡される。

Optional disposable live FTP smoke:

```sh
script/live-ftp-smoke
```

## v1.0/P14 Shape

GobanFTP v1.0 は game server ではない。untrusted enumerable substrates から
囲碁の対局を立ち上げる protocol-abuse proof machine である。

release proof は profile、adapter、attack、witness、auth、display gates の
一致を要求する。

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

`v0.1` は GOFTP/1 consensus boundary を固定した。`v1.0/P14` はその境界を
package 1.000 の cross-substrate proof source にする。

## Documentation

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
|-- README.zh-CN.md        Simplified Chinese README
|-- README.ja.md           this text
|-- docs/                  protocol, roadmap, decisions, gates
|-- oracle/goban.pl        executable source-art smoke wrapper
|-- lib/GobanFTP/          Perl implementation modules
|-- script/gobanftp        CLI entry point
|-- examples/fixtures/     browsable mirrored games
`-- t/                     tests and attack galleries
```

protocol behavior を変える前に読むこと:

1. `docs/PROTOCOL.md`
2. `docs/ARCHITECTURE.md`
3. `docs/ALGORITHMS.md`
4. `docs/RULES.md`
5. `docs/ROADMAP.md`
6. `docs/DECISIONS.md`

別の protocol を発明する前に、既存の protocol を締める。
