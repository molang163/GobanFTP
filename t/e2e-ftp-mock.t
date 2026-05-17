use v5.34;
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

subtest 'mock FTP create publish list replay chain stays listing-first' => sub {
    MockFTP->reset;

    local %ENV = %ENV;
    $ENV{GOBANFTP_STORE} = 'ftp';
    $ENV{GOBANFTP_FTP_HOST} = 'mock.example';
    $ENV{GOBANFTP_FTP_USER} = 'alice';
    $ENV{GOBANFTP_FTP_PASSWORD} = 'secret';
    $ENV{GOBANFTP_FTP_CLASS} = 'MockFTP';
    $ENV{GOBANFTP_FTP_ROOT} = 'mock-root';

    my ($create_exit, $create_stdout, $create_stderr) = _run_cli(
        qw(create-game --id ftp-mock --size 9 --black alice --white bob),
    );
    is $create_exit, 0, 'mock FTP create-game succeeds';
    like $create_stdout, qr/^store=ftp$/m, 'FTP store is selected';
    is $create_stderr, '', 'create-game has no diagnostics';

    my ($game) = $create_stdout =~ /^game=(g1\..+)$/m;
    ok $game, 'created game descriptor is reported';

    my ($black_exit, $black_stdout, $black_stderr) = _run_cli(qw(publish-move --nonce b1), $game, 'aa');
    is $black_exit, 0, 'black move publishes through FTP CLI';
    like $black_stdout, qr/^events=1$/m, 'black move is visible from listing';
    is $black_stderr, '', 'black move has no diagnostics';

    my ($white_exit, $white_stdout, $white_stderr) = _run_cli(qw(publish-move --nonce w1), $game, 'bb');
    is $white_exit, 0, 'white move publishes through FTP CLI';
    like $white_stdout, qr/^events=2$/m, 'white move is visible from listing';
    is $white_stderr, '', 'white move has no diagnostics';

    my ($replay_exit, $replay_stdout, $replay_stderr) = _run_cli('replay', $game);
    is $replay_exit, 0, 'replay reads mock FTP listing';
    like $replay_stdout, qr/^canonical_moves=2$/m, 'replay reconstructs both moves';
    like $replay_stdout, qr/^canonical_ids=[0-9a-v]{16},[0-9a-v]{16}$/m, 'replay prints canonical ids';
    is $replay_stderr, '', 'replay has no diagnostics';

    my ($sgf_exit, $sgf_stdout, $sgf_stderr) = _run_cli('sgf', $game);
    is $sgf_exit, 0, 'plain sgf reads mock FTP listing';
    like $sgf_stdout, qr/;B\[aa\].*;W\[bb\]/s, 'plain sgf contains both moves';
    is $sgf_stderr, '', 'plain sgf has no diagnostics';

    my ($project_exit, undef, $project_stderr) = _run_cli('project', $game);
    is $project_exit, 4, 'FTP project is rejected instead of writing local files';
    like $project_stderr, qr/project writes local projection files and requires the local store/,
        'FTP project explains the local-only projection boundary';

    my @calls = MockFTP->calls;
    my @forbidden = grep { $_->[0] =~ /\A(?:get|retr|size|mdtm|dir|list)\z/ } @calls;
    is_deeply \@forbidden, [], 'FTP e2e does not read RETR SIZE MDTM or long listings';
    ok((grep { $_->[0] eq 'ls' } @calls), 'FTP e2e reads through directory listings');
    ok((grep { $_->[0] eq 'rename' } @calls), 'FTP e2e publishes through rename mode');
};

subtest 'mock FTP publish confirms a lost rename response through listings' => sub {
    MockFTP->reset;

    local %ENV = %ENV;
    $ENV{GOBANFTP_STORE} = 'ftp';
    $ENV{GOBANFTP_FTP_HOST} = 'mock.example';
    $ENV{GOBANFTP_FTP_USER} = 'alice';
    $ENV{GOBANFTP_FTP_PASSWORD} = 'secret';
    $ENV{GOBANFTP_FTP_CLASS} = 'MockFTP';
    $ENV{GOBANFTP_FTP_ROOT} = 'mock-root';

    my ($create_exit, $create_stdout, $create_stderr) = _run_cli(
        qw(create-game --id ftp-rename-confirm --size 9 --black alice --white bob),
    );
    is $create_exit, 0, 'mock FTP create-game succeeds for confirm case';
    is $create_stderr, '', 'create-game confirm case has no diagnostics';

    my ($game) = $create_stdout =~ /^game=(g1\..+)$/m;
    ok $game, 'created confirm-case game descriptor is reported';

    MockFTP->delay_next_rename_confirm(after_listings => 2);

    my ($publish_exit, $publish_stdout, $publish_stderr) = _run_cli(qw(publish-move --nonce delayed), $game, 'cc');
    is $publish_exit, 0, 'publish-move succeeds after delayed listing confirm';
    like $publish_stdout, qr/^events=1$/m, 'published move is visible after confirm';
    is $publish_stderr, '', 'delayed confirm publish has no diagnostics';

    my @calls = MockFTP->calls;
    my @forbidden = grep { $_->[0] =~ /\A(?:get|retr|size|mdtm|dir|list)\z/ } @calls;
    is_deeply \@forbidden, [], 'delayed confirm e2e uses listing-only reads';
    is scalar(grep { $_->[0] eq 'put' } @calls), 1, 'delayed confirm e2e uploads the temp file once';
    is scalar(grep { $_->[0] eq 'rename' } @calls), 1, 'delayed confirm e2e does not retry after confirm succeeds';
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

package MockFTP;

use v5.34;
use strict;
use warnings;

our $STATE;

sub new {
    my ($class) = @_;
    $STATE //= _fresh_state();
    return bless $STATE, $class;
}

sub reset {
    my ($class, %args) = @_;
    $STATE = _fresh_state(%args);
    return;
}

sub calls {
    return @{ $STATE->{calls} };
}

sub delay_next_rename_confirm {
    my ($class, %args) = @_;

    $STATE //= _fresh_state();
    $STATE->{delay_next_rename_confirm} = $args{after_listings} // 1;

    return 1;
}

sub login {
    my ($self, @args) = @_;
    $self->_record('login', $args[0] // '');
    return 1;
}

sub ls {
    my ($self, @args) = @_;

    $self->_record('ls', @args);
    $self->{message} = '';

    my $path = _canon($args[0] // '');
    $self->_apply_scheduled_creates($path);

    return () if ($self->{entries}{$path} // '') ne 'dir';

    my @children = sort
        map { _basename($_) }
        grep { $_ ne '' && _parent($_) eq $path }
        keys %{ $self->{entries} };

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
    return $remote;
}

sub rename {
    my ($self, $old, $new) = @_;

    $self->_record('rename', $old, $new);
    $old = _canon($old);
    $new = _canon($new);

    if ($self->{delay_next_rename_confirm}) {
        push @{ $self->{scheduled_creates} }, {
            path      => $new,
            parent    => _parent($new),
            remaining => delete $self->{delay_next_rename_confirm},
        };
        delete $self->{entries}{$old};
        $self->{message} = '550 rename response lost';
        return;
    }

    return if !exists $self->{entries}{$old};
    return if exists $self->{entries}{$new};
    return if ($self->{entries}{ _parent($new) } // '') ne 'dir';

    $self->{entries}{$new} = delete $self->{entries}{$old};
    return 1;
}

sub message {
    my ($self) = @_;
    return $self->{message};
}

sub get  { die 'forbidden get' }
sub retr { die 'forbidden retr' }
sub size { die 'forbidden size' }
sub mdtm { die 'forbidden mdtm' }
sub dir  { die 'forbidden dir' }
sub list { die 'forbidden list' }
sub nlst { die 'forbidden nlst' }

sub _fresh_state {
    return {
        entries           => { '' => 'dir' },
        calls             => [],
        message           => '',
        scheduled_creates => [],
    };
}

sub _record {
    my ($self, @call) = @_;
    push @{ $self->{calls} }, \@call;
    return;
}

sub _apply_scheduled_creates {
    my ($self, $listed_path) = @_;

    my @remaining;
    for my $item (@{ $self->{scheduled_creates} }) {
        if ($item->{parent} eq $listed_path) {
            $item->{remaining}--;
            if ($item->{remaining} <= 0) {
                $self->_create_file($item->{path});
                next;
            }
        }
        push @remaining, $item;
    }
    $self->{scheduled_creates} = \@remaining;

    return 1;
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
