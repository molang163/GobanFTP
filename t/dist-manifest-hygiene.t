use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->rel2abs("$FindBin::Bin/..");

my @manifest = _read_lines(File::Spec->catfile($repo_root, 'MANIFEST'));
my $skip     = _read_text(File::Spec->catfile($repo_root, 'MANIFEST.SKIP'));

my @forbidden_manifest_entries = (
    [qr{\Adocs/SESSION_RESTORE[.]md\z},        'local resume notes'],
    [qr{\Adocs/V1_1_GATE_MEMO[.]md\z},         'local gate memo'],
    [qr{\Adocs/v1[.]1-unattended-plan[.]md\z}, 'local unattended plan'],
    [qr{\Aevidence(?:/|\z)},                   'local integration evidence'],
    [qr{\A(?:blib|_Inline)(?:/|\z)},           'local build tree'],
    [qr{\AMYMETA[.](?:json|yml)\z},            'local MYMETA file'],
    [qr{\Apm_to_blib\z},                       'MakeMaker copy stamp'],
    [qr{\AGobanFTP-[0-9][^/]*[.]tar[.]gz\z},  'nested distribution tarball'],
    [qr{\AGobanFTP-[0-9][^/]*/},               'stale distribution directory'],
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
);

my %manifest_entry = map { $_ => 1 } @manifest;
for my $entry (@required_manifest_entries) {
    ok $manifest_entry{$entry}, "MANIFEST includes $entry";
}

my @required_skip_rules = (
    ['_Inline tree',              '^_Inline/'],
    ['blib tree',                 '^blib/'],
    ['source META residue',       '^META\.(?:json|yml)$'],
    ['MYMETA files',              '^MYMETA\.(?:json|yml)$'],
    ['pm_to_blib',                '^pm_to_blib$'],
    ['distribution tarballs',     '^GobanFTP-[0-9][^/]*\.tar\.gz$'],
    ['distribution directories',  '^GobanFTP-[0-9][^/]*/'],
    ['local resume notes',        '^docs/SESSION_RESTORE\.md$'],
    ['local gate memo',           '^docs/V1_1_GATE_MEMO\.md$'],
    ['local unattended plan',      '^docs/v1\.1-unattended-plan\.md$'],
    ['local evidence directory',   '^evidence/'],
);

for my $case (@required_skip_rules) {
    my ($label, $rule) = @$case;
    ok index($skip, $rule) >= 0, "MANIFEST.SKIP keeps $label out";
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
