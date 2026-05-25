use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->rel2abs("$FindBin::Bin/..");

my @manifest = _read_lines(File::Spec->catfile($repo_root, 'MANIFEST'));
my $skip     = _read_text(File::Spec->catfile($repo_root, 'MANIFEST.SKIP'));
my $gitignore = _read_text(File::Spec->catfile($repo_root, '.gitignore'));
my @skip_patterns = _manifest_skip_patterns($skip);

my @forbidden_manifest_entries = (
    [qr{\Adocs/SESSION_RESTORE[.]md\z},        'local resume notes'],
    [qr{\Adocs/V1_1_UPDATE_CHECKLIST[.]md\z},  'retired v1.1 update checklist'],
    [qr{\Adocs/references(?:/|\z)},            'reference-only docs'],
    [qr{\A(?:blib|_Inline)(?:/|\z)},           'local build tree'],
    [qr{\AMakefile(?:[.]old)?\z},               'generated Makefile residue'],
    [qr{\AMETA[.](?:json|yml)\z},               'source META residue'],
    [qr{\AMYMETA[.](?:json|yml)\z},            'local MYMETA file'],
    [qr{\Apm_to_blib\z},                       'MakeMaker copy stamp'],
    [qr{\AGobanFTP-[0-9][^/]*[.]tar[.]gz\z},  'nested distribution tarball'],
    [qr{\AGobanFTP-[0-9][^/]*/},               'stale distribution directory'],
    [qr{\A(?!t/fixtures/).*[.](?:bak|tmp|part)\z}, 'non-fixture scratch file'],
    [qr{\A(?!t/fixtures/)(?:.*/)?[.]gobanftp-tmp-[^/]+\z}, 'non-fixture gobanftp tmp scratch'],
);

for my $case (@forbidden_manifest_entries) {
    my ($pattern, $label) = @$case;
    my @matches = grep { /$pattern/ } @manifest;
    is_deeply \@matches, [], "MANIFEST excludes $label";
}

my @required_manifest_entries = qw(
    lib/GobanFTP/Showcase/StaticPreview.pm
    t/showcase-preview.t
    t/store-config.t
    t/fixtures/attacks/tmp-poison/tmp/pending.part
);

my %manifest_entry = map { $_ => 1 } @manifest;
for my $entry (@required_manifest_entries) {
    ok $manifest_entry{$entry}, "MANIFEST includes $entry";
}

my @required_skip_rules = (
    ['_Inline tree',              '^_Inline/'],
    ['blib tree',                 '^blib/'],
    ['generated Makefile',        '^Makefile$'],
    ['generated Makefile.old',    '^Makefile\.old$'],
    ['source META residue',       '^META\.(?:json|yml)$'],
    ['MYMETA files',              '^MYMETA\.(?:json|yml)$'],
    ['pm_to_blib',                '^pm_to_blib$'],
    ['distribution tarballs',     '^GobanFTP-[0-9][^/]*\.tar\.gz$'],
    ['distribution directories',  '^GobanFTP-[0-9][^/]*/'],
    ['reference-only docs',       '^docs/references(?:/|$)'],
    ['retired v1.1 checklist',    '^docs/V1_1_UPDATE_CHECKLIST\.md$'],
    ['non-fixture .part scratch', '^(?!t/fixtures/).*[.]part$'],
    ['non-fixture .tmp scratch',  '^(?!t/fixtures/).*[.]tmp$'],
    ['non-fixture .bak scratch',  '^(?!t/fixtures/).*[.]bak$'],
    ['non-fixture gobanftp tmp',  '^(?!t/fixtures/)(?:.*/)?[.]gobanftp-tmp-[^/]+$'],
    ['local resume notes',        '^docs/SESSION_RESTORE\.md$'],
);

for my $case (@required_skip_rules) {
    my ($label, $rule) = @$case;
    ok index($skip, $rule) >= 0, "MANIFEST.SKIP keeps $label out";
}

for my $path (qw(
    Makefile
    Makefile.old
    META.json
    META.yml
    MYMETA.json
    MYMETA.yml
    pm_to_blib
)) {
    ok _path_is_skipped($path, \@skip_patterns),
        "MANIFEST.SKIP excludes generated residue $path";
}

for my $path (qw(
    Makefile
    Makefile.old
    META.json
    META.yml
    MYMETA.json
    MYMETA.yml
    pm_to_blib
)) {
    like $gitignore, qr/^\Q$path\E$/m,
        ".gitignore excludes generated residue $path";
}

ok _path_is_skipped('docs/references/README.md', \@skip_patterns),
    'MANIFEST.SKIP excludes docs/references';
ok _path_is_skipped('docs/references/nested/note.md', \@skip_patterns),
    'MANIFEST.SKIP excludes the full docs/references tree';
ok _path_is_skipped('docs/V1_1_UPDATE_CHECKLIST.md', \@skip_patterns),
    'MANIFEST.SKIP excludes the retired v1.1 checklist';
like $gitignore, qr/^docs\/references\/$/m,
    '.gitignore excludes local docs/references material';
like $gitignore, qr/^docs\/V1_1_UPDATE_CHECKLIST[.]md$/m,
    '.gitignore excludes the retired v1.1 checklist';
ok !-e File::Spec->catfile($repo_root, qw(docs references README.md)),
    'public source tree omits README reference notes';
ok !-d File::Spec->catdir($repo_root, qw(docs references)),
    'public source tree omits reference-only docs tree';
ok _path_is_skipped('scratch/output.part', \@skip_patterns),
    'MANIFEST.SKIP excludes non-fixture .part scratch';
ok _path_is_skipped('scratch/output.tmp', \@skip_patterns),
    'MANIFEST.SKIP excludes non-fixture .tmp scratch';
ok _path_is_skipped('scratch/output.bak', \@skip_patterns),
    'MANIFEST.SKIP excludes non-fixture .bak scratch';
ok _path_is_skipped('scratch/.gobanftp-tmp-demo', \@skip_patterns),
    'MANIFEST.SKIP excludes non-fixture gobanftp tmp scratch';
ok !_path_is_skipped('t/fixtures/attacks/tmp-poison/tmp/pending.part', \@skip_patterns),
    'MANIFEST.SKIP allows fixture .part files';

for my $suffix (qw(bak tmp part)) {
    my $ignore = "*.$suffix";
    my $allow = "!t/fixtures/**/*.$suffix";
    my $ignore_index = index($gitignore, $ignore);
    my $allow_index = index($gitignore, $allow);

    ok $allow_index >= 0, ".gitignore has fixture .$suffix exception";
    ok $ignore_index >= 0 && $allow_index > $ignore_index,
        ".gitignore fixture .$suffix exception follows global ignore";
}

done_testing;

sub _read_lines {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @lines;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        my ($entry) = split /\s+/, $line, 2;
        push @lines, $entry;
    }
    close $fh or die "close $path: $!";

    return @lines;
}

sub _read_text {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "close $path: $!";

    return $text // '';
}

sub _manifest_skip_patterns {
    my ($text) = @_;

    my @patterns;
    for my $line (split /\n/, $text // '') {
        $line =~ s/\A\s+|\s+\z//g;
        next if $line eq '' || $line =~ /\A#/;
        push @patterns, qr/$line/;
    }

    return @patterns;
}

sub _path_is_skipped {
    my ($path, $patterns) = @_;

    for my $pattern (@$patterns) {
        return 1 if $path =~ /$pattern/;
    }

    return 0;
}
