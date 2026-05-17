use v5.34;
use strict;
use warnings;

use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

my $docs_path = "$FindBin::Bin/../docs/DIAGNOSTICS.md";
my $fixture_dir = "$FindBin::Bin/fixtures/e2e";

my @allowed_fields = qw(
    child_ids code color error event_id expected_color expected_player
    expected_ply index name names parent_id parent_kind player ply reason
    stage target_id target_kind
);

my @allowed_classes = qw(parse event-id dag rules fork);

my @stdout_fields = qw(
    board canonical_ids canonical_moves event event_id events game
    event_set_count event_set_root
    gobanftp.create-game gobanftp.play gobanftp.project
    gobanftp.publish-ack gobanftp.publish-move gobanftp.replay
    gobanftp.sgf gobanftp.verify gobanftp.watch legal_ids legal_moves
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

    my ($block) = $docs =~ /Known `code` values include:\n\n```text\n(.*?)\n```/s;
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
