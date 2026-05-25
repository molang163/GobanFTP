use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

my $repo_root = File::Spec->rel2abs("$FindBin::Bin/..");
my $poison_vector_path = File::Spec->catfile(
    $repo_root, qw(t fixtures vectors v1-non-consensus-poison.jsonl)
);

my %poison = map { ($_->{id} // '') => $_ } _read_jsonl($poison_vector_path);

subtest 'non-consensus poison vectors cover the v1.1 truth boundary' => sub {
    my %required = (
        'core-bad-payload-public-vector' => [qw(file-bytes file-size)],
        'core-bad-mtime-public-vector' => [qw(mtime)],
        'core-bad-list-order-public-vector' => [qw(listing-order)],
        'core-poisoned-sidecar-public-vector' => [qw(sidecar)],
        'core-projection-poison-public-vector' => [qw(projections)],
        'core-tmp-poison-public-vector' => [qw(tmp)],
        'ftp-listing-shadow-poison-public-vector' => [
            qw(ftp-sidecar ftp-tmp ftp-projection ftp-recursive-descendant ftp-list-order)
        ],
        'webdav-metadata-poison-public-vector' => [
            qw(sidecar projection tmp content metadata list-order recursive-href wrong-game-href duplicate-href)
        ],
        'git-tree-path-metadata-poison-public-vector' => [
            qw(git-object-size git-sidecar git-tmp git-projections recursive-path wrong-game-path duplicate-entry)
        ],
        'dns-owner-poison-public-vector' => [
            qw(dns-ttl dns-answer-order dns-sidecar dns-projection-owner dns-tmp-owner dns-wrong-game-owner dns-duplicate-event)
        ],
        'webdav-href-traversal-public-vector' => [
            qw(webdav-dot-segment webdav-encoded-dot-segment webdav-encoded-slash webdav-encoded-backslash)
        ],
    );

    for my $id (sort keys %required) {
        my $vector = $poison{$id};
        ok $vector, "$id exists";
        next if !$vector;

        is $vector->{vector_version}, 'GOFTP-V1-NON-CONSENSUS-POISON/1',
            "$id declares the public vector version";
        is_deeply $vector->{consensus_inputs}, [qw(game_descriptor accepted_event_basenames)],
            "$id declares the only consensus inputs";
        _has_all($vector->{ignored_inputs}, $required{$id}, "$id ignored inputs");
        _has_all(
            $vector->{same_witness_fields},
            [qw(event_set_root accepted_count accepted_events replay_status board_hash sgf_hash variations_sgf_hash)],
            "$id same witness fields",
        );
        ok !grep({ m{/} } @{ $vector->{expected_witness}{accepted_events} // [] }),
            "$id accepted events are direct basenames";
    }
};

subtest 'attack verdicts bind file metadata and shadow rows outside consensus' => sub {
    my %required = (
        't/fixtures/attacks/bad-payload/expected.verdict' => [qw(file-bytes file-size)],
        't/fixtures/attacks/bad-mtime/expected.verdict' => [qw(mtime)],
        't/fixtures/attacks/bad-list-order/expected.verdict' => [qw(listing-order)],
        't/fixtures/attacks/poisoned-sidecar/expected.verdict' => [qw(sidecar)],
        't/fixtures/attacks/projection-poison/expected.verdict' => [qw(projections)],
        't/fixtures/attacks/tmp-poison/expected.verdict' => [qw(tmp)],
        't/fixtures/v1/attacks/webdav-metadata-poison/expected.verdict' => [
            qw(webdav-content-length resource-body-not-read webdav-tmp webdav-sidecar webdav-projections recursive-href wrong-game-href href-order)
        ],
        't/fixtures/v1/attacks/git-tree-path-metadata-poison/expected.verdict' => [
            qw(git-object-size git-sidecar git-tmp git-projections recursive-path wrong-game-path)
        ],
        't/fixtures/v1/attacks/dns-owner-poison/expected.verdict' => [
            qw(dns-ttl dns-answer-order dns-sidecar dns-projection-owner dns-tmp-owner dns-wrong-game-owner dns-duplicate-event)
        ],
    );

    for my $rel (sort keys %required) {
        my $verdict = _read_verdict(File::Spec->catfile($repo_root, split m{/}, $rel));
        is $verdict->{status}, 'ok', "$rel is an accepted conformance verdict";
        like $verdict->{event_set_root} // '', qr/\A[0-9a-f]{64}\z/,
            "$rel records a stable event_set_root";
        _has_all([ split /,/, $verdict->{ignored_inputs} // '' ], $required{$rel}, "$rel ignored inputs");
        is $verdict->{consensus_inputs}, 'descriptor,events',
            "$rel keeps the legacy descriptor/events consensus label";
    }
};

subtest 'compare commands gate cross-substrate roots and replay' => sub {
    my $fixture = File::Spec->catdir($repo_root, qw(t fixtures v1 cross-substrate minimal));

    my ($exit, $stdout, $stderr) = _run_cli('v1', 'compare-roots', '--fixture', $fixture);
    is $exit, 0, 'compare-roots exits success';
    is $stderr, '', 'compare-roots has no diagnostics';
    like $stdout, qr/^gobanftp[.]v1[.]compare-roots=ok$/m, 'compare-roots status is ok';
    like $stdout, qr/^profile_count=5$/m, 'compare-roots covers five fixture profiles';
    like $stdout, qr/^profiles=local-goftp1,ftp-goftp1,git-tree-goftp1,dns-record-goftp1,webdav-goftp1$/m,
        'compare-roots covers Local, FTP, Git, DNS, and WebDAV';
    like $stdout, qr/^mismatch_count=0$/m, 'compare-roots reports no mismatches';
    like $stdout, qr/^event_set_root=599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461$/m,
        'compare-roots records the minimal fixture root';

    ($exit, $stdout, $stderr) = _run_cli('v1', 'compare-replay', '--fixture', $fixture);
    is $exit, 0, 'compare-replay exits success';
    is $stderr, '', 'compare-replay has no diagnostics';
    like $stdout, qr/^gobanftp[.]v1[.]compare-replay=ok$/m, 'compare-replay status is ok';
    like $stdout, qr/^profile_count=5$/m, 'compare-replay covers five fixture profiles';
    like $stdout, qr/^mismatch_count=0$/m, 'compare-replay reports no mismatches';
    like $stdout, qr/^replay_status=ok$/m, 'compare-replay records common replay success';
    like $stdout, qr/^accepted_events=[^\/\n]+$/m, 'compare-replay accepted events are direct basenames';
};

done_testing;

sub _has_all {
    my ($got, $want, $label) = @_;

    my %got = map { $_ => 1 } @{ $got // [] };
    for my $item (@$want) {
        ok $got{$item}, "$label includes $item";
    }
}

sub _read_jsonl {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @rows;
    while (my $line = <$fh>) {
        next if $line =~ /\A\s*\z/;
        push @rows, decode_json($line);
    }
    close $fh or die "close $path: $!";

    return @rows;
}

sub _read_verdict {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my %verdict;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        my ($key, $value) = split /=/, $line, 2;
        die "bad verdict line in $path: $line" if !defined($key) || !defined($value);
        $verdict{$key} = $value;
    }
    close $fh or die "close $path: $!";

    return \%verdict;
}

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
