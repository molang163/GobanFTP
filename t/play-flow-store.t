use v5.34;
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;

my $fixture_dir = "$FindBin::Bin/fixtures/play-flow";
my $game = _read_single(File::Spec->catfile($fixture_dir, 'game.name'));
my @moves = _read_moves(File::Spec->catfile($fixture_dir, 'moves.tsv'));

subtest 'local descriptor flow alternates players through the store' => sub {
    my $root = tempdir(CLEANUP => 1);

    local %ENV = %ENV;
    delete $ENV{GOBANFTP_STORE};
    $ENV{GOBANFTP_ROOT} = $root;

    my ($create_exit, $create_stdout, $create_stderr) = _run_cli('create-game', $game);
    is $create_exit, 0, 'create-game succeeds';
    like $create_stdout, qr/^store=local$/m, 'local store is selected';
    is $create_stderr, '', 'create-game has no diagnostics';

    my @published;
    for my $move (@moves) {
        my ($exit, $stdout, $stderr) = _run_cli(
            'publish-move',
            '--nonce',
            $move->{nonce},
            $game,
            $move->{action},
        );

        is $exit, 0, "publish $move->{action} succeeds";
        is $stderr, '', "publish $move->{action} has no diagnostics";
        push @published, _event_from_stdout($stdout);
    }

    my ($id1) = $published[0] =~ /\.h-([0-9a-v]{16})\z/;
    my ($id2) = $published[1] =~ /\.h-([0-9a-v]{16})\z/;
    my ($id3) = $published[2] =~ /\.h-([0-9a-v]{16})\z/;

    like $published[0], qr/\Am1\.p000001\.b\.play-aa\.pa-genesis\.by-alice\.n-b1\.h-[0-9a-v]{16}\z/,
        'black opens at aa';
    like $published[1], qr/\Am1\.p000002\.w\.play-bb\.pa-\Q$id1\E\.by-bob\.n-w1\.h-[0-9a-v]{16}\z/,
        'white follows at bb';
    like $published[2], qr/\Am1\.p000003\.b\.pass\.pa-\Q$id2\E\.by-alice\.n-b2\.h-[0-9a-v]{16}\z/,
        'black pass is third';
    like $published[3], qr/\Am1\.p000004\.w\.resign\.pa-\Q$id3\E\.by-bob\.n-w2\.h-[0-9a-v]{16}\z/,
        'white resign is fourth';

    my ($replay_exit, $replay_stdout, $replay_stderr) = _run_cli('replay', $game);
    is $replay_exit, 0, 'replay succeeds by descriptor basename';
    like $replay_stdout, qr/^canonical_moves=4$/m, 'all four moves are canonical';
    is $replay_stderr, '', 'replay has no diagnostics';

    my ($sgf_exit, $sgf_stdout, $sgf_stderr) = _run_cli('sgf', $game);
    is $sgf_exit, 0, 'sgf succeeds by descriptor basename';
    like $sgf_stdout, qr/;B\[aa\].*;W\[bb\].*;B\[\].*;W\[\]C\[resign\]/s,
        'SGF shows the alternating play flow';
    is $sgf_stderr, '', 'sgf has no diagnostics';

    is_deeply [_event_names(File::Spec->catdir($root, $game))], [sort @published],
        'store listing contains only the published move names';
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

sub _event_from_stdout {
    my ($stdout) = @_;

    my ($event) = $stdout =~ /^event=(m1\..+)$/m;
    die "publish output did not include an event line:\n$stdout" if !defined $event;

    return $event;
}

sub _event_names {
    my ($game_root) = @_;

    my $dir = File::Spec->catdir($game_root, 'events');
    opendir my $dh, $dir or die "opendir $dir: $!";
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh or die "closedir $dir: $!";

    return @names;
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

sub _read_moves {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my $header = <$fh>;
    die "$path is empty" if !defined $header;
    chomp $header;
    my @columns = split /\t/, $header;

    my @moves;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        my @values = split /\t/, $line;
        my %move;
        @move{@columns} = @values;
        push @moves, \%move;
    }
    close $fh or die "close $path: $!";

    return @moves;
}
