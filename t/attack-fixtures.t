use v5.34;
use strict;
use warnings;

use FindBin;
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";

use GobanFTP::CLI;
use GobanFTP::EventSetRoot qw(event_set_root_result);
use GobanFTP::Listing qw(event_basenames normalize_listing);
use GobanFTP::Replay qw(replay);

my $fixture_dir = "$FindBin::Bin/fixtures/attacks";

my @attacks = grep { -d File::Spec->catdir($fixture_dir, $_) }
    grep { $_ ne '.' && $_ ne '..' }
    _dir_names($fixture_dir);

ok @attacks, 'attack fixture gallery is present';

for my $attack (@attacks) {
    subtest $attack => sub {
        my $dir      = File::Spec->catdir($fixture_dir, $attack);
        my $expected = _read_verdict(File::Spec->catfile($dir, 'expected.verdict'));
        my $game     = _read_single(File::Spec->catfile($dir, 'game.name'));
        my @raw      = _read_names(File::Spec->catfile($dir, 'listing.names'));
        my @events   = normalize_listing(@raw);

        is $expected->{attack}, $attack, 'verdict attack name matches directory';
        is $game, $expected->{game}, 'game descriptor matches verdict';
        is scalar(@events), 0 + $expected->{events}, 'normalized event-looking listing count';

        my $event_set = event_set_root_result(game_descriptor => $game, names => \@raw);
        is $event_set->{event_count}, 0 + $expected->{event_set_count}, 'event-set count';
        is $event_set->{event_set_root}, $expected->{event_set_root}, 'event-set root';

        my $result = replay(game_descriptor => $game, events => \@events);
        _assert_replay_result($result, $expected);

        if (($expected->{mode} // '') eq 'local') {
            my ($game_root) = _materialize_local_game($dir, $game, \@raw);
            _assert_cli_result($dir, $game_root, $expected);
        }
    };
}

done_testing;

sub _assert_replay_result {
    my ($result, $expected) = @_;

    my @canonical_ids = $result->canonical_ids;
    my @legal_ids     = $result->legal_ids;

    is scalar(@canonical_ids), 0 + $expected->{canonical_moves}, 'canonical move count';
    is scalar(@legal_ids),     0 + $expected->{legal_moves},     'legal move count';
    is join(',', @canonical_ids), $expected->{canonical_ids}, 'canonical ids';
    is join(',', @legal_ids),     $expected->{legal_ids},     'legal ids';

    _assert_diagnostics([$result->diagnostics], $expected);
}

sub _assert_cli_result {
    my ($fixture_dir, $game_root, $expected) = @_;

    my $events_dir   = File::Spec->catdir($game_root, 'events');
    my @events_before = _dir_names($events_dir);
    my %bytes_before  = map { $_ => _slurp(File::Spec->catfile($events_dir, $_)) } @events_before;

    my ($exit, $stdout, $stderr) = _run_cli($expected->{command}, $game_root);
    my $cli_status = _cli_status($expected->{status});

    is $exit, 0 + $expected->{exit}, "$expected->{command} exit";
    like $stdout, qr/^gobanftp\.\Q$expected->{command}\E=\Q$cli_status\E$/m,
        "$expected->{command} status";
    like $stdout, qr/^events=\Q$expected->{events}\E$/m, 'CLI reports event count';
    like $stdout, qr/^event_set_count=\Q$expected->{event_set_count}\E$/m,
        'CLI reports event-set count';
    like $stdout, qr/^event_set_root=\Q$expected->{event_set_root}\E$/m,
        'CLI reports event-set root';
    like $stdout, qr/^canonical_moves=\Q$expected->{canonical_moves}\E$/m,
        'CLI reports canonical move count';
    like $stdout, qr/^legal_moves=\Q$expected->{legal_moves}\E$/m,
        'CLI reports legal move count';

    if (($expected->{'diagnostic.code'} // '') eq '') {
        is $stderr, '', 'CLI has no diagnostics';
    }
    else {
        _assert_diagnostic_line($stderr, $expected);
    }

    is_deeply [_dir_names($events_dir)], \@events_before, 'event names are unchanged';
    for my $name (@events_before) {
        is _slurp(File::Spec->catfile($events_dir, $name)), $bytes_before{$name},
            "event bytes unchanged: $name";
    }

    _assert_project_rebuilt_from_events($game_root, $expected)
        if $expected->{command} eq 'project' && $expected->{exit} == 0;
}

sub _assert_project_rebuilt_from_events {
    my ($game_root, $expected) = @_;

    my $board   = _slurp(File::Spec->catfile($game_root, qw(projections oracle board.txt)));
    my $verdict = _slurp(File::Spec->catfile($game_root, qw(projections oracle verdict.txt)));
    my $listing = _slurp(File::Spec->catfile($game_root, qw(projections oracle listing.txt)));
    my $sgf     = _slurp(File::Spec->catfile($game_root, qw(projections sgf main.sgf)));

    like $board, qr/^3 B \. \.$/m, 'board projection contains black aa';
    like $board, qr/^2 \. W \.$/m, 'board projection contains white bb';
    like $verdict, qr/^status=ok$/m, 'verdict projection is rebuilt as ok';
    like $verdict, qr/^canonical_ids=\Q$expected->{canonical_ids}\E$/m,
        'verdict projection records canonical ids';
    like $sgf, qr/;B\[aa\].*;W\[bb\].*;B\[\]/s, 'SGF projection follows event basenames';

    unlike $listing, qr/poison|not-consensus|claim=|pending\.part/,
        'listing transcript excludes ignored poison material';
    unlike $verdict, qr/poison|not-consensus/, 'verdict projection overwrites stale poison';
    unlike $sgf, qr/B\[cc\]/, 'SGF projection overwrites stale poison';
}

sub _assert_diagnostics {
    my ($diagnostics, $expected) = @_;

    my $code = $expected->{'diagnostic.code'} // '';
    if ($code eq '') {
        is_deeply $diagnostics, [], 'no diagnostics';
        return;
    }

    my ($match) = grep { ($_->{code} // '') eq $code } @$diagnostics;
    ok defined($match), "diagnostic code $code is present";
    return if !defined $match;

    for my $key (sort keys %$expected) {
        next if $key !~ /\Adiagnostic\.(.+)\z/;
        my $field = $1;
        next if $field eq 'code';
        my $want = $expected->{$key};
        if (ref($match->{$field}) eq 'ARRAY') {
            is join(',', @{ $match->{$field} }), $want, "diagnostic $field";
        }
        else {
            is $match->{$field} // '', $want, "diagnostic $field";
        }
    }
}

sub _assert_diagnostic_line {
    my ($stderr, $expected) = @_;

    my $code = $expected->{'diagnostic.code'};
    like $stderr, qr/^diagnostic .*code=\Q$code\E/m, "CLI diagnostic code $code";

    for my $key (sort keys %$expected) {
        next if $key !~ /\Adiagnostic\.(.+)\z/;
        my $field = $1;
        next if $field eq 'code';
        my $want = $expected->{$key};
        like $stderr, qr/^diagnostic .*\Q$field=$want\E/m, "CLI diagnostic $field";
    }
}

sub _materialize_local_game {
    my ($fixture_dir, $game, $raw_names) = @_;

    my $root       = tempdir(CLEANUP => 1);
    my $game_root  = File::Spec->catdir($root, $game);
    my $events_dir = File::Spec->catdir($game_root, 'events');
    make_path($events_dir);

    my $event_bytes_path = File::Spec->catfile($fixture_dir, 'event-bytes.txt');
    my $event_bytes = -f $event_bytes_path ? _slurp($event_bytes_path) : "ignored event bytes\n";

    my %seen;
    for my $event (event_basenames($raw_names)) {
        next if $seen{$event}++;
        _write_text(File::Spec->catfile($events_dir, $event), $event_bytes);
    }

    for my $surface (qw(sidecar tmp projections)) {
        my $source = File::Spec->catdir($fixture_dir, $surface);
        next if !-d $source;
        _copy_tree($source, File::Spec->catdir($game_root, $surface));
    }

    return ($game_root);
}

sub _copy_tree {
    my ($source, $target) = @_;

    find(
        {
            no_chdir => 1,
            wanted   => sub {
                my $path = $File::Find::name;
                my $rel  = File::Spec->abs2rel($path, $source);
                return if $rel eq '.';

                my $dest = File::Spec->catfile($target, File::Spec->splitdir($rel));
                if (-d $path) {
                    make_path($dest);
                    return;
                }

                make_path(dirname($dest));
                copy($path, $dest) or die "copy $path to $dest: $!";
            },
        },
        $source,
    );
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

sub _cli_status {
    my ($status) = @_;
    return 'ok'     if $status eq 'ok';
    return 'fork'   if $status eq 'fork';
    return 'failed' if $status eq 'validation';
    die "unsupported status: $status";
}

sub _read_verdict {
    my ($path) = @_;

    my %verdict;
    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        my ($key, $value) = split /=/, $line, 2;
        die "bad verdict line in $path: $line" if !defined($key) || !defined($value);
        $verdict{$key} = $value;
    }
    close $fh or die "close $path: $!";

    return \%verdict;
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

sub _dir_names {
    my ($dir) = @_;

    opendir my $dh, $dir or die "opendir $dir: $!";
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh or die "closedir $dir: $!";

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
