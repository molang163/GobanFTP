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
        "$rel keeps the v1.0/package release line";
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
    like $text{$rel}, _truth_surface_pattern($rel),
        "$rel keeps display and accelerator surfaces outside truth";
    unlike $text{$rel}, qr/\b(?:AI|ChatGPT|LLM|生成AI|人工智能|大模型|機械翻訳)\b/i,
        "$rel has no generated-content marker";
}

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
    return qr/Current release: `v1[.]0[.]1\/package 1[.]001`[.]/ if $rel eq 'README.md';
    return qr/当前版本：`v1[.]0[.]1\/package 1[.]001`。/ if $rel eq 'README.zh-CN.md';
    return qr/現在のリリース: `v1[.]0[.]1\/package 1[.]001`[.]/ if $rel eq 'README.ja.md';
    die "unknown README $rel";
}

sub _truth_surface_pattern {
    my ($rel) = @_;
    return qr/source art \/ C \/ asm \/ Web UI \/ TUI -> cannot change truth/ if $rel eq 'README.md';
    return qr/代码画 \/ C \/ asm \/ Web UI \/ TUI -> 不能改变协议真相/ if $rel eq 'README.zh-CN.md';
    return qr/source art \/ C \/ asm \/ Web UI \/ TUI -> replay の真実を変えられません/ if $rel eq 'README.ja.md';
    die "unknown README $rel";
}
