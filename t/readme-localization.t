use v5.34;
use strict;
use warnings;
use utf8;

use FindBin;
use File::Spec;
use Test::More;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $repo_root = File::Spec->rel2abs("$FindBin::Bin/..");

my @readmes = qw(
    README.md
    README.zh-CN.md
    README.ja.md
);

my @language_links = (
    ['English', '[English](README.md)'],
    ['zh-CN',   '[简体中文](README.zh-CN.md)'],
    ['ja',      '[日本語](README.ja.md)'],
);

my %text;
for my $rel (@readmes) {
    my $path = File::Spec->catfile($repo_root, $rel);
    ok -f $path, "$rel exists";
    $text{$rel} = _read_text($path);
    ok length($text{$rel}) > 0, "$rel is readable";

    for my $case (@language_links) {
        my ($label, $link) = @$case;
        like $text{$rel}, qr/\Q$link\E/, "$rel has language link $label";
    }

    like $text{$rel}, _release_line_pattern($rel),
        "$rel keeps the v1.1.0-beta.1 release line";
    unlike $text{$rel}, qr/^README refs:\s+docs\/references\/README[.]md$/m,
        "$rel does not expose internal README reference notes";
    like $text{$rel}, qr/license-Apache--2[.]0-blue/,
        "$rel keeps the Apache-2.0 license badge";
    like $text{$rel}, qr/Apache License,\s+Version 2[.]0/,
        "$rel names Apache License 2.0 in the license section";
    like $text{$rel}, qr/Copyright 2026 GobanFTP contributors[.]/,
        "$rel carries the repository copyright notice";
    like $text{$rel}, qr/third-party|第三方|第三者/,
        "$rel says the license does not authorize third-party systems";
    like $text{$rel}, qr/security certification|生产安全认证|security\s+certification/,
        "$rel says the license is not a production security certification";
    unlike $text{$rel}, qr/perl_5|perl__5/,
        "$rel does not keep the old perl_5 license badge";
    like $text{$rel}, qr/\[.*?\]\(#the-shape\).*?\[.*?\]\(#the-fork\).*?\[.*?\]\(#why-this-exists\).*?\[.*?\]\(#see-it-first\).*?\[.*?\]\(#three-minute-proof\).*?\[.*?\]\(#terminal-play\).*?\[.*?\]\(#static-witness-specimen\).*?\[.*?\]\(#the-contract\)/s,
        "$rel uses stable local README anchors";
    like $text{$rel}, qr/static HTML .*hosted Web UI|Static HTML .*hosted Web UI|static HTML .*hosted Web UI/s,
        "$rel keeps static HTML separate from hosted Web UI";
    like $text{$rel}, qr/live DNS/s, "$rel keeps live DNS out of DNS record admission";
    like $text{$rel}, qr/production (?:auth|writer authorization|key lifecycle)/s,
        "$rel keeps production auth/key lifecycle outside signed material";
    like $text{$rel}, _webdav_https_pattern($rel),
        "$rel says authenticated WebDAV requires HTTPS";
    like $text{$rel}, _webdav_http_fixture_pattern($rel),
        "$rel keeps unauthenticated HTTP WebDAV out of production transport safety";
    like $text{$rel}, _local_path_descriptor_pattern($rel),
        "$rel says local path basenames must be game descriptors";
    like $text{$rel}, _truth_surface_pattern($rel),
        "$rel keeps display and accelerator surfaces outside truth";
    unlike $text{$rel}, qr/\b(?:AI|ChatGPT|LLM|生成AI|人工智能|大模型|機械翻訳)\b/i,
        "$rel has no generated-content marker";
}

unlike $text{'README.zh-CN.md'}, qr/v1[.]0 明确不声称/,
    'Chinese README does not keep stale v1.0 non-claim wording';
like $text{'README.zh-CN.md'}, qr/v1[.]1[.]0-beta[.]1\/package 1[.]100_001 明确不声称/,
    'Chinese README scopes non-claims to the current v1.1 beta line';

my $manifest = _read_text(File::Spec->catfile($repo_root, 'MANIFEST'));
for my $rel (@readmes) {
    like $manifest, qr/^\Q$rel\E$/m, "MANIFEST includes $rel";
}

subtest 'local README links resolve' => sub {
    for my $rel (@readmes) {
        my @links = _markdown_links($text{$rel});
        for my $link (@links) {
            next if $link =~ /\A(?:https?:)?\/\//;
            next if $link =~ /\A#/;
            my ($target) = split /#/, $link, 2;
            next if !defined($target) || $target eq '';
            my $path = File::Spec->catfile($repo_root, split '/', $target);
            ok -e $path, "$rel link exists: $link";
        }
    }
};

done_testing;

sub _markdown_links {
    my ($text) = @_;
    my @links;
    while ($text =~ /\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g) {
        push @links, $1;
    }
    return @links;
}

sub _read_text {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "close $path: $!";
    return $text // '';
}

sub _release_line_pattern {
    my ($rel) = @_;
    return qr{Current beta release: `v1[.]1[.]0-beta[.]1/package 1[.]100_001`[.]} if $rel eq 'README.md';
    return qr{当前 beta 版本：`v1[.]1[.]0-beta[.]1/package 1[.]100_001`。} if $rel eq 'README.zh-CN.md';
    return qr{現在の beta リリース: `v1[.]1[.]0-beta[.]1/package 1[.]100_001`[.]} if $rel eq 'README.ja.md';
    die "unknown README $rel";
}

sub _truth_surface_pattern {
    my ($rel) = @_;
    return qr/source art \/ C \/ asm \/ Web UI \/ TUI -> cannot change truth/ if $rel eq 'README.md';
    return qr/代码画 \/ C \/ asm \/ Web UI \/ TUI -> 不能改变协议真相/ if $rel eq 'README.zh-CN.md';
    return qr/source art \/ C \/ asm \/ Web UI \/ TUI -> replay の真実を変えられません/ if $rel eq 'README.ja.md';
    die "unknown README $rel";
}

sub _webdav_https_pattern {
    my ($rel) = @_;
    return qr/Authenticated WebDAV URLs must use `https:\/\/`; Basic and Bearer credentials are\s+rejected on `http:\/\/`/
        if $rel eq 'README.md';
    return qr/带认证的 WebDAV URL 必须使用 `https:\/\/`；Basic 和 Bearer 凭据会在 `http:\/\/` 上被拒绝/
        if $rel eq 'README.zh-CN.md';
    return qr/認証付き WebDAV URL は `https:\/\/` が必須です。Basic と Bearer の認証情報は `http:\/\/` では拒否されます/
        if $rel eq 'README.ja.md';
    die "unknown README $rel";
}

sub _webdav_http_fixture_pattern {
    my ($rel) = @_;
    return qr/Unauthenticated `http:\/\/` remains available for\s+mock\/local cleartext fixtures and is not a production transport-safety mode/
        if $rel eq 'README.md';
    return qr/不带认证的 `http:\/\/` 保留给 mock\/本地明文 fixture 使用，不是生产传输安全模式/
        if $rel eq 'README.zh-CN.md';
    return qr/認証なしの `http:\/\/` は mock\/local の平文 fixture 用に残しているもので、production transport-safety mode ではありません/
        if $rel eq 'README.ja.md';
    die "unknown README $rel";
}

sub _local_path_descriptor_pattern {
    my ($rel) = @_;
    return qr/local argument is a path, only the final path component is used as the\s+game descriptor basename, and that basename must be a valid GOFTP game\s+descriptor/
        if $rel eq 'README.md';
    return qr/本地参数如果是路径，只使用最后一段作为 game descriptor basename；这个 basename 必须是合法的 GOFTP game descriptor/
        if $rel eq 'README.zh-CN.md';
    return qr/local argument が path の場合、最後の path component だけが game descriptor basename として使われます。その basename は有効な GOFTP game descriptor でなければなりません/
        if $rel eq 'README.ja.md';
    die "unknown README $rel";
}
