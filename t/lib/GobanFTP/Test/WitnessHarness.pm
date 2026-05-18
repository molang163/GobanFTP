package GobanFTP::Test::WitnessHarness;

use v5.34;
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use Exporter qw(import);

use GobanFTP::Auth::HMAC qw(verify_event_signature);
use GobanFTP::EventSetRoot qw(event_set_root_result);
use GobanFTP::Listing qw(normalize_listing);
use GobanFTP::Projection qw(render_projection);
use GobanFTP::Replay qw(replay);

our @EXPORT_OK = qw(witness_for_listing);

my %SCHEMA_CACHE;

sub witness_for_listing {
    my (%args) = @_;

    my $profile_id = _required($args{profile_id},      'profile_id');
    my $game       = _required($args{game_descriptor}, 'game_descriptor');
    my $raw_names  = _array_ref($args{raw_names},      'raw_names');
    my $schema     = _schema($args{diagnostics_schema_path});

    my @profile_names = _profile_listing_names($profile_id, $game, $raw_names);
    my @events        = normalize_listing(@profile_names);
    my @replay_events = @events;
    my $event_set = event_set_root_result(
        game_descriptor => $game,
        names           => \@profile_names,
    );

    if (_is_signed_hmac_profile($profile_id)) {
        $event_set = _signed_hmac_event_set_result(
            profile_id       => $profile_id,
            game_descriptor  => $game,
            unsigned_result  => $event_set,
            hmac_attestations => _array_ref(
                $args{hmac_attestations} // [],
                'hmac_attestations',
            ),
            trusted_hmac_keys => _hash_ref(
                $args{trusted_hmac_keys} // {},
                'trusted_hmac_keys',
            ),
        );
        @replay_events = @{ $event_set->{accepted_events} };
    }

    my $result = replay(
        game_descriptor => $game,
        events          => \@replay_events,
    );
    my @diagnostics = $result->diagnostics;

    my $rendered = render_projection(
        game_descriptor => $game,
        events          => \@replay_events,
        replay_result   => $result,
    );

    my @canonical_ids = $result->canonical_ids;
    my @legal_ids     = $result->legal_ids;

    return {
        profile_id             => $profile_id,
        game_descriptor        => $game,
        raw_count              => scalar(@$raw_names),
        normalized_count       => scalar(@events),
        normalized_events      => [@events],
        accepted_count         => $event_set->{event_count},
        accepted_events        => [@{ $event_set->{accepted_events} }],
        rejected_count         => scalar(@{ $event_set->{diagnostics} }),
        rejected_codes         => [_diagnostic_codes($event_set->{diagnostics})],
        rejected_classes       => [_diagnostic_classes($event_set->{diagnostics}, $schema)],
        event_set_root         => $event_set->{event_set_root},
        replay_status          => _replay_status(\@diagnostics),
        canonical_tip          => @canonical_ids ? $canonical_ids[-1] : 'genesis',
        canonical_ids          => \@canonical_ids,
        legal_ids              => \@legal_ids,
        board_hash             => sha256_hex($rendered->{board} // ''),
        sgf_hash               => sha256_hex($rendered->{sgf_main} // $rendered->{sgf} // ''),
        variations_sgf_hash    => sha256_hex($rendered->{sgf_variations} // $rendered->{variations_sgf} // ''),
        diagnostic_codes       => [_diagnostic_codes(\@diagnostics)],
        diagnostic_classes     => [_diagnostic_classes(\@diagnostics, $schema)],
        diagnostic_count       => scalar(@diagnostics),
    };
}

sub _profile_listing_names {
    my ($profile_id, $game, $raw_names) = @_;

    return _git_tree_listing_names($game, $raw_names) if $profile_id eq 'git-tree-goftp1';
    return _dns_record_listing_names($raw_names) if $profile_id eq 'dns-record-goftp1';
    return _webdav_listing_names($raw_names) if $profile_id eq 'webdav-goftp1';
    return @$raw_names;
}

sub _is_signed_hmac_profile {
    my ($profile_id) = @_;
    return $profile_id eq 'signed-hmac-goftp1';
}

sub _signed_hmac_event_set_result {
    my (%args) = @_;

    my $profile_id      = _required($args{profile_id},      'profile_id');
    my $game_descriptor = _required($args{game_descriptor}, 'game_descriptor');
    my $unsigned_result = $args{unsigned_result};
    die 'unsigned_result must be a hash reference' if ref($unsigned_result) ne 'HASH';

    my $attestations = _hmac_attestation_index($args{hmac_attestations});
    my $trusted_keys = $args{trusted_hmac_keys};

    my (@signed_events, @signature_diagnostics);
    for my $event (@{ $unsigned_result->{accepted_events} // [] }) {
        my ($ok, $diagnostic) = _verify_signed_hmac_event(
            profile_id       => $profile_id,
            game_descriptor  => $game_descriptor,
            event            => $event,
            attestation      => $attestations->{$event},
            trusted_hmac_keys => $trusted_keys,
        );

        if ($ok) {
            push @signed_events, $event;
            next;
        }

        push @signature_diagnostics, $diagnostic;
    }

    my $signed_result = event_set_root_result(
        game_descriptor => $game_descriptor,
        names           => \@signed_events,
    );

    return {
        %$signed_result,
        diagnostics => [
            @{ $unsigned_result->{diagnostics} // [] },
            @signature_diagnostics,
        ],
    };
}

sub _verify_signed_hmac_event {
    my (%args) = @_;

    my $profile_id  = _required($args{profile_id}, 'profile_id');
    my $event       = _required($args{event},      'event');
    my @attestations = _attestation_records($args{attestation});
    if (!@attestations) {
        return (0, {
            code       => 'missing_signature',
            profile_id => $profile_id,
            name       => $event,
            event_id   => _event_id_from_basename($event),
        });
    }

    my @diagnostics;
    for my $attestation (@attestations) {
        my $diagnostic = _signed_hmac_attestation_diagnostic(
            %args,
            profile_id  => $profile_id,
            event       => $event,
            attestation => $attestation,
        );

        return (1, undef) if !defined $diagnostic;
        push @diagnostics, $diagnostic;
    }

    return (0, _preferred_signature_diagnostic(@diagnostics));
}

sub _signed_hmac_attestation_diagnostic {
    my (%args) = @_;

    my $profile_id  = _required($args{profile_id}, 'profile_id');
    my $event       = _required($args{event},      'event');
    my $attestation = $args{attestation};
    die 'attestation must be a hash reference' if ref($attestation) ne 'HASH';

    my $event_id = _event_id_from_basename($event);
    my $key_id   = $attestation->{key_id} // '';
    my $keys     = $args{trusted_hmac_keys};

    if ($key_id eq '' || !exists $keys->{$key_id}) {
        return {
            code       => 'untrusted_signature',
            profile_id => $profile_id,
            name       => $event,
            event_id   => $event_id,
            key_id     => $key_id,
            reason     => $key_id eq '' ? 'key_id.missing' : 'key.untrusted',
        };
    }

    my $verification = _verify_hmac_attestation(
        profile_id       => $profile_id,
        game_descriptor  => _required($args{game_descriptor}, 'game_descriptor'),
        event            => $event,
        event_id         => $event_id,
        key_id           => $key_id,
        key              => $keys->{$key_id},
        attestation      => $attestation,
    );

    return undef if $verification->{ok};

    my $code = _signature_diagnostic_code($verification->{error});
    my %diagnostic = (
        code       => $code,
        profile_id => $profile_id,
        reason     => $verification->{error} // 'signature.invalid',
    );

    if ($code eq 'malformed_signature') {
        $diagnostic{signature_id} = $attestation->{signature_id} // $event_id;
    }
    else {
        $diagnostic{name}     = $event;
        $diagnostic{event_id} = $event_id;
        $diagnostic{key_id}   = $key_id;
    }

    return \%diagnostic;
}

sub _attestation_records {
    my ($attestation) = @_;
    return () if !defined $attestation;
    return @$attestation if ref($attestation) eq 'ARRAY';
    return ($attestation);
}

sub _preferred_signature_diagnostic {
    my (@diagnostics) = @_;

    my %priority = (
        wrong_signature     => 0,
        malformed_signature => 1,
        untrusted_signature => 2,
        missing_signature   => 3,
    );

    return (sort {
        ($priority{ $a->{code} // '' } // 99) <=> ($priority{ $b->{code} // '' } // 99)
            || (($a->{key_id} // '') cmp ($b->{key_id} // ''))
            || (($a->{signature_id} // '') cmp ($b->{signature_id} // ''))
            || (($a->{reason} // '') cmp ($b->{reason} // ''))
    } @diagnostics)[0];
}

sub _verify_hmac_attestation {
    my (%args) = @_;

    my $record = _normalized_hmac_attestation_record(%args);

    return verify_event_signature(
        version          => _signed_hmac_event_version(),
        profile          => _signed_hmac_attestation_profile($args{profile_id}),
        game_descriptor  => $args{game_descriptor},
        event_basename   => $args{event},
        event_id         => $args{event_id},
        key_id           => $args{key_id},
        key              => $args{key},
        signature_record => $record,
    );
}

sub _normalized_hmac_attestation_record {
    my (%args) = @_;

    my %record = %{ $args{attestation} };
    $record{signature} //= $record{signature_hex} // $record{hmac_sha256};
    $record{event_basename} //= $record{event};

    return \%record;
}

sub _signed_hmac_event_version {
    return 'GOFTP-HMAC-EVENT/1';
}

sub _signed_hmac_attestation_profile {
    my ($profile_id) = @_;
    return $profile_id;
}

sub _signature_diagnostic_code {
    my ($error) = @_;
    return 'missing_signature'
        if !defined($error) || $error eq 'signature.missing';
    return 'malformed_signature'
        if $error eq 'signature.format' || $error eq 'signature.record';
    return 'wrong_signature';
}

sub _hmac_attestation_index {
    my ($records) = @_;

    my %by_event;
    for my $index (0 .. $#$records) {
        my $record = $records->[$index];
        die "hmac_attestations[$index] must be a hash reference"
            if ref($record) ne 'HASH';

        my $event = _required(
            $record->{event_basename} // $record->{event},
            "hmac_attestations[$index].event_basename",
        );
        push @{ $by_event{$event} }, $record;
    }

    return \%by_event;
}

sub _event_id_from_basename {
    my ($event) = @_;
    return undef if !defined $event;
    return $1 if $event =~ /[.]h-([a-z0-9]+)\z/;
    return undef;
}

sub _git_tree_listing_names {
    my ($game, $raw_names) = @_;

    my @names;
    for my $raw (@$raw_names) {
        my $name = _git_tree_visible_name($raw, $game);
        push @names, $name if defined($name) && $name ne '';
    }

    return @names;
}

sub _git_tree_visible_name {
    my ($line, $game) = @_;

    return undef if !defined($line) || $line eq '';

    my $path;
    if ($line =~ /\A[0-7]{6}\s+\S+\s+[0-9a-fA-F]+\t(.+)\z/) {
        $path = $1;    # git ls-tree default: mode type object<TAB>path
    }
    elsif ($line =~ /\A[0-7]{6}\s+[0-9a-fA-F]+\s+\S+\s+(.+)\z/) {
        $path = $1;    # mode object type path fixtures
    }
    elsif ($line =~ /\Amode=[0-7]{6}\s+object=[0-9a-fA-F]+\s+type=\S+\s+path=(.+)\z/) {
        $path = $1;
    }
    elsif ($line =~ m{\A(?:\./)?(?:events|sidecar|projections?|tmp)(?:/|\z)}) {
        $path = $line; # checkout-style relative path
    }

    return undef if !defined($path) || $path eq '';

    $path =~ s{\A(?:\./)+}{};
    $path =~ s{\A\Q$game\E/}{};

    return $path;
}

sub _dns_record_listing_names {
    my ($raw_names) = @_;

    my @names;
    for my $line (@$raw_names) {
        my $event = _dns_record_event_value($line);
        push @names, $event if defined $event;
    }

    return @names;
}

sub _dns_record_event_value {
    my ($line) = @_;

    return undef if !defined $line || $line eq '';

    my $presentation = lc $line;
    return undef if $presentation !~ /(?:\A|\s)type=txt(?:\s|\z)/;

    my ($event) = $presentation =~ /(?:\A|\s)event="?([a-z0-9._-]+)"?(?:\s|\z)/;
    return undef if !defined $event;

    return $event;
}

sub _webdav_listing_names {
    my ($raw_names) = @_;

    my @names;
    for my $line (@$raw_names) {
        my $href = _webdav_href($line);
        next if !defined $href;

        my $name = _webdav_listing_name_from_href($href);
        push @names, $name if defined $name;
    }

    return @names;
}

sub _webdav_href {
    my ($line) = @_;

    return undef if !defined $line || $line eq '';
    return $1 if $line =~ m{<href>([^<]*)</href>};
    return $1 if $line =~ /\bhref="([^"]*)"/;
    return $1 if $line =~ /\bhref='([^']*)'/;
    return $1 if $line =~ /\bhref=([^\s;]+)/;
    return undef;
}

sub _webdav_listing_name_from_href {
    my ($href) = @_;

    $href =~ s{\Ahttps?://[^/]*}{};
    $href =~ s/[?#].*\z//;

    my @segments = grep { $_ ne '' } split m{/+}, $href;
    for my $i (0 .. $#segments) {
        next if $segments[$i] ne 'events';
        next if $i != $#segments - 1;

        my $basename = _percent_decode_once($segments[$i + 1]);
        next if !defined $basename;
        next if $basename !~ /\A[a-z0-9._-]+\z/;

        return "events/$basename";
    }

    return undef;
}

sub _percent_decode_once {
    my ($value) = @_;

    return undef if !defined $value;
    return undef if $value =~ /%(?![0-9A-Fa-f]{2})/;

    $value =~ s/%([0-9A-Fa-f]{2})/chr hex $1/eg;
    return $value;
}

sub _replay_status {
    my ($diagnostics) = @_;

    return 'ok' if !@$diagnostics;
    return 'validation' if grep { ($_->{code} // '') ne 'fork' } @$diagnostics;
    return 'fork';
}

sub _diagnostic_codes {
    my ($diagnostics) = @_;
    return _unique_sorted(map { $_->{code} // '' } @$diagnostics);
}

sub _diagnostic_classes {
    my ($diagnostics, $schema) = @_;
    return _unique_sorted(map { _diagnostic_class($_, $schema) // 'unknown' } @$diagnostics);
}

sub _diagnostic_class {
    my ($diagnostic, $schema) = @_;

    my $code = $diagnostic->{code} // '';
    return 'signature'
        if $code =~ /\Asignature(?:_|\z)/
            || $code =~ /\A(?:missing|wrong|untrusted|malformed)_signature\z/;

    my @candidates = grep { $_->{code} eq $code } @$schema;
    for my $row (@candidates) {
        return $row->{class} if _selector_matches($diagnostic, $row->{selector});
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

sub _schema {
    my ($path) = @_;

    die 'diagnostics_schema_path is required' if !defined($path) || $path eq '';
    return $SCHEMA_CACHE{$path} if exists $SCHEMA_CACHE{$path};

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $docs = do { local $/; <$fh> };
    close $fh or die "close $path: $!";

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
        };
    }

    return $SCHEMA_CACHE{$path} = \@schema;
}

sub _unique_sorted {
    my (%seen, @values);
    for my $value (@_) {
        next if !defined($value) || $value eq '';
        next if $seen{$value}++;
        push @values, $value;
    }
    return sort @values;
}

sub _required {
    my ($value, $name) = @_;
    die "$name is required" if !defined($value) || $value eq '';
    return $value;
}

sub _array_ref {
    my ($value, $name) = @_;
    die "$name must be an array reference" if ref($value) ne 'ARRAY';
    return $value;
}

sub _hash_ref {
    my ($value, $name) = @_;
    die "$name must be a hash reference" if ref($value) ne 'HASH';
    return $value;
}

1;
