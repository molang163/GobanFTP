use v5.34;
use strict;
use warnings;

use FindBin;
use File::Basename qw(dirname);
use File::Spec;
use JSON::PP qw(decode_json);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::DAG qw(build);
use GobanFTP::Diagnostics qw(
    diagnostic_classes
    diagnostic_codes
    replay_status
    schema_from_file
);
use GobanFTP::EventSetRoot qw(event_set_root_preimage);
use GobanFTP::Profile::Adapter qw(profile_listing_names);
use GobanFTP::Replay qw(replay);
use GobanFTP::Witness qw(witness_for_listing);

my $repo_root          = File::Spec->rel2abs("$FindBin::Bin/..");
my $vector_path        = "$FindBin::Bin/fixtures/vectors/v1-witness.jsonl";
my $replay_vector_path = "$FindBin::Bin/fixtures/vectors/v1-replay-invariants.jsonl";
my $dag_vector_path    = "$FindBin::Bin/fixtures/vectors/v1-dag-invariants.jsonl";
my $poison_vector_path = "$FindBin::Bin/fixtures/vectors/v1-non-consensus-poison.jsonl";
my $schema_path        = "$FindBin::Bin/../docs/DIAGNOSTICS.md";
my $schema             = schema_from_file($schema_path);

my @witness_fields = qw(
    profile_id
    profile_consensus_version
    adapter_id
    game_descriptor
    ruleset_id
    ruleset_semver
    ruleset_seal_version
    ruleset_fixture_digest
    ruleset_seal
    raw_count
    normalized_count
    normalized_events
    accepted_count
    accepted_events
    rejected_count
    rejected_diagnostics
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
    projection_text
);

my @vectors = _read_jsonl($vector_path);
ok @vectors, 'loaded v1 witness golden vectors';

my %seen_id;
for my $vector (@vectors) {
    my $id = $vector->{id} // '<missing id>';
    subtest $id => sub {
        ok !$seen_id{$id}++, 'vector id is unique';

        for my $field (qw(id input_fixture input_names), @witness_fields) {
            ok exists $vector->{$field}, "vector has $field";
        }

        like $vector->{input_fixture},
            qr{\At/fixtures/v1/cross-substrate/[^/]+/[^/]+/listing\.names\z},
            'input fixture points at a cross-substrate listing';

        my $listing_path = File::Spec->rel2abs($vector->{input_fixture}, $repo_root);
        my $case_dir     = dirname(dirname($listing_path));
        my $game_path    = File::Spec->catfile($case_dir, 'game.name');

        my $game = _read_single($game_path);
        is $game, $vector->{game_descriptor}, 'vector game descriptor matches fixture';

        my @raw = _read_names($listing_path);
        is_deeply $vector->{input_names}, \@raw,
            'vector input names match fixture';

        my $witness = witness_for_listing(
            profile_id              => $vector->{profile_id},
            game_descriptor         => $game,
            raw_names               => $vector->{input_names},
            diagnostics_schema_path => $schema_path,
            include_projection_text => 1,
        );

        for my $field (@witness_fields) {
            my $got  = $witness->{$field};
            my $want = $vector->{$field};
            if (ref $want) {
                is_deeply $got, $want, "$field matches golden vector";
            }
            else {
                is $got, $want, "$field matches golden vector";
            }
        }
    };
}

for my $case (qw(minimal fork fork-with-ack bad-event-id future-version missing-parent wrong-player)) {
    for my $profile (qw(local-goftp1 ftp-goftp1 git-tree-goftp1 dns-record-goftp1 webdav-goftp1)) {
        ok $seen_id{"$case-$profile"}, "$case $profile vector is present";
    }
}

my @poison_vectors = _read_jsonl($poison_vector_path);
ok @poison_vectors, 'loaded v1 non-consensus poison golden vectors';

my %seen_poison_id;
for my $vector (@poison_vectors) {
    my $id = $vector->{id} // '<missing id>';
    subtest "poison invariant $id" => sub {
        ok !$seen_poison_id{$id}++, 'poison vector id is unique';

        for my $field (qw(
            id
            vector_version
            attack
            game_descriptor
            consensus_inputs
            ignored_inputs
            evidence_markers
            expected_event_set_preimage_hex
            baseline
            poisoned
            same_witness_fields
            same_projection_text_fields
            expected_witness
        )) {
            ok exists $vector->{$field}, "vector has $field";
        }

        is $vector->{vector_version}, 'GOFTP-V1-NON-CONSENSUS-POISON/1',
            'vector declares non-consensus poison vector version';
        is_deeply $vector->{consensus_inputs}, [qw(game_descriptor accepted_event_basenames)],
            'vector declares the only truth inputs';

        _assert_poison_evidence($vector);

        for my $side (qw(baseline poisoned)) {
            ok ref($vector->{$side}) eq 'HASH', "$side input is an object";
            ok exists $vector->{$side}{profile_id}, "$side has profile_id";
            ok exists $vector->{$side}{input_fixture}, "$side has input_fixture";
            ok exists $vector->{$side}{input_names}, "$side has input_names";
            ok ref($vector->{$side}{input_names}) eq 'ARRAY', "$side input_names is an array";
            ok @{ $vector->{$side}{input_names} }, "$side input_names has rows";

            my $input_fixture = File::Spec->rel2abs($vector->{$side}{input_fixture}, $repo_root);
            my @raw = _read_names($input_fixture);
            is_deeply $vector->{$side}{input_names}, \@raw,
                "$side input_names match fixture";
        }

        _assert_poison_markers($vector);
        _assert_poison_order($vector) if exists $vector->{poisoned_order};

        my %witness;
        for my $side (qw(baseline poisoned)) {
            $witness{$side} = witness_for_listing(
                profile_id              => $vector->{$side}{profile_id},
                game_descriptor         => $vector->{game_descriptor},
                raw_names               => $vector->{$side}{input_names},
                diagnostics_schema_path => $schema_path,
                include_projection_text => 1,
            );

            my @profile_names = profile_listing_names(
                profile_id      => $vector->{$side}{profile_id},
                game_descriptor => $vector->{game_descriptor},
                raw_names       => $vector->{$side}{input_names},
            );
            my $preimage_hex = unpack 'H*', event_set_root_preimage(
                game_descriptor => $vector->{game_descriptor},
                names           => \@profile_names,
            );

            is $preimage_hex, $vector->{expected_event_set_preimage_hex},
                "$side event-set preimage matches poison golden vector";
            is $witness{$side}{raw_count}, scalar(@{ $vector->{$side}{input_names} }),
                "$side raw count matches vector input";
        }

        ok $witness{poisoned}{raw_count} > $witness{baseline}{raw_count},
            'poisoned input carries extra non-consensus rows';
        ok $witness{poisoned}{normalized_count} >= $witness{poisoned}{accepted_count},
            'poisoned input may contain duplicate candidates before event-set admission';

        for my $side (qw(baseline poisoned)) {
            for my $field (sort keys %{ $vector->{expected_witness} }) {
                _assert_golden_value(
                    $witness{$side}{$field},
                    $vector->{expected_witness}{$field},
                    "$side $field matches poison golden vector",
                );
            }
        }

        for my $field (@{ $vector->{same_witness_fields} }) {
            _assert_golden_value(
                $witness{poisoned}{$field},
                $witness{baseline}{$field},
                "poisoned witness matches baseline $field",
            );
        }

        for my $field (@{ $vector->{same_projection_text_fields} }) {
            _assert_golden_value(
                $witness{poisoned}{projection_text}{$field},
                $witness{baseline}{projection_text}{$field},
                "poisoned projection text matches baseline $field",
            );
        }

        my $projection_text = join '', map { $witness{poisoned}{projection_text}{$_} // '' }
            @{ $vector->{same_projection_text_fields} };
        for my $marker (values %{ $vector->{evidence_markers} }) {
            unlike $projection_text, qr/\Q$marker\E/,
                'poison evidence marker is not copied into invariant projection text';
        }
    };
}

for my $case (qw(
    webdav-metadata-poison-public-vector
    webdav-href-traversal-public-vector
    dns-owner-poison-public-vector
    git-tree-path-metadata-poison-public-vector
)) {
    ok $seen_poison_id{$case}, "$case poison invariant vector is present";
}

my @replay_vectors = _read_jsonl($replay_vector_path);
ok @replay_vectors, 'loaded v1 replay invariant golden vectors';

my @replay_vector_fields = qw(
    game_descriptor
    policy
    input_events
    replay_status
    canonical_ids
    legal_ids
    diagnostic_codes
    diagnostic_classes
    diagnostic_count
    diagnostics
    illegal_by_id
    ack_ids_by_target
    final_board_rows
    final_next_color
    final_consecutive_passes
    final_terminal
);

my %seen_replay_id;
for my $vector (@replay_vectors) {
    my $id = $vector->{id} // '<missing id>';
    subtest "replay invariant $id" => sub {
        ok !$seen_replay_id{$id}++, 'replay vector id is unique';

        for my $field (qw(id), @replay_vector_fields) {
            ok exists $vector->{$field}, "vector has $field";
        }

        like $vector->{policy}, qr/\A(?:conservative|ack-assisted)\z/,
            'v1 replay vector uses a supported policy';
        ok @{ $vector->{input_events} }, 'vector has input events';
        ok !grep({ m{/} } @{ $vector->{input_events} }), 'input events are basenames';

        my $result = replay(
            game_descriptor => $vector->{game_descriptor},
            events          => $vector->{input_events},
            policy          => $vector->{policy},
        );
        my @diagnostics = $result->diagnostics;
        my $final_state = $result->final_state;

        is replay_status(\@diagnostics), $vector->{replay_status},
            'replay status matches golden vector';
        is_deeply [$result->canonical_ids], $vector->{canonical_ids},
            'canonical ids match golden vector';
        is_deeply [$result->legal_ids], $vector->{legal_ids},
            'legal ids match golden vector';
        is_deeply [diagnostic_codes(\@diagnostics)], $vector->{diagnostic_codes},
            'diagnostic codes match golden vector';
        is_deeply [diagnostic_classes(\@diagnostics, $schema)], $vector->{diagnostic_classes},
            'diagnostic classes match golden vector';
        is scalar(@diagnostics), $vector->{diagnostic_count},
            'diagnostic count matches golden vector';
        is_deeply \@diagnostics, $vector->{diagnostics},
            'diagnostics match golden vector';
        is_deeply $result->illegal_by_id, $vector->{illegal_by_id},
            'illegal replay map matches golden vector';
        is_deeply $result->ack_ids_by_target, $vector->{ack_ids_by_target},
            'accepted ACK target map matches golden vector';
        is_deeply _board_rows($final_state), $vector->{final_board_rows},
            'final board rows match golden vector';
        is $final_state->{next_color}, $vector->{final_next_color},
            'final next color matches golden vector';
        is $final_state->{consecutive_passes}, $vector->{final_consecutive_passes},
            'final pass count matches golden vector';
        is $final_state->{terminal} ? 1 : 0, $vector->{final_terminal},
            'final terminal flag matches golden vector';
    };
}

for my $case (qw(
    illegal-sibling-preserves-legal-line
    invalid-root-preflight-diagnostics
    outsider-ack-keeps-move-canonical
    ack-assisted-fork-choice
    malformed-basename
    parent-not-move
    dangling-ack-target
    ack-target-not-move
    capture-removes-surrounded-stone
    suicide-rejection-preserves-board
    bounds-rejection-stays-at-genesis
    single-pass-advances-turn
    two-pass-terminal
    resign-terminal
    simple-ko-superko-rejects-recapture
)) {
    ok $seen_replay_id{$case}, "$case replay invariant vector is present";
}

my @dag_vectors = _read_jsonl($dag_vector_path);
ok @dag_vectors, 'loaded v1 DAG invariant golden vectors';

my @dag_vector_fields = qw(
    boundary
    synthetic
    ordinary_basename_collision
    input_items
    absent_node_ids
    move_ids
    ack_ids
    topological_move_ids
    children_of
    forks
    diagnostic_codes
    diagnostic_classes
    diagnostic_count
    diagnostics
);

my %seen_dag_id;
for my $vector (@dag_vectors) {
    my $id = $vector->{id} // '<missing id>';
    subtest "DAG invariant $id" => sub {
        ok !$seen_dag_id{$id}++, 'DAG vector id is unique';

        for my $field (qw(id), @dag_vector_fields) {
            ok exists $vector->{$field}, "vector has $field";
        }

        is $vector->{boundary}, 'dag', 'vector is explicitly a DAG-boundary vector';
        ok $vector->{synthetic}, 'vector is explicitly synthetic';
        ok !$vector->{ordinary_basename_collision},
            'vector does not claim ordinary basenames collide';
        ok @{ $vector->{input_items} }, 'vector has input items';

        for my $item (@{ $vector->{input_items} }) {
            ok ref($item) eq 'HASH', 'input item is an object';
            ok exists $item->{name}, 'input item has name';
            ok exists $item->{event}, 'input item has synthetic parsed event';
            unlike $item->{name}, qr/\A(?:m1|a1)\./,
                'synthetic item name is not an ordinary GOFTP event basename';
        }

        my $dag = build(events => $vector->{input_items});
        my @diagnostics = $dag->diagnostics;

        for my $node_id (@{ $vector->{absent_node_ids} }) {
            is $dag->node($node_id), undef, "$node_id is absent from DAG nodes";
        }

        is_deeply [$dag->move_ids], $vector->{move_ids},
            'move ids match golden vector';
        is_deeply [$dag->ack_ids], $vector->{ack_ids},
            'ack ids match golden vector';
        is_deeply [$dag->topological_move_ids], $vector->{topological_move_ids},
            'topological move ids match golden vector';

        for my $parent_id (sort keys %{ $vector->{children_of} }) {
            is_deeply [$dag->children_of($parent_id)], $vector->{children_of}{$parent_id},
                "$parent_id children match golden vector";
        }

        is_deeply $dag->forks, $vector->{forks},
            'forks match golden vector';
        is_deeply [diagnostic_codes(\@diagnostics)], $vector->{diagnostic_codes},
            'diagnostic codes match golden vector';
        is_deeply [diagnostic_classes(\@diagnostics, $schema)], $vector->{diagnostic_classes},
            'diagnostic classes match golden vector';
        is scalar(@diagnostics), $vector->{diagnostic_count},
            'diagnostic count matches golden vector';
        is_deeply \@diagnostics, $vector->{diagnostics},
            'DAG diagnostics match golden vector';
    };
}

for my $case (qw(event-id-collision-synthetic)) {
    ok $seen_dag_id{$case}, "$case DAG invariant vector is present";
}

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

sub _read_single {
    my ($path) = @_;

    my @names = _read_names($path);
    die "$path must contain exactly one nonblank line" if @names != 1;
    return $names[0];
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

sub _assert_golden_value {
    my ($got, $want, $name) = @_;

    if (ref $want) {
        is_deeply $got, $want, $name;
    }
    else {
        is $got, $want, $name;
    }
}

sub _assert_poison_markers {
    my ($vector) = @_;

    ok ref($vector->{evidence_markers}) eq 'HASH',
        'evidence markers are an object';
    ok scalar(keys %{ $vector->{evidence_markers} }),
        'vector declares poison evidence markers';

    my $raw = join "\n", @{ $vector->{poisoned}{input_names} };
    for my $evidence (sort keys %{ $vector->{evidence_markers} }) {
        my $marker = $vector->{evidence_markers}{$evidence};
        ok defined($marker) && $marker ne '' && index($raw, $marker) >= 0,
            "poisoned input carries $evidence marker";
    }
}

sub _assert_poison_evidence {
    my ($vector) = @_;

    my $ignored_inputs = ref($vector->{ignored_inputs}) eq 'ARRAY'
        ? $vector->{ignored_inputs}
        : [];

    ok ref($vector->{ignored_inputs}) eq 'ARRAY',
        'ignored inputs are an array';
    ok @$ignored_inputs,
        'vector declares ignored inputs';

    my %ignored;
    for my $input (@$ignored_inputs) {
        ok defined($input) && $input ne '', 'ignored input name is nonempty';
        ok !$ignored{$input}++, "ignored input is unique: $input";
    }

    if (ref($vector->{evidence_markers}) eq 'HASH') {
        for my $evidence (sort keys %{ $vector->{evidence_markers} }) {
            ok $ignored{$evidence}, "evidence marker is declared ignored input: $evidence";
        }
    }
}

sub _assert_poison_order {
    my ($vector) = @_;

    my $poisoned_order = ref($vector->{poisoned_order}) eq 'ARRAY'
        ? $vector->{poisoned_order}
        : [];

    ok ref($vector->{poisoned_order}) eq 'ARRAY',
        'poisoned order is an array';
    my @order = @$poisoned_order;
    ok @order >= 2, 'poisoned order declares multiple events';

    my @positions;
    for my $event (@order) {
        my ($index) = grep { index($vector->{poisoned}{input_names}[$_], $event) >= 0 }
            0 .. $#{ $vector->{poisoned}{input_names} };
        ok defined $index, "poisoned input contains ordered event $event";
        push @positions, $index if defined $index;
    }

    if (@positions == @order) {
        my $is_strictly_increasing = 1;
        for my $i (1 .. $#positions) {
            $is_strictly_increasing &&= $positions[$i - 1] < $positions[$i];
        }
        ok $is_strictly_increasing, 'poisoned listing order is represented by raw rows';
    }

    isnt join("\0", @order),
        join("\0", @{ $vector->{expected_witness}{accepted_events} }),
        'poisoned listing order differs from accepted event-set order';
}

sub _board_rows {
    my ($state) = @_;

    die 'final_state must contain a board' if ref($state) ne 'HASH' || !$state->{board};

    my $board = $state->{board};
    my $size  = $board->size;
    my @cells = unpack 'C*', $board->canonical_bytes;
    my @rows;
    for my $y (0 .. $size - 1) {
        push @rows, join '', @cells[$y * $size .. ($y + 1) * $size - 1];
    }

    return \@rows;
}
