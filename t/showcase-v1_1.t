use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

my $minimal_root = '599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461';
my @expected_files = qw(
    index.html
    witness-clean.html
    witness-fork.html
    demo-transcript.txt
    release-evidence.txt
    roots.json
);

subtest 'showcase writes static fixture artifacts and JSON evidence' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $out = File::Spec->catdir($root, 'showcase');

    my ($exit, $stdout, $stderr) = _run_cli('showcase', '--out', $out, '--json');
    is $exit, 0, 'showcase exits success';
    is $stderr, '', 'showcase has no diagnostics';

    my $doc = decode_json($stdout);
    is $doc->{schema}, 'gobanftp.showcase.v1', 'showcase JSON has scoped schema';
    is $doc->{version}, '1.1', 'showcase JSON has version 1.1';
    is $doc->{boundary}, 'static-fixture-only', 'showcase boundary is fixture-only';
    is $doc->{auth_boundary}{publish_preflight}{scope}, 'fixture-preflight',
        'showcase carries auth boundary metadata';
    is $doc->{auth_boundary}{publish_preflight}{production_authorization}, 0,
        'showcase does not claim production auth';
    is scalar(@{ $doc->{cases} }), 2, 'showcase reports clean and fork cases';
    is_deeply $doc->{files}, \@expected_files, 'showcase JSON reports the fixed expected file list';

    my @entries = _dir_entries($out);
    is_deeply \@entries, [sort @expected_files], 'showcase output directory contains exactly expected files';

    for my $file (@{ $doc->{files} }) {
        ok -f File::Spec->catfile($out, $file), "showcase wrote $file";
    }

    my $roots = decode_json(_slurp(File::Spec->catfile($out, 'roots.json')));
    is $roots->{schema}, 'gobanftp.showcase.v1', 'roots JSON has scoped schema';
    is $roots->{cases}[0]{event_set_root}, $minimal_root, 'roots JSON records the clean fixture root';

    my $index = _slurp(File::Spec->catfile($out, 'index.html'));
    like $index, qr/\A<!doctype html>\n/, 'index is direct-open HTML';
    like $index, qr/data-boundary="static-fixture-only"/, 'index carries static boundary';
    like $index, qr/<nav aria-label="Static showcase files">/,
        'index includes static showcase navigation';
    like $index, qr/<a href="#cases">Cases<\/a>/,
        'index navigation links to local cases anchor';
    like $index, qr/<a href="demo-transcript[.]txt">Demo transcript<\/a>/,
        'index navigation links to the generated transcript';
    like $index, qr/<a href="release-evidence[.]txt">Release evidence<\/a>/,
        'index navigation links to release evidence';
    unlike $index, qr/<script\b/i, 'index has no script';
    unlike $index, qr/\b(?:https?:)?\/\//i, 'index loads no remote resources';
    unlike $index, qr/<(?:form|input|button)\b/i, 'index is not an interactive hosted UI';

    my $clean = _slurp(File::Spec->catfile($out, 'witness-clean.html'));
    like $clean, qr/<dt>event_set_root<\/dt><dd>\Q$minimal_root\E<\/dd>/,
        'clean witness HTML includes the fixture root';
    like $clean, qr/<nav class="surface-nav" aria-label="Showcase sections">/,
        'clean witness includes static section navigation';
    like $clean, qr/<a href="#witness">Witness<\/a>/,
        'clean witness navigation links to the witness summary';
    like $clean, qr/<a href="#projection-board">projection[.]board<\/a>/,
        'clean witness navigation links to board projection';
    like $clean, qr/<section id="witness" class="witness">/,
        'clean witness summary has a local anchor target';
    like $clean, qr/<section id="projection-board" class="projection projection-board">/,
        'clean witness board projection has a local anchor target';
    unlike $clean, qr/<script\b/i, 'clean witness has no script';

    my $transcript = _slurp(File::Spec->catfile($out, 'demo-transcript.txt'));
    like $transcript, qr/^boundary=static-fixture-only$/m, 'transcript names static boundary';
    like $transcript, qr/^auth\.production_authorization=0$/m, 'transcript names auth non-goal';

    for my $file (grep { /[.]html\z/ } @entries) {
        my $html = _slurp(File::Spec->catfile($out, $file));
        for my $forbidden (
            ['script tag',        qr/<script\b/i],
            ['event handler attr', qr/\bon[a-z]+\s*=/i],
            ['javascript/data URL', qr/\b(?:href|src|srcset|action)\s*=\s*["']?\s*(?:javascript|data):/i],
            ['fetch API',         qr/\bfetch\s*\(/i],
            ['WebSocket API',     qr/\bWebSocket\b/],
            ['EventSource API',   qr/\bEventSource\b/],
            ['XMLHttpRequest API', qr/\bXMLHttpRequest\b/],
            ['worker API',        qr/\b(?:Worker|SharedWorker|ServiceWorker|navigator[.]serviceWorker)\b/],
            ['CSS url loader',    qr/\burl\s*\(/i],
            ['resource loader tag', qr/<(?:iframe|object|embed|link|img|audio|video|source|track)\b/i],
            ['remote http URL',   qr{http://}i],
            ['remote https URL',  qr{https://}i],
            ['protocol-relative URL', qr{(?<!:)//}],
            ['form/input/button', qr/<(?:form|input|button)\b/i],
            ['meta refresh',      qr/<meta\b[^>]*\bhttp-equiv\s*=\s*["']?refresh/i],
        ) {
            my ($label, $pattern) = @$forbidden;
            unlike $html, $pattern, "$file contains no $label";
        }

        my %allowed_href = map { $_ => 1 } @expected_files;
        while ($html =~ /\b(?:href|src|srcset|action)\s*=\s*["']([^"']+)["']/gi) {
            my $target = $1;
            ok $target =~ /\A#[A-Za-z0-9_-]+\z/ || $allowed_href{$target},
                "$file link target stays local and allowlisted: $target";
        }
    }
};

subtest 'showcase refuses unexpected pre-existing output files' => sub {
    for my $unexpected (qw(old.js stale.html)) {
        my $root = tempdir(CLEANUP => 1);
        my $out = File::Spec->catdir($root, 'showcase');
        mkdir $out or die "mkdir $out: $!";
        _write_text(File::Spec->catfile($out, $unexpected), "stale\n");

        my ($exit, $stdout, $stderr) = _run_cli('showcase', '--out', $out, '--json');
        isnt $exit, 0, "$unexpected: showcase fails for an unexpected pre-existing file";
        is $stderr, '', "$unexpected: JSON failure keeps diagnostics on stdout";

        my $doc = _decode_json_or_fail($stdout, "$unexpected: showcase failure JSON");
        is $doc->{schema}, 'gobanftp.showcase.v1', "$unexpected: failure JSON has scoped schema";
        is $doc->{version}, '1.1', "$unexpected: failure JSON has version 1.1";
        is $doc->{status}, 'failed', "$unexpected: failure JSON reports failed status";
        is $doc->{diagnostics}[0]{code}, 'showcase_out_dir_not_clean',
            "$unexpected: failure JSON reports stable diagnostic code";

        my @entries = _dir_entries($out);
        is_deeply \@entries, [$unexpected], "$unexpected: failure writes no partial showcase files";
    }
};

subtest 'showcase may overwrite a directory containing only expected files' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $out = File::Spec->catdir($root, 'showcase');
    mkdir $out or die "mkdir $out: $!";
    for my $file (@expected_files) {
        _write_text(File::Spec->catfile($out, $file), "STALE-$file\n");
    }

    my ($exit, $stdout, $stderr) = _run_cli('showcase', '--out', $out, '--json');
    is $exit, 0, 'showcase exits success when only expected files pre-exist';
    is $stderr, '', 'showcase overwrite has no diagnostics';
    my $doc = decode_json($stdout);
    is $doc->{status}, 'ok', 'showcase overwrite reports ok status';
    is_deeply $doc->{files}, \@expected_files, 'showcase overwrite reports expected file list';

    my @entries = _dir_entries($out);
    is_deeply \@entries, [sort @expected_files], 'showcase overwrite leaves exactly expected files';
    for my $file (@expected_files) {
        unlike _slurp(File::Spec->catfile($out, $file)), qr/STALE-\Q$file\E/,
            "showcase overwrote stale expected $file";
    }
};

subtest 'showcase refuses expected-name non-regular output entries' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $out = File::Spec->catdir($root, 'showcase');
    mkdir $out or die "mkdir $out: $!";
    mkdir File::Spec->catdir($out, 'index.html') or die "mkdir expected-name directory: $!";

    my ($exit, $stdout, $stderr) = _run_cli('showcase', '--out', $out, '--json');
    isnt $exit, 0, 'showcase fails for an expected-name pre-existing directory';
    is $stderr, '', 'expected-name directory failure keeps diagnostics on stdout';
    my $doc = _decode_json_or_fail($stdout, 'expected-name directory failure JSON');
    is $doc->{diagnostics}[0]{code}, 'showcase_out_dir_not_clean',
        'expected-name directory reports stable diagnostic code';
    is_deeply [_dir_entries($out)], ['index.html'],
        'expected-name directory failure writes no partial showcase files';

    my $link_root = tempdir(CLEANUP => 1);
    my $link_out = File::Spec->catdir($link_root, 'showcase');
    mkdir $link_out or die "mkdir $link_out: $!";
    my $outside = File::Spec->catfile($link_root, 'outside-roots.json');
    _write_text($outside, "outside sentinel\n");
    my $link = File::Spec->catfile($link_out, 'roots.json');
    if (!eval { symlink $outside, $link }) {
        diag 'symlink unavailable; skipping symlink-specific showcase check';
        return;
    }

    ($exit, $stdout, $stderr) = _run_cli('showcase', '--out', $link_out, '--json');
    isnt $exit, 0, 'showcase fails for an expected-name pre-existing symlink';
    is $stderr, '', 'expected-name symlink failure keeps diagnostics on stdout';
    $doc = _decode_json_or_fail($stdout, 'expected-name symlink failure JSON');
    is $doc->{diagnostics}[0]{code}, 'showcase_out_dir_not_clean',
        'expected-name symlink reports stable diagnostic code';
    is _slurp($outside), "outside sentinel\n", 'showcase does not follow output symlink outside --out';
    is_deeply [_dir_entries($link_out)], ['roots.json'],
        'expected-name symlink failure writes no partial showcase files';
};

done_testing;

sub _run_cli {
    my (@args) = @_;

    my ($stdout, $stderr) = ('', '');
    open my $out_fh, '>', \$stdout or die "open stdout scalar: $!";
    open my $err_fh, '>', \$stderr or die "open stderr scalar: $!";

    my $exit;
    {
        local *STDOUT = $out_fh;
        local *STDERR = $err_fh;
        $exit = GobanFTP::CLI->run(@args);
    }

    return ($exit, $stdout, $stderr);
}

sub _slurp {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "close $path: $!";
    return $text // '';
}

sub _write_text {
    my ($path, $text) = @_;

    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} $text;
    close $fh or die "close $path: $!";
}

sub _dir_entries {
    my ($path) = @_;

    opendir my $dh, $path or die "opendir $path: $!";
    my @entries = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh or die "closedir $path: $!";

    return @entries;
}

sub _decode_json_or_fail {
    my ($text, $label) = @_;

    my $doc = eval { decode_json($text) };
    if ($@) {
        fail "$label decodes JSON";
        diag "decode error: $@";
        diag "stdout was: $text";
        return {};
    }

    pass "$label decodes JSON";
    return $doc;
}
