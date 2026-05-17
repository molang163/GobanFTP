use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

subtest 'create-game creates a local descriptor root' => sub {
    my $root = tempdir(CLEANUP => 1);

    local %ENV = %ENV;
    delete $ENV{GOBANFTP_STORE};
    $ENV{GOBANFTP_ROOT} = $root;

    my ($exit, $stdout, $stderr) = _run_cli(qw(
        create-game --id local-flow --size 9 --black alice --white bob
    ));

    my $game = 'g1.id-local-flow.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';
    is $exit, 0, 'create-game exits success';
    like $stdout, qr/^gobanftp\.create-game=ok$/m, 'status is reported';
    like $stdout, qr/^store=local$/m, 'local store is reported';
    like $stdout, qr/^\Qgame=$game\E$/m, 'descriptor is reported';
    is $stderr, '', 'no diagnostics';

    ok -d File::Spec->catdir($root, $game), 'game root exists';
    ok -d File::Spec->catdir($root, $game, 'events'), 'events directory exists';
    ok -d File::Spec->catdir($root, $game, 'tmp'), 'tmp directory exists';
};

subtest 'create-game creates through GOBANFTP_STORE=ftp' => sub {
    my $game = 'g1.id-ftp-create.s9.r-chinese-area-v1.k7500.pb-alice.pw-bob';

    local %ENV = %ENV;
    $ENV{GOBANFTP_STORE} = 'ftp';
    $ENV{GOBANFTP_FTP_HOST} = 'mock.example';
    $ENV{GOBANFTP_FTP_USER} = 'tester';
    $ENV{GOBANFTP_FTP_PASSWORD} = 'secret';
    $ENV{GOBANFTP_FTP_ROOT} = 'games';
    $ENV{GOBANFTP_FTP_CLASS} = 'CreateGameFTP';

    my ($exit, $stdout, $stderr) = _run_cli('create-game', $game);

    is $exit, 0, 'create-game exits success over FTP';
    like $stdout, qr/^store=ftp$/m, 'FTP store is reported';
    like $stdout, qr/^\Qgame=$game\E$/m, 'FTP descriptor is reported';
    is $stderr, '', 'no FTP diagnostics';

    my $ftp = $CreateGameFTP::LAST;
    ok $ftp, 'mock FTP object was used';
    is $ftp->entry_type("games/$game"), 'dir', 'FTP game root exists';
    is $ftp->entry_type("games/$game/events"), 'dir', 'FTP events directory exists';
    is $ftp->entry_type("games/$game/tmp"), 'dir', 'FTP tmp directory exists';
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

package CreateGameFTP;

use v5.34;
use strict;
use warnings;

our $LAST;

sub new {
    my ($class) = @_;
    $LAST = bless {
        entries => { '' => 'dir' },
        message => '',
    }, $class;
    return $LAST;
}

sub login { return 1 }

sub mkdir {
    my ($self, $path) = @_;

    $path = _canon($path);
    $self->_mkdir_internal($path);
    return $path eq '' ? '.' : $path;
}

sub ls {
    my ($self, $path) = @_;

    $path = _canon($path);
    return () if ($self->{entries}{$path} // '') ne 'dir';

    return sort
        map { $path eq '' ? $_ : "$path/$_" }
        map { _basename($_) }
        grep { $_ ne '' && _parent($_) eq $path }
        keys %{ $self->{entries} };
}

sub message {
    my ($self) = @_;
    return $self->{message};
}

sub entry_type {
    my ($self, $path) = @_;
    return $self->{entries}{ _canon($path) };
}

sub _mkdir_internal {
    my ($self, $path) = @_;

    my $current = '';
    for my $component (split m{/+}, $path) {
        next if $component eq '';
        $current = $current eq '' ? $component : "$current/$component";
        $self->{entries}{$current} = 'dir';
    }

    return 1;
}

sub _canon {
    my ($path) = @_;

    $path //= '';
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
