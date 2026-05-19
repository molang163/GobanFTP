use v5.34;
use strict;
use warnings;

use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP ();
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::PublishToken qw(sign_publish_token);
use GobanFTP::CLI;
use GobanFTP::Diagnostics qw(
    default_diagnostics_schema
    diagnostic_class
    diagnostic_registry
    diagnostic_schema_json
    explain_diagnostic
);
use GobanFTP::Witness qw(witness_for_listing);

my $docs_path = "$FindBin::Bin/../docs/DIAGNOSTICS.md";
my $fixture_dir = "$FindBin::Bin/fixtures/e2e";
my $signed_hmac_fixture_dir = "$FindBin::Bin/fixtures/v1/signed-hmac";

my $signed_hmac_profile = 'signed-hmac-goftp1';
my $signed_hmac_game = 'g1.id-replay.s3.r-chinese-area-v1.k0.pb-alice.pw-bob';
my $signed_hmac_event =
    'm1.p000001.b.play-aa.pa-genesis.by-alice.n-chain1.h-khjclcui7pejbv3m';
my $signed_hmac_other_event =
    'm1.p000002.w.play-bb.pa-khjclcui7pejbv3m.by-bob.n-chain2.h-bihb3re4k9hlucat';
my $signed_hmac_key_id = 'fixture-key-1';
my $signed_hmac_secret = 'gobanftp signed hmac fixture key 1';

my @allowed_fields = qw(
    child_ids code color error event_id expected_color expected_player
    expected_ply index key_id name names parent_id parent_kind player ply
    profile_id reason signature_id stage target_id target_kind trust_set_id
);

my @allowed_classes = qw(parse event-id dag rules fork signature storage);

my @stdout_fields = qw(
    algorithm attestations board canonical_ids canonical_moves event event_id
    events game key_id key_path key_id_version public_key_version suite public_key_bytes
    game_descriptor profile_id profile_consensus_version adapter_id
    substrate_profile_id substrate_adapter_id
    ruleset_id ruleset_semver ruleset_seal_version ruleset_fixture_digest ruleset_seal
    fixture_id comparison_scope profile_count profiles baseline_profile compared_fields
    mismatch_count mismatch_fields mismatch_profiles profile_roots profile_replay_statuses
    raw_count normalized_count normalized_events accepted_count accepted_events
    rejected_count rejected_codes rejected_classes replay_status
    canonical_tip diagnostic_codes diagnostic_classes diagnostic_count
    board_hash sgf_hash variations_sgf_hash attestation_count
    trusted_hmac_key_ids signature.status event_set_count event_set_root
    trust.status trust.public_key_count trust.record_count
    trust.trusted_count trust.trusted_key_ids trust.rotated_count
    trust.rotated_key_ids trust.revoked_count trust.revoked_key_ids
    trust.expired_count trust.expired_key_ids
    publish_auth.status publish_auth.profile_id publish_auth.key_id
    publish_auth.diagnostic_codes publish_auth.diagnostic_classes
    publish_auth.diagnostic_count publish_token
    gobanftp.create-game gobanftp.play gobanftp.project
    gobanftp.publish-ack gobanftp.publish-move gobanftp.replay
    gobanftp.sgf gobanftp.verify gobanftp.v1.attest
    gobanftp.v1.publish-auth gobanftp.v1.publish-token
    gobanftp.v1.compare-replay gobanftp.v1.compare-roots
    gobanftp.v1.keygen gobanftp.v1.keyid gobanftp.v1.trust-report
    gobanftp.v1.witness gobanftp.watch legal_ids legal_moves
    listing root sgf snapshot store turn_color turn_player verdict worldline.status
    worldline.canonical_ids worldline.legal_ids worldline.fork.parent_id
    worldline.fork.child_ids
);

subtest 'diagnostics document defines emitted fields and secret policy' => sub {
    my $docs = _slurp($docs_path);

    like $docs, qr/diagnostic key=value key=value/, 'stderr line format is documented';
    like $docs, qr/Diagnostics must not print passwords/, 'secret policy is documented';
    like $docs, qr/environment\s+variables whose names contain/, 'secret environment variable policy is documented';
    for my $secret_word (qw(PASSWORD TOKEN SECRET KEY)) {
        like $docs, qr/\Q$secret_word\E/, "secret word is documented: $secret_word";
    }

    for my $field (@stdout_fields) {
        like $docs, qr/^\Q$field\E$/m, "stdout field is documented: $field";
    }

    for my $field (@allowed_fields) {
        like $docs, qr/^\Q$field\E$/m, "field is documented: $field";
    }

    my @schema = _diagnostic_schema($docs);
    ok @schema, 'diagnostic schema block is documented';

    my %allowed_field = map { $_ => 1 } @allowed_fields;
    my %allowed_class = map { $_ => 1 } @allowed_classes;
    my %schema_code;
    for my $row (@schema) {
        $schema_code{ $row->{code} } = 1;
        ok $allowed_class{ $row->{class} }, "schema class is documented: $row->{class}";

        for my $field (@{ $row->{required} }, @{ $row->{optional} }) {
            ok $allowed_field{$field}, "schema field is allowed: $row->{code}.$field";
        }
    }

    for my $code (_known_codes($docs)) {
        ok $schema_code{$code}, "known diagnostic code has schema: $code";
    }

    ok grep({ $_->{code} eq 'parse_event' && $_->{selector} eq 'error=event_id.*' && $_->{class} eq 'event-id' } @schema),
        'parse_event event-id selector is documented';
    ok grep({ $_->{code} eq 'parse_event' && $_->{selector} eq 'error=*' && $_->{class} eq 'parse' } @schema),
        'parse_event parse selector is documented';

    my @default_schema = @{ default_diagnostics_schema() };
    is_deeply(
        [
            map {
                +{
                    code     => $_->{code},
                    selector => $_->{selector},
                    class    => $_->{class},
                    required => $_->{required},
                    optional => $_->{optional},
                }
            } @default_schema
        ],
        [
            map {
                +{
                    code     => $_->{code},
                    selector => $_->{selector},
                    class    => $_->{class},
                    required => $_->{required},
                    optional => $_->{optional},
                }
            } @schema
        ],
        'built-in diagnostics registry matches docs schema fields',
    );

    for my $row (@default_schema) {
        ok defined($row->{explanation}) && $row->{explanation} ne '',
            "registry row has human explanation: $row->{code}/$row->{selector}";
        ok defined($row->{hint}) && $row->{hint} ne '',
            "registry row has operator hint: $row->{code}/$row->{selector}";
    }
};

subtest 'diagnostics registry exposes JSON, explanations, and storage class' => sub {
    my $registry = diagnostic_registry();
    ok grep({ $_->{code} eq 'storage' && $_->{class} eq 'storage' } @$registry),
        'storage diagnostic code is in the active registry';
    ok grep({ $_->{code} eq 'transport_stale' && $_->{class} eq 'storage' } @$registry),
        'transport_stale diagnostic code is in the active registry';
    ok grep({ $_->{code} eq 'publish_pending' && $_->{class} eq 'storage' } @$registry),
        'publish_pending diagnostic code is in the active registry';
    ok grep({ $_->{code} eq 'shadow_poisoned' && $_->{class} eq 'storage' } @$registry),
        'shadow_poisoned diagnostic code is in the active registry';

    is diagnostic_class({ code => 'storage', error => 'read_only' }), 'storage',
        'storage diagnostics classify without an explicit schema';
    like explain_diagnostic({ code => 'fork', parent_id => 'root', child_ids => ['a', 'b'] }),
        qr/\Afork: Multiple legal child moves compete/,
        'fork diagnostics have a human explanation';
    like explain_diagnostic({ code => 'parse_event', name => 'm1.bad', error => 'event_id.mismatch' }),
        qr/\Aparse_event: The event basename failed event-id validation[.]\z/,
        'selector-specific explanations are available';

    my $json = diagnostic_schema_json($registry);
    my $decoded = JSON::PP->new->decode($json);
    is ref($decoded), 'ARRAY', 'registry JSON encodes an array';
    ok grep({ $_->{code} eq 'storage' && $_->{class} eq 'storage' } @$decoded),
        'registry JSON preserves storage code';

    $registry->[0]{class} = 'mutated';
    is diagnostic_registry()->[0]{class}, 'event-id',
        'diagnostic_registry returns a deep clone';
};

subtest 'CLI diagnostics use documented fields and do not echo ignored secrets' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $game = _read_single(File::Spec->catfile($fixture_dir, 'game.name'));
    my @events = _read_names(File::Spec->catfile($fixture_dir, 'events.names'));
    my $game_root = File::Spec->catdir($root, $game);

    make_path(
        File::Spec->catdir($game_root, 'events'),
        File::Spec->catdir($game_root, 'sidecar'),
        File::Spec->catdir($game_root, 'tmp'),
    );

    _write_text(File::Spec->catfile($game_root, 'events', $events[0]), '');
    _write_text(File::Spec->catfile($game_root, 'events', 'm1.bad'), '');
    _write_text(File::Spec->catfile($game_root, 'sidecar', 'secret.txt'), "password=hunter2\n");
    _write_text(File::Spec->catfile($game_root, 'tmp', 'secret.part'), "token=super-secret\n");

    local $ENV{GOBANFTP_FTP_PASSWORD} = 'env-secret';
    my ($exit, $stdout, $stderr) = _run_cli('verify', $game_root);

    is $exit, 2, 'invalid event exits validation failure';
    like $stdout, qr/^gobanftp\.verify=failed$/m, 'failure summary is on stdout';
    like $stderr, qr/^diagnostic /m, 'diagnostic line is on stderr';
    unlike $stdout . $stderr, qr/hunter2|super-secret|env-secret|GOBANFTP_FTP_PASSWORD/,
        'diagnostics do not leak ignored sidecar tmp or environment secrets';

    my %allowed = map { $_ => 1 } @allowed_fields;
    my @schema = _diagnostic_schema(_slurp($docs_path));
    for my $line (grep { /^diagnostic / } split /\n/, $stderr) {
        my @pairs = split /\s+/, $line;
        shift @pairs;

        my %fields;
        for my $pair (@pairs) {
            my ($key, $value) = split /=/, $pair, 2;
            $fields{$key} = $value // '';
            ok $allowed{$key}, "diagnostic field is documented: $key";
        }
        ok $fields{code}, 'diagnostic line includes code';
        _assert_schema_match(\%fields, \@schema);
    }
};

subtest 'CLI reports direct unknown event versions as parser diagnostics' => sub {
    my $root = tempdir(CLEANUP => 1);
    my $game = _read_single(File::Spec->catfile($fixture_dir, 'game.name'));
    my $game_root = File::Spec->catdir($root, $game);
    my $unknown = 'm2.p000001.b.play-aa.pa-genesis.by-alice.n-future.h-0000000000000000';

    make_path(File::Spec->catdir($game_root, 'events'));
    _write_text(File::Spec->catfile($game_root, 'events', $unknown), '');

    my ($exit, $stdout, $stderr) = _run_cli('verify', $game_root);

    is $exit, 2, 'unknown event version exits validation failure';
    like $stdout, qr/^gobanftp\.verify=failed$/m, 'failure summary is on stdout';
    like $stdout, qr/^events=1$/m, 'direct unknown event child is counted as an event item';
    like $stderr, qr/^diagnostic /m, 'diagnostic line is on stderr';
    like $stderr, qr/\bcode=parse_event\b/, 'diagnostic code is stable';
    like $stderr, qr/\berror=event\.version\b/, 'parser error is stable';
    like $stderr, qr/\bname=\Q$unknown\E\b/, 'public event basename is reported';
};

subtest 'signed profile diagnostics expose contract fields and signature class' => sub {
    my @schema = _diagnostic_schema(_slurp($docs_path));
    my @cases = (
        {
            fixture => 'missing-signature',
            code    => 'missing_signature',
            fields  => [qw(code event_id name profile_id)],
        },
        {
            fixture => 'wrong-signature',
            code    => 'wrong_signature',
            fields  => [qw(code event_id key_id name profile_id reason)],
            reason  => 'signature.mismatch',
        },
        {
            fixture => 'untrusted-key-id',
            code    => 'untrusted_signature',
            fields  => [qw(code event_id key_id name profile_id reason)],
            reason  => 'key.untrusted',
        },
        {
            fixture => 'malformed-signature',
            code    => 'malformed_signature',
            fields  => [qw(code profile_id reason signature_id)],
            reason  => 'signature.format',
        },
    );

    for my $case (@cases) {
        my $witness = _signed_hmac_witness_for_case($case->{fixture});
        my ($diagnostic) = @{ $witness->{rejected_diagnostics} };

        is $witness->{rejected_count}, 1, "$case->{fixture}: one rejected event";
        is_deeply $witness->{rejected_codes}, [$case->{code}],
            "$case->{fixture}: rejected code is stable";
        is_deeply $witness->{rejected_classes}, ['signature'],
            "$case->{fixture}: rejected class is signature";
        _assert_signature_diagnostic_contract(
            $diagnostic,
            \@schema,
            $case,
            "$case->{fixture}: witness diagnostic",
        );
    }
};

subtest 'publish-auth diagnostics use signature contract fields and redact auth material' => sub {
    my @schema = _diagnostic_schema(_slurp($docs_path));
    my $root = tempdir(CLEANUP => 1);
    my $key_id = 'diagnostics-contract-key';
    my $secret = 'diagnostics-contract-secret-value';
    my $token = sign_publish_token(
        profile         => $signed_hmac_profile,
        game_descriptor => $signed_hmac_game,
        event_basename  => $signed_hmac_event,
        key_id          => $key_id,
        key             => $secret,
    );
    my $bad_signature = 'not-a-hex-signature';

    my @cases = (
        {
            name    => 'wrong-signature',
            token   => $token,
            event   => $signed_hmac_other_event,
            trusted => 1,
            code    => 'wrong_signature',
            fields  => [qw(code event_id key_id name profile_id reason)],
            reason  => 'event_basename.mismatch',
        },
        {
            name    => 'missing-signature',
            token   => _without_signature_fields($token),
            event   => $signed_hmac_event,
            trusted => 1,
            code    => 'missing_signature',
            fields  => [qw(code event_id name profile_id)],
        },
        {
            name    => 'malformed-signature',
            token   => {
                %$token,
                mac           => $bad_signature,
                signature     => $bad_signature,
                signature_hex => $bad_signature,
            },
            event   => $signed_hmac_event,
            trusted => 1,
            code    => 'malformed_signature',
            fields  => [qw(code profile_id reason signature_id)],
            reason  => 'signature.format',
        },
        {
            name    => 'untrusted-signature',
            token   => $token,
            event   => $signed_hmac_event,
            trusted => 0,
            code    => 'untrusted_signature',
            fields  => [qw(code event_id key_id name profile_id reason)],
            reason  => 'key.untrusted',
        },
    );

    for my $case (@cases) {
        my $token_path = File::Spec->catfile($root, "$case->{name}.jsonl");
        _write_jsonl($token_path, [$case->{token}]);

        my @args = (
            'v1', 'publish-auth',
            '--profile', $signed_hmac_profile,
            '--token', $token_path,
        );
        push @args, ('--trusted-hmac-key', "$key_id=$secret") if $case->{trusted};
        push @args, ($signed_hmac_game, $case->{event});

        my ($exit, $stdout, $stderr) = _run_cli(@args);
        my @diagnostics = _diagnostics_from_stderr($stderr);

        is $exit, 2, "$case->{name}: denied token exits validation";
        like $stdout, qr/^gobanftp[.]v1[.]publish-auth=denied$/m,
            "$case->{name}: command status is denied";
        like $stdout, qr/^publish_auth[.]status=denied$/m,
            "$case->{name}: publish_auth status is denied";
        like $stdout, qr/^diagnostic_codes=\Q$case->{code}\E$/m,
            "$case->{name}: stdout code summary is stable";
        like $stdout, qr/^diagnostic_classes=signature$/m,
            "$case->{name}: stdout class summary is signature";
        like $stdout, qr/^diagnostic_count=1$/m,
            "$case->{name}: stdout diagnostic count is stable";
        is scalar(@diagnostics), 1, "$case->{name}: one stderr diagnostic";

        _assert_signature_diagnostic_contract(
            $diagnostics[0],
            \@schema,
            $case,
            "$case->{name}: CLI diagnostic",
        );

        my $combined = $stdout . $stderr;
        unlike $combined, qr/\Q$secret\E/,
            "$case->{name}: trusted HMAC secret is not printed";
        unlike $combined, qr/\Q$token->{signature}\E/,
            "$case->{name}: full publish MAC is not printed";
        unlike $combined, qr/\Q$bad_signature\E/,
            "$case->{name}: malformed signature value is not printed";
    }
};

subtest 'CLI storage errors redact FTP messages that echo credentials' => sub {
    local %ENV = %ENV;
    $ENV{GOBANFTP_STORE} = 'ftp';
    $ENV{GOBANFTP_FTP_HOST} = 'mock.example';
    $ENV{GOBANFTP_FTP_USER} = 'alice';
    $ENV{GOBANFTP_FTP_PASSWORD} = 'env-secret';
    $ENV{API_TOKEN} = 'abc';
    $ENV{GOBANFTP_FTP_CLASS} = 'LeakyFTP';

    my $game = 'g1.id-redact.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
    my ($exit, $stdout, $stderr) = _run_cli('verify', $game);

    is $exit, 4, 'login failure exits storage failure';
    is $stdout, '', 'storage failure writes no stdout';
    like $stderr, qr/^storage: FTP login failed:/m, 'storage failure is reported';
    unlike $stderr, qr/env-secret|bearer-secret|cookie-secret|aws-secret|private-secret|pass-secret|\babc\b/,
        'storage error is redacted before reaching stderr';
    like $stderr, qr/\[REDACTED\]/, 'redaction marker is visible';
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

sub _read_single {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $line = <$fh>;
    close $fh or die "close $path: $!";
    die "$path is empty" if !defined $line;
    chomp $line;
    return $line;
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

sub _slurp {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "close $path: $!";
    return $text;
}

sub _write_text {
    my ($path, $text) = @_;

    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} $text;
    close $fh or die "close $path: $!";
}

sub _write_jsonl {
    my ($path, $rows) = @_;

    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    my $json = JSON::PP->new->canonical(1);
    for my $row (@$rows) {
        print {$fh} $json->encode($row), "\n";
    }
    close $fh or die "close $path: $!";
}

sub _read_jsonl {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @rows;
    my $json = JSON::PP->new;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @rows, $json->decode($line);
    }
    close $fh or die "close $path: $!";

    return @rows;
}

sub _signed_hmac_witness_for_case {
    my ($case) = @_;

    my $case_dir = File::Spec->catdir($signed_hmac_fixture_dir, $case);
    my $profile_dir = File::Spec->catdir($case_dir, $signed_hmac_profile);
    my $game = _read_single(File::Spec->catfile($case_dir, 'game.name'));
    my @raw_names = _read_names(File::Spec->catfile($profile_dir, 'listing.names'));
    my @attestations = _read_jsonl(File::Spec->catfile($profile_dir, 'attestations.jsonl'));

    return witness_for_listing(
        profile_id              => $signed_hmac_profile,
        game_descriptor         => $game,
        raw_names               => \@raw_names,
        diagnostics_schema_path => $docs_path,
        hmac_attestations       => \@attestations,
        trusted_hmac_keys       => { $signed_hmac_key_id => $signed_hmac_secret },
    );
}

sub _without_signature_fields {
    my ($token) = @_;

    my %copy = %$token;
    delete @copy{qw(mac signature signature_hex hmac_sha256)};
    return \%copy;
}

sub _diagnostics_from_stderr {
    my ($stderr) = @_;

    my @diagnostics;
    for my $line (grep { /^diagnostic / } split /\n/, $stderr) {
        my @pairs = split /\s+/, $line;
        shift @pairs;

        my %fields;
        for my $pair (@pairs) {
            my ($key, $value) = split /=/, $pair, 2;
            $fields{$key} = $value // '';
        }
        push @diagnostics, \%fields;
    }

    return @diagnostics;
}

sub _assert_signature_diagnostic_contract {
    my ($diagnostic, $schema, $case, $label) = @_;

    is $diagnostic->{code}, $case->{code}, "$label: code is stable";
    is diagnostic_class($diagnostic, $schema), 'signature', "$label: class is signature";
    is_deeply [sort keys %$diagnostic], [sort @{ $case->{fields} }],
        "$label: field set matches contract";
    is $diagnostic->{profile_id}, $signed_hmac_profile, "$label: profile id is public";
    is $diagnostic->{reason}, $case->{reason}, "$label: reason is stable"
        if exists $case->{reason};

    my %allowed = map { $_ => 1 } @allowed_fields;
    for my $field (keys %$diagnostic) {
        ok $allowed{$field}, "$label: diagnostic field is documented: $field";
    }
    _assert_schema_match($diagnostic, $schema);
}

sub _diagnostic_schema {
    my ($docs) = @_;

    my ($block) = $docs =~ /^```diagnostic-schema\n(.*?)^```/ms;
    die 'diagnostic-schema block not found' if !defined $block;

    my @lines = grep { /\S/ } split /\n/, $block;
    my $header = shift @lines // '';
    die "bad diagnostic schema header: $header"
        if $header ne 'code|selector|class|required|optional';

    my @schema;
    for my $line (@lines) {
        my ($code, $selector, $class, $required, $optional) = split /\|/, $line, 5;
        die "bad diagnostic schema line: $line"
            if !defined($code) || !defined($selector) || !defined($class)
                || !defined($required) || !defined($optional);

        push @schema, {
            code     => $code,
            selector => $selector,
            class    => $class,
            required => [_schema_fields($required)],
            optional => [_schema_fields($optional)],
        };
    }

    return @schema;
}

sub _schema_fields {
    my ($text) = @_;
    return () if !defined($text) || $text eq '' || $text eq '-';
    return split /,/, $text;
}

sub _known_codes {
    my ($docs) = @_;

    my ($block) = $docs =~ /The v1 diagnostic code registry includes:\n\n```text\n(.*?)\n```/s;
    die 'known code block not found' if !defined $block;
    return grep { /\S/ } split /\n/, $block;
}

sub _assert_schema_match {
    my ($diagnostic, $schema) = @_;

    my $row = _schema_row($diagnostic, $schema);
    ok defined($row), "diagnostic code has schema row: $diagnostic->{code}";
    return if !defined $row;

    for my $field (@{ $row->{required} }) {
        ok exists($diagnostic->{$field}), "diagnostic includes required field: $field";
    }
}

sub _schema_row {
    my ($diagnostic, $schema) = @_;

    my @candidates = grep { $_->{code} eq ($diagnostic->{code} // '') } @$schema;
    for my $row (@candidates) {
        return $row if _selector_matches($diagnostic, $row->{selector});
    }

    return undef;
}

sub _selector_matches {
    my ($diagnostic, $selector) = @_;

    return 1 if !defined($selector) || $selector eq '*';

    if ($selector =~ /\A([a-z_]+)=(.*)\z/) {
        my ($field, $want) = ($1, $2);
        my $got = $diagnostic->{$field} // '';
        return $got =~ /\A\Q$want\E\z/ if $want !~ /\*\z/;

        my $prefix = substr($want, 0, -1);
        return index($got, $prefix) == 0;
    }

    return 0;
}

package LeakyFTP;

use v5.34;
use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub login {
    return 0;
}

sub message {
    return join ' ',
        '530 PASS env-secret',
        'bare env-secret rejected',
        'short abc rejected',
        'Authorization: Bearer bearer-secret',
        'Cookie: session=cookie-secret',
        'AWS_SECRET_ACCESS_KEY=aws-secret',
        'private_key=private-secret',
        '--token pass-secret';
}
