use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use JSON::PP qw(decode_json encode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::PublishToken qw(publish_authorization_result);
use GobanFTP::Diagnostics qw(diagnostic_classes diagnostic_codes schema_from_file);
use GobanFTP::Witness qw(witness_for_listing);

my $repo_root   = File::Spec->rel2abs("$FindBin::Bin/..");
my $vector_path = "$FindBin::Bin/fixtures/vectors/v1-publish-auth.jsonl";
my $schema_path = "$FindBin::Bin/../docs/DIAGNOSTICS.md";
my $schema      = schema_from_file($schema_path);

my %trusted_hmac_keys = (
    'fixture-key-1' => 'gobanftp signed hmac fixture key 1',
);

my @unsigned_witness_fields = qw(
    profile_id
    profile_consensus_version
    adapter_id
    raw_count
    normalized_count
    normalized_events
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
    diagnostic_codes
    diagnostic_classes
    diagnostic_count
    replay_diagnostics
    board_hash
    sgf_hash
    variations_sgf_hash
);

my @vectors = _read_jsonl($vector_path);
ok @vectors, 'loaded publish-auth golden vectors';

my %seen_id;
for my $vector (@vectors) {
    my $id = $vector->{id} // '<missing id>';
    subtest $id => sub {
        ok !$seen_id{$id}++, 'vector id is unique';

        for my $field (qw(
            id
            vector_version
            attack
            profile_id
            game_descriptor
            consensus_inputs
            auth_inputs
            unsigned_ignored_inputs
            unsigned_profile_id
            unsigned_listing_fixture
            unsigned_input_names
            token_event_basename
            candidate_event_basename
            candidate_event_id
            trusted_hmac_key_ids
            trusted_hmac_key_statuses
            publish_token
            expected_authorization
            expected_unsigned_witness
            note
        )) {
            ok exists $vector->{$field}, "vector has $field";
        }

        is $vector->{vector_version}, 'GOFTP-V1-PUBLISH-AUTH/1',
            'vector declares publish-auth vector version';
        is $vector->{profile_id}, 'signed-hmac-goftp1',
            'vector covers signed-HMAC publish auth';
        is_deeply $vector->{consensus_inputs},
            [qw(game_descriptor accepted_event_basenames)],
            'vector keeps GOFTP/1 consensus inputs narrow';
        is_deeply $vector->{unsigned_ignored_inputs},
            [qw(publish_token trusted_hmac_key_selector trusted_hmac_key_status candidate_event_basename)],
            'vector declares auth material ignored by unsigned replay';
        ok $vector->{note} ne '', 'vector has a public judgment note';

        like $vector->{unsigned_listing_fixture},
            qr{\At/fixtures/v1/attacks/[^/]+/local-goftp1/listing[.]names\z},
            'unsigned fixture points at a local profile listing';
        my $listing_path = File::Spec->rel2abs($vector->{unsigned_listing_fixture}, $repo_root);
        my @fixture_names = _read_names($listing_path);
        is_deeply $vector->{unsigned_input_names}, \@fixture_names,
            'unsigned input names match fixture';

        is $vector->{publish_token}{version}, 'GOFTP-HMAC-PUBLISH/1',
            'token has publish auth version';
        is $vector->{publish_token}{purpose}, 'publish',
            'token has publish purpose';
        is $vector->{publish_token}{profile}, $vector->{profile_id},
            'token profile matches vector profile';
        is $vector->{publish_token}{game_descriptor}, $vector->{game_descriptor},
            'token binds the vector game';
        is $vector->{publish_token}{event_basename}, $vector->{token_event_basename},
            'token event matches vector token event';
        isnt $vector->{token_event_basename}, $vector->{candidate_event_basename},
            'token event differs from publish candidate';
        unlike join("\n", @{ $vector->{unsigned_input_names} }),
            qr/\Q$vector->{candidate_event_basename}\E/,
            'denied publish candidate is absent from unsigned listing';
        unlike encode_json($vector), qr/\Qgobanftp signed hmac fixture key 1\E/,
            'public vector does not embed HMAC secret';

        my %trusted_keys;
        for my $key_id (@{ $vector->{trusted_hmac_key_ids} }) {
            ok exists($trusted_hmac_keys{$key_id}), 'trusted selector is a known fixture key';
            $trusted_keys{$key_id} = $trusted_hmac_keys{$key_id};
        }
        is_deeply [sort keys %{ $vector->{trusted_hmac_key_statuses} }],
            [sort @{ $vector->{trusted_hmac_key_ids} }],
            'vector records lifecycle status for every trusted selector';

        my $auth = publish_authorization_result(
            profile_id                => $vector->{profile_id},
            game_descriptor           => $vector->{game_descriptor},
            event_basename            => $vector->{candidate_event_basename},
            token                     => $vector->{publish_token},
            trusted_hmac_keys         => \%trusted_keys,
            trusted_hmac_key_statuses => $vector->{trusted_hmac_key_statuses},
        );
        my $auth_got = {
            %$auth,
            diagnostic_codes   => [diagnostic_codes($auth->{diagnostics})],
            diagnostic_classes => [diagnostic_classes($auth->{diagnostics}, $schema)],
            diagnostic_count   => scalar @{ $auth->{diagnostics} },
        };
        is_deeply $auth_got, $vector->{expected_authorization},
            'publish-auth mismatch result matches golden vector';
        is $auth_got->{status}, 'denied', 'publish-auth mismatch is denied';
        is $auth_got->{diagnostics}[0]{reason}, 'event_basename.mismatch',
            'publish-auth mismatch reason is stable';

        my $witness = witness_for_listing(
            profile_id              => $vector->{unsigned_profile_id},
            game_descriptor         => $vector->{game_descriptor},
            raw_names               => $vector->{unsigned_input_names},
            diagnostics_schema_path => $schema_path,
        );
        for my $field (@unsigned_witness_fields) {
            my $got  = $witness->{$field};
            my $want = $vector->{expected_unsigned_witness}{$field};
            if (ref $want) {
                is_deeply $got, $want, "unsigned $field matches golden vector";
            }
            else {
                is $got, $want, "unsigned $field matches golden vector";
            }
        }
        unlike join(',', @{ $witness->{accepted_events} }),
            qr/\Q$vector->{candidate_event_basename}\E/,
            'unsigned GOFTP/1 accepted set does not include denied candidate';
    };
}

ok $seen_id{'publish-auth-event-basename-mismatch-public-vector'},
    'publish-auth event basename mismatch vector is present';

done_testing;

sub _read_jsonl {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @rows;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @rows, decode_json($line);
    }
    close $fh or die "close $path: $!";

    return @rows;
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
