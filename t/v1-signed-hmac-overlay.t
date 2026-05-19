use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;
use GobanFTP::EventSetRoot qw(event_set_root_result);
use GobanFTP::Profile qw(profile);
use GobanFTP::Profile::Adapter qw(profile_listing_names);
use GobanFTP::Witness qw(witness_for_listing);

my $cross_dir = "$FindBin::Bin/fixtures/v1/cross-substrate";
my $signed_dir = "$FindBin::Bin/fixtures/v1/signed-hmac";
my $schema_path = "$FindBin::Bin/../docs/DIAGNOSTICS.md";
my $minimal_case = File::Spec->catdir($cross_dir, 'minimal');
my $attestations_path = File::Spec->catfile(
    $signed_dir,
    'valid',
    'signed-hmac-goftp1',
    'attestations.jsonl',
);
my $fixture_key = 'gobanftp signed hmac fixture key 1';

my @substrate_profiles = qw(
    local-goftp1
    ftp-goftp1
    git-tree-goftp1
    dns-record-goftp1
    webdav-goftp1
);

my $game = 'g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob';
my @minimal_events = qw(
    m1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m
    m1.p000002.w.play-bb.pa-khjclcui7pejbv3m.by-bob.n-chain2.h-bihb3re4k9hlucat
    m1.p000003.b.pass.pa-bihb3re4k9hlucat.by-alice.n-chain3.h-kcvtlonfje163p9q
);
my $injected_event =
    'm1.p000004.w.play-cc.pa-kcvtlonfje163p9q.by-bob.n-inject1.h-nr55esqpd0ika4bt';
my $minimal_root = '599c00f0614e400274a92ab1c96d09087a53d0d88bd8b0ecba481ac60a1f1461';

my @attestations = _read_jsonl($attestations_path);
my %trusted_hmac_keys = (
    'fixture-key-1' => $fixture_key,
);

subtest 'signed-HMAC overlay accepts the same truth across substrate normalizers' => sub {
    my %witnesses;

    for my $substrate (@substrate_profiles) {
        my @raw = _read_names(File::Spec->catfile($minimal_case, $substrate, 'listing.names'));
        my $substrate_profile = profile($substrate);
        my $witness = witness_for_listing(
            profile_id              => 'signed-hmac-goftp1',
            substrate_profile_id    => $substrate,
            game_descriptor         => $game,
            raw_names               => \@raw,
            hmac_attestations       => \@attestations,
            trusted_hmac_keys       => \%trusted_hmac_keys,
            diagnostics_schema_path => $schema_path,
        );
        $witnesses{$substrate} = $witness;

        is $witness->{profile_id}, 'signed-hmac-goftp1', "$substrate records signed profile";
        is $witness->{adapter_id}, 'signed-hmac-listing-goftp1',
            "$substrate records signed adapter";
        is $witness->{substrate_profile_id}, $substrate, "$substrate records substrate profile";
        is $witness->{substrate_adapter_id}, $substrate_profile->{adapter_id},
            "$substrate records substrate adapter";
        is $witness->{accepted_count}, 3, "$substrate accepts three signed events";
        is_deeply $witness->{accepted_events}, \@minimal_events,
            "$substrate signed-accepted events match";
        is $witness->{rejected_count}, 0, "$substrate has no signature rejections";
        is_deeply $witness->{rejected_classes}, [], "$substrate rejected classes are empty";
        is $witness->{event_set_root}, $minimal_root, "$substrate signed root is stable";
        is $witness->{replay_status}, 'ok', "$substrate signed replay is ok";
        is $witness->{canonical_tip}, 'kcvtlonfje163p9q',
            "$substrate signed canonical tip is stable";
        ok !grep({ m{/|href=|owner=|\bblob\b|\bmode=} } @{ $witness->{accepted_events} }),
            "$substrate accepted events are GOFTP basenames";
    }

    _assert_same_witness(\%witnesses, qw(
        accepted_count
        accepted_events
        rejected_count
        rejected_codes
        rejected_classes
        event_set_root
        replay_status
        canonical_tip
        canonical_ids
        legal_ids
        board_hash
        sgf_hash
        variations_sgf_hash
        diagnostic_codes
        diagnostic_classes
        diagnostic_count
    ));
};

subtest 'unsigned injections are rejected after substrate normalization' => sub {
    for my $substrate (@substrate_profiles) {
        my @raw = _read_names(File::Spec->catfile($minimal_case, $substrate, 'listing.names'));
        push @raw, _substrate_raw_event($substrate, $game, $injected_event);

        my @candidate_names = profile_listing_names(
            profile_id      => $substrate,
            game_descriptor => $game,
            raw_names       => \@raw,
        );
        my $unsigned = event_set_root_result(
            game_descriptor => $game,
            names           => \@candidate_names,
        );
        is $unsigned->{event_count}, 4, "$substrate unsigned substrate admits injection";
        ok grep({ $_ eq $injected_event } @{ $unsigned->{accepted_events} }),
            "$substrate unsigned event set contains injection before HMAC gate";
        isnt $unsigned->{event_set_root}, $minimal_root,
            "$substrate unsigned root changes before HMAC gate";

        my $witness = witness_for_listing(
            profile_id              => 'signed-hmac-goftp1',
            substrate_profile_id    => $substrate,
            game_descriptor         => $game,
            raw_names               => \@raw,
            hmac_attestations       => \@attestations,
            trusted_hmac_keys       => \%trusted_hmac_keys,
            diagnostics_schema_path => $schema_path,
        );

        ok grep({ $_ eq $injected_event } @{ $witness->{normalized_events} }),
            "$substrate injection reaches the signed gate";
        is $witness->{accepted_count}, 3, "$substrate signed gate keeps valid chain";
        is_deeply $witness->{accepted_events}, \@minimal_events,
            "$substrate signed gate excludes injection";
        is $witness->{rejected_count}, 1, "$substrate records one signature rejection";
        is_deeply $witness->{rejected_codes}, ['missing_signature'],
            "$substrate reports missing signature";
        is_deeply $witness->{rejected_classes}, ['signature'],
            "$substrate maps rejection to signature";
        is $witness->{rejected_diagnostics}[0]{name}, $injected_event,
            "$substrate diagnostic names injected event";
        is $witness->{event_set_root}, $minimal_root,
            "$substrate signed root remains the baseline root";
        is $witness->{replay_status}, 'ok', "$substrate accepted signed set still replays";
    }
};

subtest 'CLI exposes signed-HMAC overlay substrate fields' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--substrate-profile', 'ftp-goftp1',
        '--fixture', $minimal_case,
        '--attestations', $attestations_path,
        '--trusted-hmac-key', "fixture-key-1=$fixture_key",
    );

    is $exit, 0, 'CLI overlay exits success';
    is $stderr, '', 'CLI overlay emits no diagnostics';
    like $stdout, qr/^gobanftp[.]v1[.]witness=ok$/m, 'CLI overlay status is ok';
    like $stdout, qr/^profile_id=signed-hmac-goftp1$/m, 'CLI prints signed profile id';
    like $stdout, qr/^adapter_id=signed-hmac-listing-goftp1$/m, 'CLI prints signed adapter';
    like $stdout, qr/^substrate_profile_id=ftp-goftp1$/m, 'CLI prints substrate profile';
    like $stdout, qr/^substrate_adapter_id=ftp-listing-goftp1$/m, 'CLI prints substrate adapter';
    like $stdout, qr/^raw_count=8$/m, 'CLI reads FTP fixture listing';
    like $stdout, qr/^accepted_count=3$/m, 'CLI accepts the signed chain';
    like $stdout, qr/^rejected_count=0$/m, 'CLI has no signature rejection';
    like $stdout, qr/^event_set_root=\Q$minimal_root\E$/m, 'CLI prints stable signed root';
    like $stdout, qr/^signature[.]status=ok$/m, 'CLI prints signature status';
};

subtest 'CLI rejects substrate overlay outside signed-HMAC witness mode' => sub {
    my ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'local-goftp1',
        '--substrate-profile', 'ftp-goftp1',
        '--fixture', $minimal_case,
    );

    is $exit, 1, 'unsigned profile cannot request substrate overlay';
    is $stdout, '', 'usage failure writes no stdout';
    like $stderr, qr/^usage: v1 witness /m, 'usage is reported';

    ($exit, $stdout, $stderr) = _run_cli(
        'v1', 'witness',
        '--profile', 'signed-hmac-goftp1',
        '--substrate-profile', 'signed-hmac-goftp1',
        '--fixture', $minimal_case,
    );

    is $exit, 1, 'signed profile cannot be its own substrate overlay';
    is $stdout, '', 'signed substrate usage failure writes no stdout';
    like $stderr, qr/^usage: v1 witness /m, 'signed substrate usage is reported';
};

done_testing;

sub _assert_same_witness {
    my ($witnesses, @fields) = @_;

    my $baseline = $witnesses->{'local-goftp1'};
    for my $profile (grep { $_ ne 'local-goftp1' } sort keys %$witnesses) {
        for my $field (@fields) {
            my $got = $witnesses->{$profile}{$field};
            my $want = $baseline->{$field};
            if (ref $want) {
                is_deeply $got, $want, "$profile matches local $field";
            }
            else {
                is $got, $want, "$profile matches local $field";
            }
        }
    }
}

sub _substrate_raw_event {
    my ($substrate, $game, $event) = @_;

    return $event if $substrate eq 'local-goftp1';
    return "events/$event" if $substrate eq 'ftp-goftp1';
    return "100644 blob ffffffffffffffffffffffffffffffffffffffff\tevents/$event"
        if $substrate eq 'git-tree-goftp1';
    return "ttl=60 type=TXT owner=04.events.$game.example. event=$event"
        if $substrate eq 'dns-record-goftp1';
    return "href=/dav/$game/events/$event etag=\"W/inject\" last-modified=\"Mon, 18 May 2026 01:07:00 GMT\" content-length=211 content-type=application/octet-stream"
        if $substrate eq 'webdav-goftp1';

    die "unknown substrate profile: $substrate";
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

sub _read_jsonl {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @records;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @records, decode_json($line);
    }
    close $fh or die "close $path: $!";

    return @records;
}

sub _read_names {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @names;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @names, $line;
    }
    close $fh or die "close $path: $!";

    return @names;
}
