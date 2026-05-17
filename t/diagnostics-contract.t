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
    expected_ply name names parent_id parent_kind player ply reason target_id
    target_kind
);

my @stdout_fields = qw(
    board canonical_ids canonical_moves event event_id events game
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
    for my $line (grep { /^diagnostic / } split /\n/, $stderr) {
        my @pairs = split /\s+/, $line;
        shift @pairs;

        my %fields;
        for my $pair (@pairs) {
            my ($key) = split /=/, $pair, 2;
            $fields{$key} = 1;
            ok $allowed{$key}, "diagnostic field is documented: $key";
        }
        ok $fields{code}, 'diagnostic line includes code';
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
