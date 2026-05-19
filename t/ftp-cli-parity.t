use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::Auth::HMACKey qw(generate_hmac_key_record write_hmac_key_file);
use GobanFTP::Auth::PublishToken qw(sign_publish_token);
use GobanFTP::CLI;
use GobanFTP::MovePublisher qw(build_move_name);

my $FTP_ROOT = 'ftp-cli-root';
my $GAME = 'g1.id-ftp-cli-parity.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';

subtest 'FTP CLI parity uses listings for sgf play and watch' => sub {
    FtpCliParityFTP->reset;

    local %ENV = %ENV;
    _ftp_env();

    my ($create_exit, $create_stdout, $create_stderr) = _run_cli('create-game', $GAME);
    is $create_exit, 0, 'create-game setup succeeds';
    like $create_stdout, qr/^store=ftp$/m, 'setup selects FTP store';
    is $create_stderr, '', 'setup has no diagnostics';

    my @play_once_calls = _assert_command_uses_ftp_listing(
        'play --once',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('play', '--once', $GAME);
            is $exit, 0, 'play --once exits success';
            like $stdout, qr/^gobanftp\.play=ok$/m, 'play --once reports ok';
            like $stdout, qr/^events=0$/m, 'play --once sees the empty FTP event listing';
            like $stdout, qr/^event_set_count=0$/m, 'play --once reports empty FTP event-set count';
            like $stdout, qr/^event_set_root=e0534a852f47ec22884f56470d9dc5c408eceafb2a49b6c150b2d30553adf632$/m,
                'play --once reports empty FTP event-set root';
            like $stdout, qr/^worldline\.status=main$/m, 'play --once renders a main worldline';
            is $stderr, '', 'play --once has no diagnostics';
        },
    );
    _assert_no_ftp_writes('play --once does not write through FTP', \@play_once_calls);

    my ($left_event, $left_id);
    my @play_move_calls = _assert_command_uses_ftp_listing(
        'play --move',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('play', '--move', 'aa', '--nonce', 'p1', $GAME);
            is $exit, 0, 'play --move exits success';
            like $stdout, qr/^gobanftp\.play=ok$/m, 'play --move reports ok';
            like $stdout, qr/^events=1$/m, 'play --move reloads the FTP listing after publish';
            like $stdout, qr/^event_set_count=1$/m, 'play --move reports one accepted FTP event';
            like $stdout, qr/^event_set_root=a121f302994452df5b810c38c1223f7f57203cbac7147d5e84cdb7c73a656afa$/m,
                'play --move reports FTP event-set root after publish';
            like $stdout, qr/^canonical_moves=1$/m, 'play --move renders one canonical move';
            like $stdout, qr/^turn_player=bob$/m, 'play --move advances the turn';
            is $stderr, '', 'play --move has no diagnostics';

            ($left_event) = $stdout =~ /^event=(m1\..+)$/m;
            ($left_id) = $stdout =~ /^event_id=([0-9a-v]{16})$/m;
            like $left_event // '', qr/\Am1\.p000001\.b\.play-aa\.pa-genesis\.by-alice\.n-p1\.h-[0-9a-v]{16}\z/,
                'play --move reports the published FTP event basename';
            like $left_id // '', qr/\A[0-9a-v]{16}\z/, 'play --move reports the published event id';
        },
    );
    _assert_rename_publish('play --move publishes through FTP rename mode', \@play_move_calls);

    ok FtpCliParityFTP->has_event($FTP_ROOT, $GAME, $left_event), 'play --move published into FTP events/';

    my @watch_calls = _assert_command_uses_ftp_listing(
        'watch --once --interval 0',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('watch', '--once', '--interval', '0', $GAME);
            is $exit, 0, 'watch --once --interval 0 exits success';
            like $stdout, qr/^gobanftp\.watch=ok$/m, 'watch reports ok';
            like $stdout, qr/^snapshot=1$/m, 'watch reports the bounded snapshot';
            like $stdout, qr/^events=1$/m, 'watch sees the FTP event listing';
            like $stdout, qr/^event_set_root=a121f302994452df5b810c38c1223f7f57203cbac7147d5e84cdb7c73a656afa$/m,
                'watch reports the same FTP event-set root';
            like $stdout, qr/^worldline\.status=main$/m, 'watch renders the main worldline';
            is $stderr, '', 'watch has no diagnostics';
        },
    );
    _assert_no_ftp_writes('watch --once does not write through FTP', \@watch_calls);

    my @sgf_calls = _assert_command_uses_ftp_listing(
        'sgf',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('sgf', $GAME);
            is $exit, 0, 'sgf exits success';
            like $stdout, qr/\A\(;/, 'sgf prints an SGF collection';
            like $stdout, qr/;B\[aa\]/, 'sgf renders the FTP-listed move';
            unlike $stdout, qr/^event_set_root=/m, 'sgf stdout is not polluted by event-set root';
            is $stderr, '', 'sgf has no diagnostics';
        },
    );
    _assert_no_ftp_writes('sgf does not write through FTP', \@sgf_calls);

    ok !FtpCliParityFTP->has_path("$FTP_ROOT/$GAME/projections"),
        'play/watch/sgf parity does not create FTP projections';
    _assert_no_forbidden_ftp_reads('read-only parity plus play --move stays listing-first');
};

subtest 'FTP publish-ack fork exit and play --ack recovery match local CLI behavior' => sub {
    FtpCliParityFTP->reset;

    local %ENV = %ENV;
    _ftp_env();

    my ($create_exit, $create_stdout, $create_stderr) = _run_cli('create-game', $GAME);
    is $create_exit, 0, 'ack setup create-game succeeds';
    like $create_stdout, qr/^store=ftp$/m, 'ack setup selects FTP store';
    is $create_stderr, '', 'ack setup has no diagnostics';

    my ($left_id);
    my @first_move_calls = _assert_command_uses_ftp_listing(
        'play --move before fork',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('play', '--move', 'aa', '--nonce', 'left', $GAME);
            is $exit, 0, 'initial play --move exits success';
            like $stdout, qr/^gobanftp\.play=ok$/m, 'initial play --move reports ok';
            like $stdout, qr/^event_set_root=457bf74ec0a90ba0ad5d7c4a0006fac00f812c55320b7641b5bb89ab99a8b930$/m,
                'initial play --move reports the FTP event-set root';
            is $stderr, '', 'initial play --move has no diagnostics';
            ($left_id) = $stdout =~ /^event_id=([0-9a-v]{16})$/m;
            like $left_id // '', qr/\A[0-9a-v]{16}\z/, 'initial play --move reports an event id';
        },
    );
    _assert_rename_publish('initial play --move publishes through FTP rename mode', \@first_move_calls);

    my ($right_event, $right_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-bb',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'right',
    );
    FtpCliParityFTP->create_file("$FTP_ROOT/$GAME/events/$right_event");

    my @publish_ack_calls = _assert_command_uses_ftp_listing(
        'publish-ack',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('publish-ack', '--nonce', 'ackleft', $GAME, $left_id);
            is $exit, 3, 'publish-ack preserves the expected conservative fork exit';
            like $stdout, qr/^gobanftp\.publish-ack=fork$/m, 'publish-ack reports fork status';
            like $stdout, qr/^events=3$/m, 'publish-ack reloads both fork moves and the ack';
            like $stdout, qr/^event_set_count=3$/m, 'publish-ack reports three accepted FTP events';
            like $stdout, qr/^event_set_root=2d9400bd875b5288537dc0c034a040374bd4584b61228960caa74c43b6fff6a9$/m,
                'publish-ack reports the FTP event-set root';
            like $stdout, qr/^event=a1\.t-\Q$left_id\E\.by-bob\.n-ackleft\.h-[0-9a-v]{16}$/m,
                'publish-ack reports the FTP ack event basename';
            like $stderr, qr/diagnostic .*code=fork/, 'publish-ack emits the conservative fork diagnostic';
        },
    );
    _assert_rename_publish('publish-ack publishes through FTP rename mode', \@publish_ack_calls);

    my @play_ack_calls = _assert_command_uses_ftp_listing(
        'play --ack',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli('play', '--ack', $left_id, '--nonce', 'playack', $GAME);
            is $exit, 0, 'play --ack exits success after ack-assisted recovery';
            like $stdout, qr/^event=a1\.t-\Q$left_id\E\.by-bob\.n-playack\.h-[0-9a-v]{16}$/m,
                'play --ack reports the FTP ack event basename';
            like $stdout, qr/^gobanftp\.play=ok$/m, 'play --ack reports ok';
            like $stdout, qr/^events=4$/m, 'play --ack reloads the FTP listing after publishing';
            like $stdout, qr/^event_set_count=4$/m, 'play --ack reports four accepted FTP events';
            like $stdout, qr/^event_set_root=dff317e62d82989489a16be3a420d9dad431629ac7d24f0d72bdbde5514c74d7$/m,
                'play --ack reports the FTP event-set root';
            like $stdout, qr/^canonical_moves=1$/m, 'play --ack chooses one canonical fork child';
            like $stdout, qr/^worldline\.status=main$/m, 'play --ack renders a recovered worldline';
            like $stdout, qr/^worldline\.canonical_ids=\Q$left_id\E$/m, 'play --ack chooses the acked child';
            unlike $stdout, qr/^worldline\.canonical_ids=\Q$right_id\E$/m, 'play --ack does not choose the unacked child';
            is $stderr, '', 'play --ack has no diagnostics after recovery';
        },
    );
    _assert_rename_publish('play --ack publishes through FTP rename mode', \@play_ack_calls);

    is scalar(grep { /\Aa1\./ } FtpCliParityFTP->event_names($FTP_ROOT, $GAME)), 2,
        'publish-ack and play --ack both publish ack events through FTP';

    ok !FtpCliParityFTP->has_path("$FTP_ROOT/$GAME/projections"),
        'ack parity commands do not create FTP projections';
    _assert_no_forbidden_ftp_reads('ack parity stays listing-first');
};

subtest 'FTP denied publish preflight does not upload or rename' => sub {
    FtpCliParityFTP->reset;

    local %ENV = %ENV;
    _ftp_env();

    my $dir = tempdir(CLEANUP => 1);
    my ($key_path, $key) = _write_key($dir);
    my ($event, $event_id) = build_move_name(
        game_descriptor => $GAME,
        ply             => 1,
        color           => 'b',
        action          => 'play-aa',
        parent_id       => 'genesis',
        player          => 'alice',
        nonce           => 'authdeny',
    );
    my $token_path = _write_token($dir, $key, $event, $event_id);

    my ($create_exit, undef, $create_stderr) = _run_cli('create-game', $GAME);
    is $create_exit, 0, 'denied setup create-game succeeds';
    is $create_stderr, '', 'denied setup has no diagnostics';

    my @calls = _assert_command_uses_ftp_listing(
        'publish-move denied preflight',
        sub {
            my ($exit, $stdout, $stderr) = _run_cli(
                'publish-move',
                '--nonce', 'authdeny',
                '--publish-auth-token', $token_path,
                '--publish-auth-trusted-hmac-key-file', $key_path,
                '--publish-auth-trusted-hmac-status', "$key->{key_id}=rotated",
                $GAME,
                'aa',
            );
            is $exit, 2, 'denied preflight exits validation';
            like $stdout, qr/^gobanftp[.]publish-move=failed$/m,
                'denied preflight reports failed';
            like $stdout, qr/^publish_auth[.]status=denied$/m,
                'denied preflight reports auth denial';
            like $stderr, qr/diagnostic .*code=untrusted_signature.*reason=key[.]rotated/,
                'denied preflight reports lifecycle reason';
            unlike $stdout . $stderr, qr/\Q$key->{secret_hex}\E|secret_hex|secret/,
                'denied preflight does not leak HMAC secret';
        },
    );

    _assert_no_ftp_writes('denied preflight does not upload or rename', \@calls);
    ok !FtpCliParityFTP->has_event($FTP_ROOT, $GAME, $event),
        'denied preflight creates no FTP event';
};

done_testing;

sub _ftp_env {
    $ENV{GOBANFTP_STORE} = 'ftp';
    $ENV{GOBANFTP_FTP_HOST} = 'mock.example';
    $ENV{GOBANFTP_FTP_USER} = 'tester';
    $ENV{GOBANFTP_FTP_PASSWORD} = 'secret';
    $ENV{GOBANFTP_FTP_CLASS} = 'FtpCliParityFTP';
    $ENV{GOBANFTP_FTP_ROOT} = $FTP_ROOT;
    return;
}

sub _assert_command_uses_ftp_listing {
    my ($label, $code) = @_;

    my $before = FtpCliParityFTP->call_count;
    $code->();
    my @calls = FtpCliParityFTP->calls_since($before);

    ok((grep { $_->[0] eq 'login' } @calls), "$label constructs an FTP store");
    ok((grep { $_->[0] eq 'ls' && ($_->[1] // '') eq "$FTP_ROOT/$GAME/events" } @calls),
        "$label reads the FTP events listing");
    _assert_no_forbidden_ftp_reads("$label does not use non-listing FTP reads", \@calls);

    return @calls;
}

sub _assert_no_forbidden_ftp_reads {
    my ($label, $calls) = @_;

    my @calls = defined $calls ? @$calls : FtpCliParityFTP->calls;
    my @forbidden = grep { $_->[0] =~ /\A(?:get|retr|size|mdtm|dir|list|nlst)\z/ } @calls;
    is_deeply \@forbidden, [], $label;
}

sub _assert_no_ftp_writes {
    my ($label, $calls) = @_;

    my @writes = grep { $_->[0] =~ /\A(?:binary|put|rename)\z/ } @$calls;
    is_deeply \@writes, [], $label;
}

sub _assert_rename_publish {
    my ($label, $calls) = @_;

    ok((grep { $_->[0] eq 'binary' } @$calls), "$label sets binary mode");
    ok((grep { $_->[0] eq 'put' } @$calls), "$label uploads a temporary event");
    ok((grep { $_->[0] eq 'rename' } @$calls), "$label renames the temporary event into events/");
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

sub _write_key {
    my ($dir) = @_;

    my $key = generate_hmac_key_record(secret => ('f' x 32));
    my $path = File::Spec->catfile($dir, 'player.hmac-key');
    write_hmac_key_file($path, $key);

    return ($path, $key);
}

sub _write_token {
    my ($dir, $key, $event, $event_id) = @_;

    my $token = sign_publish_token(
        profile         => 'signed-hmac-goftp1',
        game_descriptor => $GAME,
        event_basename  => $event,
        event_id        => $event_id,
        key_id          => $key->{key_id},
        key             => $key->{secret},
    );
    my $path = File::Spec->catfile($dir, 'publish-token.jsonl');
    open my $fh, '>:encoding(UTF-8)', $path or die "write $path: $!";
    print {$fh} JSON::PP->new->canonical(1)->encode($token), "\n";
    close $fh or die "close $path: $!";

    return $path;
}

package FtpCliParityFTP;

use v5.34;
use strict;
use warnings;

our $STATE;

sub new {
    my ($class, $host, %args) = @_;

    $STATE //= _fresh_state();
    my $self = bless $STATE, $class;
    $self->_record('new', $host // '');

    return $self;
}

sub reset {
    $STATE = _fresh_state();
    return;
}

sub calls {
    $STATE //= _fresh_state();
    return @{ $STATE->{calls} };
}

sub call_count {
    $STATE //= _fresh_state();
    return scalar @{ $STATE->{calls} };
}

sub calls_since {
    my ($class, $index) = @_;

    $STATE //= _fresh_state();
    my @calls = @{ $STATE->{calls} };
    return () if $index > $#calls;
    return @calls[$index .. $#calls];
}

sub create_file {
    my ($class, $path) = @_;

    $STATE //= _fresh_state();
    return bless($STATE, $class)->_create_file($path);
}

sub has_event {
    my ($class, $root, $game, $event) = @_;

    return 0 if !defined $event || $event eq '';
    $STATE //= _fresh_state();
    return exists $STATE->{entries}{ _canon("$root/$game/events/$event") } ? 1 : 0;
}

sub has_path {
    my ($class, $path) = @_;

    $STATE //= _fresh_state();
    return exists $STATE->{entries}{ _canon($path) } ? 1 : 0;
}

sub event_names {
    my ($class, $root, $game) = @_;

    $STATE //= _fresh_state();
    my $parent = _canon("$root/$game/events");
    return sort
        map { _basename($_) }
        grep { $_ ne '' && _parent($_) eq $parent }
        keys %{ $STATE->{entries} };
}

sub login {
    my ($self, @args) = @_;

    $self->_record('login', $args[0] // '');
    return 1;
}

sub ls {
    my ($self, @args) = @_;

    $self->_record('ls', @args);
    my $path = _canon($args[0] // '');

    if (($self->{entries}{$path} // '') ne 'dir') {
        $self->{message} = '550 no such directory';
        return;
    }

    my @children = sort
        map { _basename($_) }
        grep { $_ ne '' && _parent($_) eq $path }
        keys %{ $self->{entries} };

    $self->{message} = '';
    return map { $path eq '' ? $_ : "$path/$_" } @children;
}

sub mkdir {
    my ($self, $path, $recursive) = @_;

    $self->_record('mkdir', defined($recursive) ? ($path, $recursive) : ($path));
    $path = _canon($path);
    return '.' if $path eq '';

    my $parent = _parent($path);
    return if !$recursive && ($self->{entries}{$parent} // '') ne 'dir';

    $self->_mkdir_internal($path);
    $self->{message} = '';
    return $path;
}

sub binary {
    my ($self) = @_;

    $self->_record('binary');
    return 1;
}

sub put {
    my ($self, $local, $remote) = @_;

    $self->_record('put', $local, $remote);
    $remote = _canon($remote);
    return if ($self->{entries}{ _parent($remote) } // '') ne 'dir';

    $self->{entries}{$remote} = 'file';
    $self->{message} = '';
    return $remote;
}

sub rename {
    my ($self, $old, $new) = @_;

    $self->_record('rename', $old, $new);
    $old = _canon($old);
    $new = _canon($new);

    if (!exists $self->{entries}{$old}) {
        $self->{message} = '550 rename source missing';
        return;
    }
    if (exists $self->{entries}{$new}) {
        $self->{message} = '550 rename target exists';
        return;
    }
    if (($self->{entries}{ _parent($new) } // '') ne 'dir') {
        $self->{message} = '550 rename target parent missing';
        return;
    }

    $self->{entries}{$new} = delete $self->{entries}{$old};
    $self->{message} = '';
    return 1;
}

sub message {
    my ($self) = @_;
    return $self->{message};
}

sub get  { shift->_forbidden('get',  @_) }
sub retr { shift->_forbidden('retr', @_) }
sub size { shift->_forbidden('size', @_) }
sub mdtm { shift->_forbidden('mdtm', @_) }
sub dir  { shift->_forbidden('dir',  @_) }
sub list { shift->_forbidden('list', @_) }
sub nlst { shift->_forbidden('nlst', @_) }

sub _forbidden {
    my ($self, $method, @args) = @_;

    $self->_record($method, @args);
    die "forbidden FTP read: $method";
}

sub _fresh_state {
    return {
        entries => { '' => 'dir' },
        calls   => [],
        message => '',
    };
}

sub _record {
    my ($self, @call) = @_;
    push @{ $self->{calls} }, \@call;
    return;
}

sub _create_file {
    my ($self, $path) = @_;

    $path = _canon($path);
    my $parent = _parent($path);
    $self->_mkdir_internal($parent) if !exists $self->{entries}{$parent};
    $self->{entries}{$path} = 'file';
    return 1;
}

sub _mkdir_internal {
    my ($self, $path) = @_;

    $path = _canon($path);
    return if $path eq '';

    my $current = '';
    for my $component (split m{/+}, $path) {
        $current = $current eq '' ? $component : "$current/$component";
        $self->{entries}{$current} = 'dir';
    }

    return;
}

sub _canon {
    my ($path) = @_;

    $path //= '';
    $path =~ s{\A\./+}{};
    $path =~ s{\A/+}{};
    $path =~ s{/+\z}{};

    return $path;
}

sub _parent {
    my ($path) = @_;

    $path = _canon($path);
    return '' if $path !~ m{/};

    $path =~ s{/[^/]+\z}{};
    return $path;
}

sub _basename {
    my ($path) = @_;

    $path = _canon($path);
    $path =~ s{\A.*/}{};
    return $path;
}
