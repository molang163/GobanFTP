use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::KeyID qw(parse_public_key_record);
use GobanFTP::Auth::TrustReport qw(parse_trust_tsv trust_report_summary);

my $fixture_dir = "$FindBin::Bin/fixtures/auth/trust-report/advisory-ok";
my @keys = map { parse_public_key_record(_read_text($_)) } sort glob "$fixture_dir/keys/*.pub";
my $trust_tsv = _read_text("$fixture_dir/trust.tsv");

my @ids = qw(
    k1.jk4bs0r77srdlpds260hka9fpp49clpg
    k1.j0bq17f7tnre2rmihg81jnv8ud1r1crd
    k1.b9qqr423d7t8utun0q6f9nbt9o5jcita
    k1.8fqoc7krroqkucq5avbaa48qoi7p882a
);

subtest 'trust TSV summarizes public advisory key states' => sub {
    my @records = parse_trust_tsv($trust_tsv);
    is scalar(@records), 4, 'parses four trust records';

    my $summary = trust_report_summary(public_keys => \@keys, trust_tsv => $trust_tsv);
    is $summary->{status}, 'advisory', 'records advisory trust state';
    is $summary->{public_key_count}, 4, 'counts public keys';
    is $summary->{record_count}, 4, 'counts trust rows';
    is_deeply $summary->{public_key_ids}, [sort @ids], 'public key ids are content-derived and sorted';
    is_deeply $summary->{trusted_key_ids}, [$ids[0]], 'trusted key is reported';
    is_deeply $summary->{rotated_key_ids}, [$ids[1]], 'rotated key is reported';
    is_deeply $summary->{revoked_key_ids}, [$ids[2]], 'revoked key is reported';
    is_deeply $summary->{expired_key_ids}, [$ids[3]], 'expired key is reported';
};

subtest 'missing trust rows remain advisory state, not replay truth' => sub {
    my $with_key = trust_report_summary(public_keys => [$keys[0]]);
    is $with_key->{status}, 'untrusted', 'public keys without trust rows are untrusted advisory state';
    is $with_key->{public_key_count}, 1, 'public key is counted';
    is $with_key->{record_count}, 0, 'no trust records are counted';

    my $empty = trust_report_summary(public_keys => []);
    is $empty->{status}, 'unsigned', 'no public auth material is unsigned advisory state';
    is $empty->{public_key_count}, 0, 'no public keys are counted';
    is $empty->{record_count}, 0, 'no trust rows are counted';
};

subtest 'malformed trust material fails with stable parse reasons' => sub {
    my @cases = (
        ['header',          "BAD\n"],
        ['columns',         "GOFTP-TRUST/1\nkey_id\tstatus\n"],
        ['field_count',     "GOFTP-TRUST/1\n" . _columns() . "\n$ids[0]\tfixture-ed25519-v1\tplayer:alice\tplayer\ttrusted\t2026-01-01\t-\t-\n"],
        ['status',          _trust_line($ids[0], 'fixture-ed25519-v1', 'player:alice', 'player', 'unknown', '2026-01-01', '-', '-', 'bad')],
        ['key_id',          _trust_line('bad-key', 'fixture-ed25519-v1', 'player:alice', 'player', 'trusted', '2026-01-01', '-', '-', 'bad')],
        ['duplicate_key',   _trust_line($ids[0], 'fixture-ed25519-v1', 'player:alice', 'player', 'trusted', '2026-01-01', '-', '-', 'one')
                              . "$ids[0]\tfixture-ed25519-v1\tplayer:alice\tplayer\trevoked\t2026-01-01\t-\t2026-02-01\ttwo\n"],
        ['not_before',      _trust_line($ids[0], 'fixture-ed25519-v1', 'player:alice', 'player', 'trusted', '20260101', '-', '-', 'bad')],
        ['reason',          _trust_line($ids[0], 'fixture-ed25519-v1', 'player:alice', 'player', 'trusted', '2026-01-01', '-', '-', 'bad reason')],
    );

    for my $case (@cases) {
        my ($reason, $text) = @$case;
        $text = "GOFTP-TRUST/1\n" . _columns() . "\n$text"
            if $text !~ /\AGOF?TP-TRUST/ && $reason ne 'header' && $reason ne 'columns';
        like _exception(sub { parse_trust_tsv($text) }),
            qr/\Aparse_trust:\Q$reason\E\b/,
            "$reason is stable";
    }
};

subtest 'trust rows must match derived public key identity' => sub {
    my $missing = _trust_doc(_trust_row($ids[0], 'fixture-ed25519-v1', 'player:alice', 'player', 'trusted', '2026-01-01', '-', '-', 'fixture'));
    like _exception(sub { trust_report_summary(public_keys => [], trust_tsv => $missing) }),
        qr/\Aparse_trust:key[.]missing\b/,
        'trust row cannot invent a missing public key';

    my $suite_mismatch = _trust_doc(_trust_row($ids[0], 'other-suite', 'player:alice', 'player', 'trusted', '2026-01-01', '-', '-', 'fixture'));
    like _exception(sub { trust_report_summary(public_keys => [$keys[0]], trust_tsv => $suite_mismatch) }),
        qr/\Aparse_trust:suite[.]unsupported\b/,
        'unsupported suite fails before matching';

    my $duplicate_key = trust_report_summary(public_keys => [$keys[0]]);
    is $duplicate_key->{public_key_count}, 1, 'single public key summary succeeds';
    like _exception(sub { trust_report_summary(public_keys => [$keys[0], $keys[0]]) }),
        qr/\Aparse_public_key:duplicate_key\b/,
        'duplicate public key records fail closed';
};

done_testing;

sub _trust_line {
    return _trust_doc(_trust_row(@_));
}

sub _trust_doc {
    my ($rows) = @_;
    return "GOFTP-TRUST/1\n" . _columns() . "\n" . $rows;
}

sub _trust_row {
    return join("\t", @_) . "\n";
}

sub _columns {
    return join "\t", qw(key_id suite principal role status not_before not_after revoked_at reason);
}

sub _read_text {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "close $path: $!";
    return $text;
}

sub _exception {
    my ($code) = @_;
    my $error = '';
    eval { $code->(); 1 } or $error = $@;
    chomp $error;
    $error =~ s/\s+at \S+ line [0-9]+[.]\z//;
    return $error;
}
