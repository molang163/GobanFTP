use strict;
use warnings;

use FindBin;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::HMAC qw(
    event_attestation_preimage
    hmac_sha256_hex
    key_id_for_secret
    sign_event
    verify_event_signature
);
use GobanFTP::EventID qw(event_id);

my $fixture_dir = "$FindBin::Bin/fixtures/auth/hmac";

for my $case (_read_jsonl("$fixture_dir/digests.jsonl")) {
    if (exists $case->{hmac_sha256_hex}) {
        my $key = exists $case->{key_hex} ? pack('H*', $case->{key_hex}) : $case->{key};

        is hmac_sha256_hex($key, $case->{message}),
            $case->{hmac_sha256_hex},
            "$case->{id}: HMAC-SHA256 hex";
    }

    if (exists $case->{key_id}) {
        is key_id_for_secret($case->{key}),
            $case->{key_id},
            "$case->{id}: stable key id";
    }
}

my ($valid_case);

for my $case (_read_jsonl("$fixture_dir/event-signatures.jsonl")) {
    my $sign = $case->{sign};

    if ($sign) {
        $valid_case //= $case if $case->{id} eq 'valid_signature';

        is key_id_for_secret($sign->{key}),
            $sign->{key_id},
            "$case->{id}: signing key id";

        my $preimage = event_attestation_preimage(
            version         => $sign->{version},
            profile         => $sign->{profile},
            algorithm       => $sign->{algorithm},
            game_descriptor => $sign->{game_descriptor},
            event_basename  => $sign->{event_basename},
            event_id        => $sign->{event_id},
            key_id          => $sign->{key_id},
        );

        is unpack('H*', $preimage),
            $sign->{preimage_hex},
            "$case->{id}: attestation preimage framing";

        my $signature = sign_event(
            version         => $sign->{version},
            profile         => $sign->{profile},
            algorithm       => $sign->{algorithm},
            game_descriptor => $sign->{game_descriptor},
            event_basename  => $sign->{event_basename},
            event_id        => $sign->{event_id},
            key_id          => $sign->{key_id},
            key             => $sign->{key},
        );

        is $signature->{algorithm}, 'hmac-sha256', "$case->{id}: algorithm";
        is $signature->{signature}, $sign->{signature}, "$case->{id}: signature";
        is $signature->{mac}, $sign->{signature}, "$case->{id}: mac alias";
        is $signature->{signature_hex}, $sign->{signature}, "$case->{id}: signature_hex alias";
        is $signature->{profile}, $sign->{profile}, "$case->{id}: profile is carried";
        is $signature->{version}, $sign->{version}, "$case->{id}: version is carried";
        is $signature->{event_id}, $sign->{event_id}, "$case->{id}: event id is carried";
    }

    my $verify = $case->{verify};
    my %verify_args = (
        key             => $verify->{key},
        game_descriptor => $verify->{game_descriptor},
        event_basename  => $verify->{event_basename},
    );

    if ($sign) {
        @verify_args{qw(version profile algorithm event_id key_id signature)}
            = @{$sign}{qw(version profile algorithm event_id key_id signature)};
    }
    else {
        $verify_args{signature} = $verify->{signature_record};
    }
    for my $field (qw(version profile algorithm event_id key_id signature)) {
        $verify_args{$field} = $verify->{$field} if exists $verify->{$field};
    }

    my $result = verify_event_signature(%verify_args);

    is $result->{ok}, $verify->{expected_ok} ? 1 : 0, "$case->{id}: ok flag";
    is $result->{valid}, $verify->{expected_ok} ? 1 : 0, "$case->{id}: valid flag";
    is $result->{error}, $verify->{expected_error}, "$case->{id}: verification error";
}

subtest 'profile and version are part of the signed bytes' => sub {
    my $sign = $valid_case->{sign};

    my $wrong_profile = verify_event_signature(
        version         => $sign->{version},
        profile         => 'other-goftp1',
        algorithm       => $sign->{algorithm},
        game_descriptor => $sign->{game_descriptor},
        event_basename  => $sign->{event_basename},
        event_id        => $sign->{event_id},
        key_id          => $sign->{key_id},
        key             => $sign->{key},
        signature       => $sign->{signature},
    );
    is $wrong_profile->{error}, 'signature.mismatch', 'wrong profile fails closed';

    my $wrong_version = verify_event_signature(
        version         => 'GOFTP-HMAC-EVENT/2',
        profile         => $sign->{profile},
        algorithm       => $sign->{algorithm},
        game_descriptor => $sign->{game_descriptor},
        event_basename  => $sign->{event_basename},
        event_id        => $sign->{event_id},
        key_id          => $sign->{key_id},
        key             => $sign->{key},
        signature       => $sign->{signature},
    );
    is $wrong_version->{error}, 'signature.mismatch', 'wrong version fails closed';
};

subtest 'missing signature is parsed before key lookup' => sub {
    my $result = verify_event_signature(
        game_descriptor => $valid_case->{sign}{game_descriptor},
        event_basename  => $valid_case->{sign}{event_basename},
    );

    is $result->{error}, 'signature.missing', 'missing signature has a stable parse error';
};

subtest 'GOFTP/1 event id remains filename-derived' => sub {
    my $sign = $valid_case->{sign};
    my $event_without_hash = $sign->{event_basename};
    $event_without_hash =~ s/[.]h-[^.]+\z//;

    is event_id($sign->{game_descriptor}, $event_without_hash),
        'f98qai37nace5spg',
        'HMAC helper does not change the GOFTP/1 event id';
};

subtest 'attestation API accepts basenames, not event paths' => sub {
    my $sign = $valid_case->{sign};

    my $error = do {
        local $@;
        eval {
            event_attestation_preimage(
                version         => $sign->{version},
                profile         => $sign->{profile},
                algorithm       => $sign->{algorithm},
                game_descriptor => $sign->{game_descriptor},
                event_basename  => "events/$sign->{event_basename}",
                event_id        => $sign->{event_id},
                key_id          => $sign->{key_id},
            );
        };
        $@;
    };

    like $error, qr/event_basename must be a basename/, 'event path is rejected';
};

done_testing;

sub _read_jsonl {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";

    my @cases;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @cases, decode_json($line);
    }

    close $fh or die "close $path: $!";

    return @cases;
}
