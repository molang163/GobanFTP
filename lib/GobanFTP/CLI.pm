package GobanFTP::CLI;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Cwd qw(abs_path);
use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use File::Spec;
use Fcntl qw(O_CREAT O_EXCL O_TRUNC O_WRONLY);
use JSON::PP qw(decode_json);
use Scalar::Util qw(reftype);

use GobanFTP ();
use GobanFTP::AckPublisher qw(build_ack_for_target);
use GobanFTP::Auth::Boundary qw(
    auth_boundary_record
    publish_preflight_scope
);
use GobanFTP::Auth::HMAC qw(sign_event);
use GobanFTP::Auth::HMACKey qw(
    generate_hmac_key_record
    read_hmac_key_file
    write_hmac_key_file
);
use GobanFTP::Auth::KeyID qw(parse_public_key_record);
use GobanFTP::Auth::PublishToken qw(
    publish_authorization_result
    sign_publish_token
);
use GobanFTP::Auth::TrustReport qw(trust_lifecycle_decision trust_report_summary);
use GobanFTP::Diagnostics qw(diagnostic_classes diagnostic_codes);
use GobanFTP::EventSetRoot qw(event_set_root_result);
use GobanFTP::Filename::Grammar qw(parse_event);
use GobanFTP::Listing qw(normalize_listing sort_event_basenames);
use GobanFTP::GameSpec qw(build_basename parse_basename);
use GobanFTP::MovePublisher qw(build_next_move_name normalize_action);
use GobanFTP::Profile qw(known_profile);
use GobanFTP::Projection qw(render_projection write_projection write_sgf_projection);
use GobanFTP::Redact qw(contains_redactable_secret redact_text);
use GobanFTP::Replay qw(replay);
use GobanFTP::JSON qw(encode_json_doc json_doc);
use GobanFTP::Showcase::StaticPreview qw(expected_files);
use GobanFTP::Store::Config qw(
    context_for_descriptor
    context_for_game_arg
    doctor_report
    store_capabilities
    store_config_summary
    store_mode
);
use GobanFTP::Surface::WitnessView qw(
    render_witness_html
    render_witness_terminal
    render_witness_text
);
use GobanFTP::TUI::Play qw(run_play_tui);
use GobanFTP::Witness qw(witness_for_listing);

use constant {
    EXIT_SUCCESS    => 0,
    EXIT_USAGE      => 1,
    EXIT_VALIDATION => 2,
    EXIT_CONFLICT   => 3,
    EXIT_STORAGE    => 4,
    EXIT_INTERNAL   => 5,
};

my @V1_COMPARE_DEFAULT_PROFILES = qw(
    local-goftp1
    ftp-goftp1
    git-tree-goftp1
    dns-record-goftp1
    webdav-goftp1
);

use constant {
    JSONL_MAX_FILE_BYTES => 1_048_576,
    JSONL_MAX_LINE_BYTES => 8_192,
    JSONL_MAX_RECORDS    => 10_000,
};

sub run {
    my ($class, @argv) = @_;

    return _usage(*STDERR, EXIT_USAGE) if @argv == 0;
    return _usage(*STDOUT, EXIT_SUCCESS) if @argv == 1 && ($argv[0] eq '--help' || $argv[0] eq 'help');
    if (@argv == 1 && $argv[0] eq '--version') {
        print STDOUT "gobanftp $GobanFTP::VERSION\n";
        return EXIT_SUCCESS;
    }

    my $command = shift @argv;

    if ($command eq 'config') {
        return _run_checked_command($command, \@argv, \&_command_config);
    }

    if ($command eq 'doctor') {
        return _run_checked_command($command, \@argv, \&_command_doctor);
    }

    if ($command eq 'showcase') {
        return _run_checked_command($command, \@argv, \&_command_showcase);
    }

    if ($command eq 'create-game') {
        return _run_checked_command($command, \@argv, \&_command_create_game);
    }

    if ($command eq 'verify') {
        return _run_checked_command($command, \@argv, \&_command_verify);
    }

    if ($command eq 'replay') {
        return _run_checked_command($command, \@argv, \&_command_replay);
    }

    if ($command eq 'project') {
        return _run_checked_command($command, \@argv, \&_command_project);
    }

    if ($command eq 'sgf') {
        return _run_checked_command($command, \@argv, \&_command_sgf);
    }

    if ($command eq 'publish-move') {
        return _run_checked_command($command, \@argv, \&_command_publish_move);
    }

    if ($command eq 'publish-ack') {
        return _run_checked_command($command, \@argv, \&_command_publish_ack);
    }

    if ($command eq 'play') {
        return _run_checked_command($command, \@argv, \&_command_play);
    }

    if ($command eq 'watch') {
        return _run_checked_command($command, \@argv, \&_command_watch);
    }

    if ($command eq 'v1') {
        return _run_checked_command($command, \@argv, \&_command_v1);
    }

    print STDERR 'unknown command: ' . _escape_control_chars($command) . "\n";
    return _usage(*STDERR, EXIT_USAGE);
}

sub _run_checked_command {
    my ($command, $argv, $code) = @_;

    my $exit = eval { $code->(@$argv) };
    if (defined $exit) {
        return $exit;
    }

    my $error = $@ || 'unknown error';
    chomp $error;
    $error = _clean_error($error);

    if ($error =~ /\Ausage:/) {
        print STDERR "$error\n";
        return _usage(*STDERR, EXIT_USAGE);
    }

    $error = redact_text($error);

    if ($error =~ /\Astorage:/) {
        $error =~ s/\Astorage:\s*//;
        print STDERR "storage: $error\n";
        return EXIT_STORAGE;
    }

    print STDERR "internal: $error\n";
    return EXIT_INTERNAL;
}

sub _command_config {
    my (@argv) = @_;

    my $usage = 'usage: config show [--json]';
    die $usage if !@argv || shift(@argv) ne 'show';

    my $json = 0;
    while (@argv) {
        my $option = shift @argv;
        if ($option eq '--json') {
            die $usage if $json;
            $json = 1;
            next;
        }
        die $usage;
    }

    my $summary = store_config_summary();
    if ($json) {
        print STDOUT encode_json_doc(%$summary);
    }
    else {
        _print_config_summary($summary);
    }

    return ($summary->{status} // 'ok') eq 'ok' ? EXIT_SUCCESS : EXIT_VALIDATION;
}

sub _command_doctor {
    my (@argv) = @_;

    my $usage = 'usage: doctor [--json] [--connect]';
    my %opts;
    while (@argv) {
        my $option = shift @argv;
        if ($option eq '--json') {
            die $usage if $opts{json};
            $opts{json} = 1;
            next;
        }
        if ($option eq '--connect') {
            die $usage if $opts{connect};
            $opts{connect} = 1;
            next;
        }
        die $usage;
    }

    my $report = doctor_report(connect => $opts{connect} ? 1 : 0);
    if ($opts{json}) {
        print STDOUT encode_json_doc(%$report);
    }
    else {
        _print_doctor_report($report);
    }

    return $report->{status} eq 'ok' ? EXIT_SUCCESS : EXIT_VALIDATION;
}

sub _command_showcase {
    my (@argv) = @_;

    if (@argv && $argv[0] eq 'preview') {
        shift @argv;
        return _command_showcase_preview(@argv);
    }

    my $usage = _showcase_usage_line();
    my %opts;
    while (@argv) {
        my $option = shift @argv;
        if ($option eq '--json') {
            die $usage if $opts{json};
            $opts{json} = 1;
            next;
        }
        my ($name, $value);
        if ($option =~ /\A--([^=]+)=(.*)\z/) {
            ($name, $value) = ($1, $2);
        }
        elsif ($option =~ /\A--(.+)\z/) {
            $name = $1;
            die $usage if !@argv;
            $value = shift @argv;
        }
        else {
            die $usage;
        }

        if ($name eq 'out') {
            die $usage if defined $opts{out};
            $opts{out} = $value;
            next;
        }
        die $usage;
    }

    die $usage if !defined($opts{out}) || $opts{out} eq '' || $opts{out} eq '-';
    _reject_control_path($opts{out}, $usage);

    my @files = _showcase_expected_files();
    my $out_abs = File::Spec->rel2abs($opts{out});
    if (my $diagnostic = _prepare_showcase_out_dir($out_abs, \@files)) {
        my $showcase = _showcase_failure_doc($out_abs, \@files, $diagnostic);
        if ($opts{json}) {
            print STDOUT encode_json_doc(%$showcase);
        }
        else {
            _print_showcase_failure($showcase);
        }
        return EXIT_VALIDATION;
    }

    my $showcase = _write_showcase_artifacts($out_abs, \@files);
    if ($opts{json}) {
        print STDOUT encode_json_doc(%$showcase);
    }
    else {
        _print_showcase_summary($showcase);
    }

    return EXIT_SUCCESS;
}

sub _command_showcase_preview {
    my (@argv) = @_;

    my $usage = _showcase_usage_line();
    my %opts = (port => 0);
    while (@argv) {
        my $option = shift @argv;
        if ($option eq '--once') {
            die $usage if $opts{once};
            $opts{once} = 1;
            next;
        }
        my ($name, $value);
        if ($option =~ /\A--([^=]+)=(.*)\z/) {
            ($name, $value) = ($1, $2);
        }
        elsif ($option =~ /\A--(.+)\z/) {
            $name = $1;
            die $usage if !@argv;
            $value = shift @argv;
        }
        else {
            die $usage;
        }

        if ($name eq 'dir') {
            die $usage if defined $opts{dir};
            $opts{dir} = $value;
            next;
        }
        if ($name eq 'port') {
            die $usage if defined $opts{seen_port};
            $opts{seen_port} = 1;
            $opts{port} = $value;
            next;
        }
        die $usage;
    }

    die $usage if !defined($opts{dir}) || $opts{dir} eq '' || $opts{dir} eq '-';
    die $usage if !defined($opts{port}) || $opts{port} !~ /\A(?:0|[1-9][0-9]{0,4})\z/ || $opts{port} > 65535;
    _reject_control_path($opts{dir}, $usage);

    my $preview = GobanFTP::Showcase::StaticPreview->new(
        dir  => File::Spec->rel2abs($opts{dir}),
        port => $opts{port},
        once => $opts{once} ? 1 : 0,
    );

    my $old = select STDOUT;
    $| = 1;
    select $old;

    print STDOUT "gobanftp.showcase.preview=ok\n";
    print STDOUT "boundary=localhost-static-preview-only\n";
    print STDOUT "dir=" . _stdout_value($preview->dir) . "\n";
    print STDOUT "host=" . _stdout_value($preview->host) . "\n";
    print STDOUT "port=" . _stdout_value($preview->port) . "\n";
    print STDOUT "url=" . _stdout_value($preview->url) . "\n";
    print STDOUT "remote_access=0\n";
    print STDOUT "hosted_web_ui=0\n";
    print STDOUT "files=" . _stdout_value([$preview->files]) . "\n";

    $preview->serve;
    return EXIT_SUCCESS;
}

sub _command_create_game {
    my (@argv) = @_;

    my ($descriptor, $error) = _descriptor_from_create_args(@argv);
    die "usage: create-game [--id id --black player --white player] [--size n] [--rules id] [--komi milli]\n"
        if defined $error;

    my $context = eval { context_for_descriptor($descriptor) };
    die 'storage: ' . $@ if !$context;

    eval {
        $context->{store}->mkdir($context->{store_game_root});
        $context->{store}->mkdir("$context->{store_game_root}/events");
        $context->{store}->mkdir("$context->{store_game_root}/tmp");
        1;
    } or die 'storage: ' . $@;

    print STDOUT "gobanftp.create-game=ok\n";
    print STDOUT "store=$context->{store_kind}\n";
    print STDOUT "game=$context->{game_descriptor}\n";
    print STDOUT "root=$context->{game_root}\n";

    return EXIT_SUCCESS;
}

sub _command_verify {
    my (@argv) = @_;
    die "usage: verify <game-root|game-descriptor>" if @argv != 1;

    my $context = _load_context($argv[0]);
    my $exit    = _result_exit($context->{replay_result});
    my $status  = $exit == EXIT_SUCCESS ? 'ok' : $exit == EXIT_CONFLICT ? 'fork' : 'failed';

    _print_summary('verify', $status, $context, event_set => 1);
    _print_diagnostics($context->{replay_result});

    return $exit;
}

sub _command_replay {
    my (@argv) = @_;
    die "usage: replay <game-root|game-descriptor>" if @argv != 1;

    my $context = _load_context($argv[0]);
    my $exit    = _result_exit($context->{replay_result});
    my $status  = $exit == EXIT_SUCCESS ? 'ok' : $exit == EXIT_CONFLICT ? 'fork' : 'failed';

    _print_summary('replay', $status, $context, event_set => 1);
    print STDOUT 'canonical_ids=' . join(',', _canonical_ids($context->{replay_result})) . "\n";
    _print_diagnostics($context->{replay_result});

    return $exit;
}

sub _command_project {
    my (@argv) = @_;
    die "usage: project <game-root|game-descriptor>" if @argv != 1;

    _require_local_store_for_write('project writes local projection files and requires the local store');

    my $context = eval { context_for_game_arg($argv[0]) };
    die 'storage: ' . $@ if !$context;

    $context = _reload_context($context);
    my $exit    = _result_exit($context->{replay_result});
    if ($exit != EXIT_SUCCESS && ($exit != EXIT_CONFLICT || $context->{store_kind} ne 'local')) {
        _print_summary('project', $exit == EXIT_CONFLICT ? 'fork' : 'failed', $context, event_set => 1);
        _print_diagnostics($context->{replay_result});
        return $exit;
    }

    my $written = write_projection(
        game_root       => $context->{game_root},
        game_descriptor => $context->{game_descriptor},
        events          => $context->{events},
        replay_result   => $context->{replay_result},
    );

    _print_summary('project', $exit == EXIT_CONFLICT ? 'fork' : 'ok', $context, event_set => 1);
    print STDOUT "sgf=$written->{paths}{sgf}\n";
    print STDOUT "board=$written->{paths}{board}\n";
    print STDOUT "verdict=$written->{paths}{verdict}\n";
    print STDOUT "listing=$written->{paths}{listing}\n";
    _print_diagnostics($context->{replay_result});

    return $exit;
}

sub _command_sgf {
    my (@argv) = @_;

    my $write = 0;
    my $variations = 0;
    @argv = grep {
        if ($_ eq '--write') {
            $write = 1;
            0;
        }
        elsif ($_ eq '--variations') {
            $variations = 1;
            0;
        }
        else {
            1;
        }
    } @argv;
    die "usage: sgf [--write] <game-root|game-descriptor> | sgf --variations <game-root|game-descriptor>"
        if @argv != 1 || ($write && $variations);

    my $context;
    if ($write) {
        _require_local_store_for_write('sgf --write writes local projection files and requires the local store');

        $context = eval { context_for_game_arg($argv[0]) };
        die 'storage: ' . $@ if !$context;
        $context = _reload_context($context);
    }
    else {
        $context = _load_context($argv[0]);
    }

    my $exit    = _result_exit($context->{replay_result});
    if ($exit != EXIT_SUCCESS) {
        if ($variations && $exit == EXIT_CONFLICT) {
            my $rendered = render_projection(
                game_descriptor => $context->{game_descriptor},
                events          => $context->{events},
                replay_result   => $context->{replay_result},
            );
            print STDOUT $rendered->{sgf_variations};
            _print_diagnostics($context->{replay_result});
            return $exit;
        }

        _print_summary('sgf', $exit == EXIT_CONFLICT ? 'fork' : 'failed', $context);
        _print_diagnostics($context->{replay_result});
        return $exit;
    }

    if ($write) {
        my $written = write_sgf_projection(
            game_root       => $context->{game_root},
            game_descriptor => $context->{game_descriptor},
            events          => $context->{events},
            replay_result   => $context->{replay_result},
        );
        print STDOUT "gobanftp.sgf=ok\n";
        print STDOUT "game=$context->{game_descriptor}\n";
        print STDOUT "sgf=$written->{path}\n";
        return EXIT_SUCCESS;
    }

    my $rendered = render_projection(
        game_descriptor => $context->{game_descriptor},
        events          => $context->{events},
        replay_result   => $context->{replay_result},
    );
    print STDOUT $variations ? $rendered->{sgf_variations} : $rendered->{sgf};

    return EXIT_SUCCESS;
}

sub _command_publish_move {
    my (@argv) = @_;

    my $usage = _publish_move_usage_line();
    my %opts = _publish_auth_default_opts();
    while (@argv && $argv[0] =~ /\A--/) {
        my $option = shift @argv;
        if ($option eq '--nonce') {
            die $usage if !@argv;
            $opts{nonce} = shift @argv;
            next;
        }
        if ($option =~ /\A--nonce=(.+)\z/) {
            $opts{nonce} = $1;
            next;
        }
        if ($option eq '--json') {
            die $usage if $opts{json};
            $opts{json} = 1;
            next;
        }
        next if _consume_publish_auth_option($option, \@argv, \%opts, $usage);
        die $usage;
    }

    die $usage if @argv != 2;
    die $usage
        if defined($opts{nonce}) && $opts{nonce} !~ /\A[a-z0-9_-]{1,16}\z/;
    my $publish_auth = _publish_auth_config_or_usage(\%opts, $usage);

    my ($game_arg, $move_input) = @argv;
    my ($action, $action_error) = normalize_action($move_input);
    die $usage if defined $action_error;

    my $context = _load_context($game_arg);
    return _publish_action(
        command => 'publish-move',
        context => $context,
        action  => $action,
        defined($opts{nonce}) ? (nonce => $opts{nonce}) : (),
        defined($publish_auth) ? (publish_auth => $publish_auth) : (),
        $opts{json} ? (json => 1) : (),
    );
}

sub _command_publish_ack {
    my (@argv) = @_;

    my $usage = _publish_ack_usage_line();
    my %opts = _publish_auth_default_opts();
    while (@argv && $argv[0] =~ /\A--/) {
        my $option = shift @argv;
        if ($option eq '--nonce') {
            die $usage if !@argv;
            $opts{nonce} = shift @argv;
            next;
        }
        if ($option =~ /\A--nonce=(.+)\z/) {
            $opts{nonce} = $1;
            next;
        }
        if ($option eq '--json') {
            die $usage if $opts{json};
            $opts{json} = 1;
            next;
        }
        next if _consume_publish_auth_option($option, \@argv, \%opts, $usage);
        die $usage;
    }

    die $usage if @argv != 2;
    die $usage
        if defined($opts{nonce}) && $opts{nonce} !~ /\A[a-z0-9_-]{1,16}\z/;
    my $publish_auth = _publish_auth_config_or_usage(\%opts, $usage);

    my ($game_arg, $target_id) = @argv;
    die $usage if $target_id !~ /\A[0-9a-v]{16}\z/;

    my $context = _load_context($game_arg);
    return _publish_ack(
        command   => 'publish-ack',
        context   => $context,
        target_id => $target_id,
        defined($opts{nonce}) ? (nonce => $opts{nonce}) : (),
        defined($publish_auth) ? (publish_auth => $publish_auth) : (),
        $opts{json} ? (json => 1) : (),
    );
}

sub _command_play {
    my (@argv) = @_;
    my $usage = _play_usage_line();

    my %opts = (
        _publish_auth_default_opts(),
        interval => 2,
    );
    while (@argv && $argv[0] =~ /\A--/) {
        my $option = shift @argv;
        if ($option eq '--once') {
            $opts{once} = 1;
            next;
        }
        if ($option eq '--live') {
            $opts{live} = 1;
            next;
        }
        if ($option eq '--tui') {
            $opts{tui} = 1;
            next;
        }
        if ($option eq '--count') {
            die $usage if !@argv;
            $opts{count} = shift @argv;
            next;
        }
        if ($option =~ /\A--count=(.+)\z/) {
            $opts{count} = $1;
            next;
        }
        if ($option eq '--max-polls') {
            die $usage if !@argv;
            $opts{count} = shift @argv;
            next;
        }
        if ($option =~ /\A--max-polls=(.+)\z/) {
            $opts{count} = $1;
            next;
        }
        if ($option eq '--interval') {
            die $usage if !@argv;
            $opts{interval} = shift @argv;
            next;
        }
        if ($option =~ /\A--interval=(.+)\z/) {
            $opts{interval} = $1;
            next;
        }
        if ($option eq '--move') {
            die $usage
                if !@argv;
            $opts{move} = shift @argv;
            next;
        }
        if ($option =~ /\A--move=(.+)\z/) {
            $opts{move} = $1;
            next;
        }
        if ($option eq '--ack') {
            die $usage
                if !@argv;
            $opts{ack} = shift @argv;
            next;
        }
        if ($option =~ /\A--ack=(.+)\z/) {
            $opts{ack} = $1;
            next;
        }
        if ($option eq '--nonce') {
            die $usage
                if !@argv;
            $opts{nonce} = shift @argv;
            next;
        }
        if ($option =~ /\A--nonce=(.+)\z/) {
            $opts{nonce} = $1;
            next;
        }
        next if _consume_publish_auth_option($option, \@argv, \%opts, $usage);
        die $usage;
    }

    die $usage if @argv != 1 || (defined($opts{move}) && defined($opts{ack}));
    die $usage if $opts{tui} && ($opts{once} || defined($opts{move}) || defined($opts{ack}));
    die $usage if $opts{live} && ($opts{once} || $opts{tui} || defined($opts{move}) || defined($opts{ack}));
    die $usage
        if defined($opts{count}) && $opts{count} !~ /\A[1-9][0-9]*\z/;
    die $usage
        if !defined($opts{interval}) || $opts{interval} !~ /\A(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\z/;
    die $usage if !$opts{live} && (defined($opts{count}) || $opts{interval} != 2);
    die $usage
        if defined($opts{nonce}) && $opts{nonce} !~ /\A[a-z0-9_-]{1,16}\z/;
    die $usage
        if defined($opts{ack}) && $opts{ack} !~ /\A[0-9a-v]{16}\z/;
    my $publish_auth = _publish_auth_config_or_usage(\%opts, $usage);
    die $usage if defined($publish_auth)
        && !defined($opts{move})
        && !defined($opts{ack})
        && !$opts{tui};

    my ($game_arg) = @argv;

    if ($opts{live}) {
        return _run_watch_loop(
            command  => 'play',
            game_arg => $game_arg,
            count    => $opts{count},
            interval => $opts{interval},
            live     => 1,
        );
    }

    if ($opts{tui}) {
        return _command_play_tui(
            $game_arg,
            defined($opts{nonce}) ? (nonce => $opts{nonce}) : (),
            defined($publish_auth) ? (publish_auth => $publish_auth) : (),
        );
    }

    if (defined $opts{move}) {
        my ($action, $action_error) = normalize_action($opts{move});
        die $usage if defined $action_error;

        my $context = _load_context($game_arg);
        my $publish = _publish_action_result(
            command => 'play',
            context => $context,
            action  => $action,
            defined($opts{nonce}) ? (nonce => $opts{nonce}) : (),
            defined($publish_auth) ? (publish_auth => $publish_auth) : (),
        );
        if ($publish->{exit} != EXIT_SUCCESS) {
            if ($publish->{stage} eq 'published') {
                _print_event_result($publish);
                _print_publish_auth_result($publish);
                my $exit = _print_terminal_snapshot('play', $publish->{context});
                _print_diagnostics($publish->{context}{replay_result});
                return $exit;
            }

            _print_publish_result('play', $publish);
            return $publish->{exit};
        }

        _print_event_result($publish);
        _print_publish_auth_result($publish);
        return _print_terminal_snapshot('play', $publish->{context});
    }

    if (defined $opts{ack}) {
        my $context = _load_context($game_arg);
        my $publish = _publish_ack_result(
            command       => 'play',
            context       => $context,
            target_id     => $opts{ack},
            reload_policy => 'ack-assisted',
            defined($opts{nonce}) ? (nonce => $opts{nonce}) : (),
            defined($publish_auth) ? (publish_auth => $publish_auth) : (),
        );
        if ($publish->{stage} ne 'published') {
            _print_publish_result('play', $publish);
            return $publish->{exit};
        }

        _print_event_result($publish);
        _print_publish_auth_result($publish);
        my $exit = _print_terminal_snapshot('play', $publish->{context});
        _print_diagnostics($publish->{context}{replay_result});
        return $exit;
    }

    my $context = _load_context($game_arg);
    my $exit = _print_terminal_snapshot('play', $context);
    _print_diagnostics($context->{replay_result});
    return $exit if $opts{once} || $exit != EXIT_SUCCESS || _terminal_replay($context->{replay_result});

    while (1) {
        print STDERR "move> ";
        my $line = <STDIN>;
        return EXIT_SUCCESS if !defined $line;

        chomp $line;
        $line =~ s/\A\s+//;
        $line =~ s/\s+\z//;
        next if $line eq '';
        return EXIT_SUCCESS if $line eq 'quit' || $line eq 'exit' || $line eq 'q';

        if ($line eq 'refresh') {
            $context = _load_context($game_arg);
            $exit = _print_terminal_snapshot('play', $context);
            _print_diagnostics($context->{replay_result});
            return $exit if $exit != EXIT_SUCCESS || _terminal_replay($context->{replay_result});
            next;
        }

        my ($action, $action_error) = normalize_action($line);
        if (defined $action_error) {
            print STDERR "usage: enter aa, play-aa, pass, resign, refresh, quit, exit, or q\n";
            next;
        }

        my $move_context = _load_context($game_arg);
        my $publish = _publish_action_result(
            command => 'play',
            context => $move_context,
            action  => $action,
        );
        if ($publish->{exit} != EXIT_SUCCESS) {
            if ($publish->{stage} eq 'published') {
                _print_event_result($publish);
                $context = $publish->{context};
                $exit = _print_terminal_snapshot('play', $context);
                _print_diagnostics($context->{replay_result});
                return $exit;
            }

            _print_publish_result('play', $publish);
            next if $publish->{stage} eq 'candidate' && $publish->{exit} == EXIT_VALIDATION;
            return $publish->{exit};
        }

        _print_event_result($publish);
        $context = $publish->{context};
        $exit = _print_terminal_snapshot('play', $context);
        _print_diagnostics($context->{replay_result});
        return $exit if $exit != EXIT_SUCCESS || _terminal_replay($context->{replay_result});
    }
}

sub _command_play_tui {
    my ($game_arg, %opts) = @_;

    die "storage: play --tui requires an interactive terminal"
        if !-t STDIN || !-t STDOUT;

    my $session = run_play_tui(
        load_context => sub {
            return _load_context($game_arg);
        },
        publish_action => sub {
            my ($raw_action) = @_;
            my ($action, $action_error) = normalize_action($raw_action);
            return {
                exit  => EXIT_VALIDATION,
                stage => 'input',
                error => $action_error,
            } if defined $action_error;

            my $context = _load_context($game_arg);
            return _publish_action_result(
                command => 'play',
                context => $context,
                action  => $action,
                defined($opts{nonce}) ? (nonce => $opts{nonce}) : (),
                defined($opts{publish_auth}) ? (publish_auth => $opts{publish_auth}) : (),
            );
        },
    );

    my $publish = ref($session) eq 'HASH' ? $session->{publish} : undef;
    return $session->{exit} // EXIT_SUCCESS if ref($publish) ne 'HASH';

    if (($publish->{stage} // '') ne 'published') {
        _print_publish_result('play', $publish);
        return $publish->{exit} // EXIT_VALIDATION;
    }

    _print_event_result($publish);
    _print_publish_auth_result($publish);
    my $exit = _print_terminal_snapshot('play', $publish->{context});
    _print_diagnostics($publish->{context}{replay_result});
    return $exit;
}

sub _command_watch {
    my (@argv) = @_;

    my %opts = (
        interval => 2,
    );

    while (@argv && $argv[0] =~ /\A--/) {
        my $option = shift @argv;
        if ($option eq '--live') {
            $opts{live} = 1;
            next;
        }
        if ($option eq '--compact') {
            $opts{compact} = 1;
            next;
        }
        if ($option eq '--once') {
            $opts{count} = 1;
            next;
        }
        if ($option eq '--count') {
            die _watch_usage_line() if !@argv;
            $opts{count} = shift @argv;
            next;
        }
        if ($option =~ /\A--count=(.+)\z/) {
            $opts{count} = $1;
            next;
        }
        if ($option eq '--max-polls') {
            die _watch_usage_line() if !@argv;
            $opts{count} = shift @argv;
            next;
        }
        if ($option =~ /\A--max-polls=(.+)\z/) {
            $opts{count} = $1;
            next;
        }
        if ($option eq '--interval') {
            die _watch_usage_line() if !@argv;
            $opts{interval} = shift @argv;
            next;
        }
        if ($option =~ /\A--interval=(.+)\z/) {
            $opts{interval} = $1;
            next;
        }
        die _watch_usage_line();
    }

    die _watch_usage_line() if @argv != 1;
    die _watch_usage_line()
        if defined($opts{count}) && $opts{count} !~ /\A[1-9][0-9]*\z/;
    die _watch_usage_line()
        if !defined($opts{interval}) || $opts{interval} !~ /\A(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\z/;

    my ($game_arg) = @argv;
    return _run_watch_loop(
        command  => 'watch',
        game_arg => $game_arg,
        count    => $opts{count},
        interval => $opts{interval},
        live     => $opts{live} ? 1 : 0,
        compact  => $opts{compact} ? 1 : 0,
    );
}

sub _run_watch_loop {
    my (%opts) = @_;

    my $snapshot = 0;
    my ($previous_event_set_root, $previous_event_set_count);

    while (!defined($opts{count}) || $snapshot < $opts{count}) {
        $snapshot++;

        my $context = _load_context($opts{game_arg});
        my $event_set = $context->{event_set};
        my $current_event_set_root = ref($event_set) eq 'HASH'
            ? ($event_set->{event_set_root} // '')
            : '';
        my $current_event_set_count = ref($event_set) eq 'HASH'
            ? (0 + ($event_set->{event_count} // scalar(@{ $context->{events} // [] })))
            : 0 + scalar(@{ $context->{events} // [] });
        my $delta_events = defined($previous_event_set_count)
            ? $current_event_set_count - $previous_event_set_count
            : $current_event_set_count;
        $delta_events = 0 if $delta_events < 0;
        my $root_changed = defined($previous_event_set_root)
            && $current_event_set_root ne $previous_event_set_root
            ? 1
            : 0;
        my $exit = _print_terminal_snapshot(
            $opts{command},
            $context,
            snapshot => $snapshot,
            $opts{live} ? (live => 1) : (),
            $opts{compact} ? (
                compact                    => 1,
                observer_delta_events      => $delta_events,
                observer_delta_root_changed => $root_changed,
            ) : (),
        );
        _print_diagnostics($context->{replay_result});
        return $exit if $exit != EXIT_SUCCESS && !$opts{live};

        $previous_event_set_root = $current_event_set_root;
        $previous_event_set_count = $current_event_set_count;

        last if defined($opts{count}) && $snapshot >= $opts{count};
        select undef, undef, undef, 0 + $opts{interval};
    }

    return EXIT_SUCCESS;
}

sub _command_v1 {
    my (@argv) = @_;
    die _v1_usage() if !@argv;

    my $subcommand = shift @argv;
    return _command_v1_keygen(@argv) if $subcommand eq 'keygen';
    return _command_v1_keyid(@argv) if $subcommand eq 'keyid';
    return _command_v1_attest(@argv) if $subcommand eq 'attest';
    return _command_v1_publish_token(@argv) if $subcommand eq 'publish-token';
    return _command_v1_publish_auth(@argv) if $subcommand eq 'publish-auth';
    return _command_v1_trust_report(@argv) if $subcommand eq 'trust-report';
    return _command_v1_witness(@argv) if $subcommand eq 'witness';
    return _command_v1_compare('compare-roots', @argv)
        if $subcommand eq 'compare-roots';
    return _command_v1_compare('compare-replay', @argv)
        if $subcommand eq 'compare-replay';

    die _v1_usage();
}

sub _command_v1_keygen {
    my (@argv) = @_;

    my $usage = 'usage: v1 keygen --profile signed-hmac-goftp1 --out hmac-key-file';
    my %opts;

    while (@argv) {
        my ($name, $value) = _option_value($usage, @argv);
        shift @argv;
        $value = shift @argv if !defined $value;

        if ($name eq 'profile') {
            $opts{profile_id} = $value;
            next;
        }
        if ($name eq 'out') {
            $opts{out} = $value;
            next;
        }

        die $usage;
    }

    die $usage if ($opts{profile_id} // '') ne 'signed-hmac-goftp1';
    die $usage if !defined($opts{out}) || $opts{out} eq '' || $opts{out} eq '-';
    _reject_control_path($opts{out}, $usage);

    my $record = eval { generate_hmac_key_record(profile => $opts{profile_id}) };
    die 'storage: ' . $@ if !$record;
    eval { write_hmac_key_file($opts{out}, $record); 1 } or die 'storage: ' . $@;

    print STDOUT "gobanftp.v1.keygen=ok\n";
    print STDOUT "profile_id=$record->{profile}\n";
    print STDOUT "algorithm=$record->{algorithm}\n";
    print STDOUT "key_id=$record->{key_id}\n";
    print STDOUT "key_path=$opts{out}\n";

    return EXIT_SUCCESS;
}

sub _command_v1_keyid {
    my (@argv) = @_;

    my $usage = 'usage: v1 keyid --fixture public-key-file';
    my %opts;

    while (@argv) {
        my $option = shift @argv;
        my ($name, $value);

        if ($option =~ /\A--([^=]+)=(.*)\z/) {
            ($name, $value) = ($1, $2);
        }
        elsif ($option =~ /\A--(.+)\z/) {
            $name = $1;
            die $usage if !@argv;
            $value = shift @argv;
        }
        else {
            die $usage;
        }

        if ($name eq 'fixture') {
            $opts{fixture} = $value;
            next;
        }

        die $usage;
    }

    die $usage if !defined($opts{fixture}) || $opts{fixture} eq '';
    _reject_control_path($opts{fixture}, $usage);

    my $text = _read_text_file($opts{fixture});
    my $record = eval { parse_public_key_record($text) };
    if (!$record) {
        my $error = _clean_error($@ || 'parse_public_key');
        print STDOUT "gobanftp.v1.keyid=failed\n";
        print STDERR _diagnostic_line({
            code  => 'parse_public_key',
            error => $error,
        }), "\n";
        return EXIT_VALIDATION;
    }

    _print_v1_keyid($record);
    return EXIT_SUCCESS;
}

sub _command_v1_trust_report {
    my (@argv) = @_;

    my $usage = 'usage: v1 trust-report --fixture fixture-dir';
    my %opts;

    while (@argv) {
        my $option = shift @argv;
        my ($name, $value);

        if ($option =~ /\A--([^=]+)=(.*)\z/) {
            ($name, $value) = ($1, $2);
        }
        elsif ($option =~ /\A--(.+)\z/) {
            $name = $1;
            die $usage if !@argv;
            $value = shift @argv;
        }
        else {
            die $usage;
        }

        if ($name eq 'fixture') {
            $opts{fixture} = $value;
            next;
        }

        die $usage;
    }

    die $usage if !defined($opts{fixture}) || $opts{fixture} eq '';
    _reject_control_path($opts{fixture}, $usage);

    my ($fixture_id, $witness, $trust) = eval {
        _v1_trust_report_from_fixture($opts{fixture});
    };
    if (!$witness) {
        my $error = _clean_error($@ || 'trust_report');
        if ($error =~ s/\A(parse_public_key|parse_trust)://) {
            my $code = $1;
            print STDOUT "gobanftp.v1.trust-report=failed\n";
            print STDERR _diagnostic_line({
                code  => $code,
                error => $error,
            }), "\n";
            return EXIT_VALIDATION;
        }
        die $error;
    }

    my $exit = _v1_witness_exit($witness);
    my $status = _status_for_exit($exit);
    _print_v1_trust_report($fixture_id, $witness, $trust, $status);
    _print_v1_witness_diagnostics($witness, []);

    return $exit;
}

sub _command_v1_attest {
    my (@argv) = @_;

    my $usage = 'usage: v1 attest --profile signed-hmac-goftp1 --key hmac-key-file --out attestations.jsonl <game-root|game-descriptor>';
    my %opts;

    while (@argv && $argv[0] =~ /\A--/) {
        my ($name, $value) = _option_value($usage, @argv);
        shift @argv;
        $value = shift @argv if !defined $value;

        if ($name eq 'profile') {
            $opts{profile_id} = $value;
            next;
        }
        if ($name eq 'key') {
            $opts{key} = $value;
            next;
        }
        if ($name eq 'out') {
            $opts{out} = $value;
            next;
        }

        die $usage;
    }

    die $usage if @argv != 1;
    die $usage if ($opts{profile_id} // '') ne 'signed-hmac-goftp1';
    die $usage if !defined($opts{key}) || $opts{key} eq '';
    die $usage if !defined($opts{out}) || $opts{out} eq '' || $opts{out} eq '-';
    _reject_control_path($opts{key}, $usage);
    _reject_control_path($opts{out}, $usage);

    my $key = eval { _read_hmac_key_file_or_die($opts{key}) };
    if (!$key) {
        my $error = _clean_error($@ || 'hmac_key');
        die $error if $error =~ /\Astorage:/;
        $error =~ s/\Aparse_hmac_key://;
        print STDOUT "gobanftp.v1.attest=failed\n";
        print STDERR _diagnostic_line({
            code  => 'parse_hmac_key',
            error => $error,
        }), "\n";
        return EXIT_VALIDATION;
    }
    die $usage if $key->{profile} ne $opts{profile_id};

    my $context = _load_context($argv[0]);
    _assert_attest_output_outside_game_root($opts{out}, $context, $usage);
    my @event_set_diagnostics = @{ $context->{event_set}{diagnostics} // [] };
    my @replay_diagnostics = _diagnostics($context->{replay_result});
    if (@event_set_diagnostics || @replay_diagnostics) {
        my $exit = @event_set_diagnostics ? EXIT_VALIDATION : _result_exit($context->{replay_result});
        print STDOUT "gobanftp.v1.attest=" . _status_for_exit($exit) . "\n";
        print STDOUT "profile_id=$opts{profile_id}\n";
        print STDOUT "game=$context->{game_descriptor}\n";
        _print_event_set_summary($context);
        _print_unique_diagnostics(@event_set_diagnostics, @replay_diagnostics);
        return $exit;
    }

    my @events = @{ $context->{event_set}{accepted_events} // [] };
    my @records = map {
        sign_event(
            profile         => $opts{profile_id},
            game_descriptor => $context->{game_descriptor},
            event_basename  => $_,
            key_id          => $key->{key_id},
            key             => $key->{secret},
        )
    } @events;

    eval { _write_jsonl_exclusive($opts{out}, \@records); 1 } or die 'storage: ' . $@;

    print STDOUT "gobanftp.v1.attest=ok\n";
    print STDOUT "profile_id=$opts{profile_id}\n";
    print STDOUT "game=$context->{game_descriptor}\n";
    print STDOUT "event_set_count=$context->{event_set}{event_count}\n";
    print STDOUT "event_set_root=$context->{event_set}{event_set_root}\n";
    print STDOUT "attestation_count=" . scalar(@records) . "\n";
    print STDOUT "key_id=$key->{key_id}\n";
    print STDOUT "attestations=$opts{out}\n";

    return EXIT_SUCCESS;
}

sub _command_v1_publish_token {
    my (@argv) = @_;

    my $usage = 'usage: v1 publish-token --profile signed-hmac-goftp1 --key hmac-key-file --out publish-token.jsonl [--key-status trusted|rotated|revoked|expired] <game-root|game-descriptor> <event-basename>';
    my %opts = (
        key_status => 'trusted',
    );

    while (@argv && $argv[0] =~ /\A--/) {
        my ($name, $value) = _option_value($usage, @argv);
        shift @argv;
        $value = shift @argv if !defined $value;

        if ($name eq 'profile') {
            $opts{profile_id} = $value;
            next;
        }
        if ($name eq 'key') {
            $opts{key} = $value;
            next;
        }
        if ($name eq 'out') {
            $opts{out} = $value;
            next;
        }
        if ($name eq 'key-status') {
            die $usage if !_is_hmac_lifecycle_status($value);
            $opts{key_status} = $value;
            next;
        }

        die $usage;
    }

    die $usage if @argv != 2;
    die $usage if ($opts{profile_id} // '') ne 'signed-hmac-goftp1';
    die $usage if !defined($opts{key}) || $opts{key} eq '';
    die $usage if !defined($opts{out}) || $opts{out} eq '' || $opts{out} eq '-';
    _reject_control_path($opts{key}, $usage);
    _reject_control_path($opts{out}, $usage);

    my $key = eval { _read_hmac_key_file_or_die($opts{key}) };
    if (!$key) {
        my $error = _clean_error($@ || 'hmac_key');
        die $error if $error =~ /\Astorage:/;
        $error =~ s/\Aparse_hmac_key://;
        print STDOUT "gobanftp.v1.publish-token=failed\n";
        print STDERR _diagnostic_line({
            code  => 'parse_hmac_key',
            error => $error,
        }), "\n";
        return EXIT_VALIDATION;
    }
    die $usage if $key->{profile} ne $opts{profile_id};

    my ($game_arg, $event) = @argv;
    my $context = eval { context_for_game_arg($game_arg, require_exists => 0) };
    die $usage if !$context;
    _assert_output_outside_existing_game_root($opts{out}, $context, $usage);

    my ($parsed_event, $parse_error) = parse_event(
        $event,
        game_descriptor => $context->{game_descriptor},
    );
    if (defined $parse_error) {
        print STDOUT "gobanftp.v1.publish-token=failed\n";
        print STDOUT 'profile_id=' . _stdout_value($opts{profile_id}) . "\n";
        print STDOUT 'game=' . _stdout_value($context->{game_descriptor}) . "\n";
        print STDOUT 'event=' . _stdout_value($event) . "\n";
        print STDOUT 'publish_auth.status=' . _stdout_value('denied') . "\n";
        print STDERR _diagnostic_line({
            code  => 'parse_event',
            name  => $event,
            error => $parse_error,
        }), "\n";
        return EXIT_VALIDATION;
    }

    my $event_id = $parsed_event->{fields}{event_id};
    my $decision = trust_lifecycle_decision(
        status  => $opts{key_status},
        purpose => 'publish',
    );
    if (!$decision->{accepted}) {
        my $diagnostic = {
            code       => 'untrusted_signature',
            profile_id => $opts{profile_id},
            name       => $event,
            event_id   => $event_id,
            key_id     => $key->{key_id},
            reason     => $decision->{reason},
        };
        print STDOUT "gobanftp.v1.publish-token=failed\n";
        _print_v1_publish_auth_fields(
            profile_id => $opts{profile_id},
            game       => $context->{game_descriptor},
            event      => $event,
            event_id   => $event_id,
            key_id     => $key->{key_id},
            status     => 'denied',
            diagnostics => [$diagnostic],
        );
        print STDERR redact_text(_diagnostic_line($diagnostic), $key->{secret}), "\n";
        return EXIT_VALIDATION;
    }

    my $token = sign_publish_token(
        profile         => $opts{profile_id},
        game_descriptor => $context->{game_descriptor},
        event_basename  => $event,
        event_id        => $event_id,
        key_id          => $key->{key_id},
        key             => $key->{secret},
    );
    eval { _write_jsonl_exclusive($opts{out}, [$token]); 1 } or die 'storage: ' . $@;

    print STDOUT "gobanftp.v1.publish-token=ok\n";
    _print_v1_publish_auth_fields(
        profile_id => $opts{profile_id},
        game       => $context->{game_descriptor},
        event      => $event,
        event_id   => $event_id,
        key_id     => $key->{key_id},
        status     => 'authorized',
        diagnostics => [],
    );
    print STDOUT "publish_token=$opts{out}\n";

    return EXIT_SUCCESS;
}

sub _command_v1_publish_auth {
    my (@argv) = @_;

    my $usage = 'usage: v1 publish-auth --profile signed-hmac-goftp1 --token publish-token.jsonl [--trusted-hmac-key id=key] [--trusted-hmac-key-file hmac-key-file] [--trusted-hmac-status id=status] <game-root|game-descriptor> <event-basename>';
    my %opts = (
        trusted_hmac_keys      => [],
        trusted_hmac_key_files => [],
        trusted_hmac_statuses  => [],
    );

    while (@argv && $argv[0] =~ /\A--/) {
        my ($name, $value) = _option_value($usage, @argv);
        shift @argv;
        $value = shift @argv if !defined $value;

        if ($name eq 'profile') {
            $opts{profile_id} = $value;
            next;
        }
        if ($name eq 'token') {
            $opts{token} = $value;
            next;
        }
        if ($name eq 'trusted-hmac-key') {
            push @{ $opts{trusted_hmac_keys} }, $value;
            next;
        }
        if ($name eq 'trusted-hmac-key-file') {
            push @{ $opts{trusted_hmac_key_files} }, $value;
            next;
        }
        if ($name eq 'trusted-hmac-status') {
            push @{ $opts{trusted_hmac_statuses} }, $value;
            next;
        }

        die $usage;
    }

    die $usage if @argv != 2;
    die $usage if ($opts{profile_id} // '') ne 'signed-hmac-goftp1';
    die $usage if !defined($opts{token}) || $opts{token} eq '';
    _reject_control_path($opts{token}, $usage);
    _reject_control_paths($opts{trusted_hmac_key_files}, $usage);

    my $token = eval { _read_publish_token_file($opts{token}) };
    if (!$token) {
        my $error = _clean_error($@ || 'publish_token');
        die $error if $error =~ /\Astorage:/;
        $error =~ s/\Aparse_publish_token://;
        print STDOUT "gobanftp.v1.publish-auth=failed\n";
        print STDERR _diagnostic_line({
            code  => 'parse_publish_token',
            error => $error,
        }), "\n";
        return EXIT_VALIDATION;
    }

    my %trusted_hmac_keys = _trusted_hmac_key_map(
        $usage,
        @{ $opts{trusted_hmac_keys} // [] },
    );
    my %trusted_hmac_file_keys = _trusted_hmac_key_file_map(
        $usage,
        @{ $opts{trusted_hmac_key_files} // [] },
    );
    for my $key_id (keys %trusted_hmac_file_keys) {
        die $usage if exists $trusted_hmac_keys{$key_id};
        $trusted_hmac_keys{$key_id} = $trusted_hmac_file_keys{$key_id};
    }
    my %trusted_hmac_key_statuses = _trusted_hmac_key_status_map(
        \%trusted_hmac_keys,
        $usage,
        @{ $opts{trusted_hmac_statuses} // [] },
    );

    my ($game_arg, $event) = @argv;
    my $context = eval { context_for_game_arg($game_arg, require_exists => 0) };
    die $usage if !$context;

    my $result = publish_authorization_result(
        profile_id                => $opts{profile_id},
        game_descriptor           => $context->{game_descriptor},
        event_basename            => $event,
        token                     => $token,
        trusted_hmac_keys         => \%trusted_hmac_keys,
        trusted_hmac_key_statuses => \%trusted_hmac_key_statuses,
    );

    my $authorized = $result->{authorized} ? 1 : 0;
    print STDOUT 'gobanftp.v1.publish-auth=' . ($authorized ? 'authorized' : 'denied') . "\n";
    _print_v1_publish_auth_fields(
        profile_id => $opts{profile_id},
        game       => $context->{game_descriptor},
        event      => $event,
        event_id   => $result->{event_id},
        key_id     => $result->{key_id},
        status     => $result->{status},
        diagnostics => $result->{diagnostics},
    );
    _print_publish_auth_diagnostics($result, [values %trusted_hmac_keys]);

    return $authorized ? EXIT_SUCCESS : EXIT_VALIDATION;
}

sub _command_v1_witness {
    my (@argv) = @_;

    my $usage = _v1_witness_usage_line();
    my %opts = (
        trusted_hmac_keys     => [],
        trusted_hmac_key_files => [],
        trusted_hmac_statuses => [],
    );

    while (@argv) {
        my $option = shift @argv;
        my ($name, $value);

        if ($option =~ /\A--([^=]+)=(.*)\z/) {
            ($name, $value) = ($1, $2);
        }
        elsif ($option =~ /\A--(.+)\z/) {
            $name = $1;
            die $usage if !@argv;
            $value = shift @argv;
        }
        else {
            die $usage;
        }

        if ($name eq 'profile') {
            $opts{profile_id} = $value;
            next;
        }
        if ($name eq 'fixture') {
            $opts{fixture} = $value;
            next;
        }
        if ($name eq 'substrate-profile') {
            die $usage if defined $opts{substrate_profile_id};
            $opts{substrate_profile_id} = $value;
            next;
        }
        if ($name eq 'attestations') {
            $opts{attestations} = $value;
            next;
        }
        if ($name eq 'trusted-hmac-key') {
            push @{ $opts{trusted_hmac_keys} }, $value;
            next;
        }
        if ($name eq 'trusted-hmac-key-file') {
            push @{ $opts{trusted_hmac_key_files} }, $value;
            next;
        }
        if ($name eq 'trusted-hmac-status') {
            push @{ $opts{trusted_hmac_statuses} }, $value;
            next;
        }
        if ($name eq 'surface') {
            die $usage if defined($opts{surface}) || $value !~ /\A(?:text|html|terminal)\z/;
            $opts{surface} = $value;
            next;
        }

        die $usage;
    }

    die $usage if !defined($opts{profile_id}) || $opts{profile_id} eq '';
    die $usage if !defined($opts{fixture}) || $opts{fixture} eq '';
    _reject_control_path($opts{fixture}, $usage);
    _reject_control_path($opts{attestations}, $usage);
    _reject_control_paths($opts{trusted_hmac_key_files}, $usage);
    die $usage
        if defined($opts{substrate_profile_id})
            && (
                $opts{profile_id} ne 'signed-hmac-goftp1'
                || !_is_v1_compare_profile($opts{substrate_profile_id})
            );

    my ($witness, $attestation_count, $trusted_key_ids, $trusted_secrets)
        = eval { _v1_witness_from_fixture(%opts) };
    if (!$witness) {
        my $error = _clean_error($@ || 'v1_witness');
        die $error if $error =~ /\Ausage:/;
        if ($error =~ s/\A(parse_hmac_key)://) {
            print STDOUT "gobanftp.v1.witness=failed\n";
            print STDERR _diagnostic_line({
                code  => $1,
                error => $error,
            }), "\n";
            return EXIT_VALIDATION;
        }
        if ($error =~ s/\A(parse_attestations)://) {
            print STDOUT "gobanftp.v1.witness=failed\n";
            print STDERR _diagnostic_line({
                code  => $1,
                error => $error,
            }), "\n";
            return EXIT_VALIDATION;
        }
        die $error;
    }
    my $exit = _v1_witness_exit($witness);
    my $status = _status_for_exit($exit);

    if (defined $opts{surface}) {
        _print_v1_witness_surface($witness, $opts{surface});
    }
    else {
        _print_v1_witness($witness, $status, $attestation_count, $trusted_key_ids);
    }
    _print_v1_witness_diagnostics($witness, $trusted_secrets);

    return $exit;
}

sub _command_v1_compare {
    my ($subcommand, @argv) = @_;

    my $usage = "usage: v1 $subcommand --fixture fixture-dir [--profiles profile-id,...] [--json]";
    my %opts;

    while (@argv) {
        my $option = shift @argv;
        my ($name, $value);

        if ($option eq '--json') {
            die $usage if $opts{json};
            $opts{json} = 1;
            next;
        }
        if ($option =~ /\A--([^=]+)=(.*)\z/) {
            ($name, $value) = ($1, $2);
        }
        elsif ($option =~ /\A--(.+)\z/) {
            $name = $1;
            die $usage if !@argv;
            $value = shift @argv;
        }
        else {
            die $usage;
        }

        if ($name eq 'fixture') {
            $opts{fixture} = $value;
            next;
        }
        if ($name eq 'profiles') {
            $opts{profiles} = $value;
            next;
        }

        die $usage;
    }

    die $usage if !defined($opts{fixture}) || $opts{fixture} eq '';
    _reject_control_path($opts{fixture}, $usage);

    my $comparison = _v1_compare_from_fixture(
        fixture => $opts{fixture},
        defined($opts{profiles}) ? (profiles => $opts{profiles}) : (),
        usage  => $usage,
        fields => _v1_compare_fields($subcommand),
    );
    my $status = @{ $comparison->{mismatch_fields} } || @{ $comparison->{invalid_profiles} }
        ? 'failed'
        : 'ok';

    if ($opts{json}) {
        _print_v1_compare_json($subcommand, $status, $comparison);
    }
    else {
        _print_v1_compare($subcommand, $status, $comparison);
    }

    return $status eq 'ok' ? EXIT_SUCCESS : EXIT_VALIDATION;
}

sub _publish_action {
    my (%args) = @_;

    my $result = _publish_action_result(%args);
    if ($args{json}) {
        _print_publish_result_json($args{command} // 'publish-move', $result);
    }
    else {
        _print_publish_result($args{command} // 'publish-move', $result);
    }

    return $result->{exit};
}

sub _publish_ack {
    my (%args) = @_;

    my $result = _publish_ack_result(%args);
    if ($args{json}) {
        _print_publish_result_json($args{command} // 'publish-ack', $result);
    }
    else {
        _print_publish_result($args{command} // 'publish-ack', $result);
    }

    return $result->{exit};
}

sub _publish_action_result {
    my (%args) = @_;

    my $context = $args{context};
    my $action  = $args{action};

    my $pre_exit = _result_exit($context->{replay_result});
    if ($pre_exit != EXIT_SUCCESS) {
        return {
            exit    => $pre_exit,
            stage   => 'preexisting',
            context => $context,
        };
    }

    my ($event_name, $event_id) = build_next_move_name(
        game_descriptor => $context->{game_descriptor},
        replay_result   => $context->{replay_result},
        action          => $action,
        defined($args{nonce}) ? (nonce => $args{nonce}) : (),
    );

    my @validation_events = sort_event_basenames(@{ $context->{events} }, $event_name);
    my $validation_result = replay(
        game_descriptor => $context->{game_descriptor},
        events          => \@validation_events,
    );
    my $validation_exit = _result_exit($validation_result);
    if ($validation_exit != EXIT_SUCCESS) {
        my $validation_context = {
            %$context,
            events        => \@validation_events,
            replay_result => $validation_result,
        };
        return {
            exit       => $validation_exit,
            stage      => 'candidate',
            context    => $validation_context,
            event_name => $event_name,
            event_id   => $event_id,
        };
    }

    my $publish_auth = _publish_auth_preflight(
        config     => $args{publish_auth},
        context    => $context,
        event_name => $event_name,
        event_id   => $event_id,
    );
    if (ref($publish_auth) eq 'HASH' && !$publish_auth->{authorized}) {
        return _publish_auth_denied_result(
            context      => $context,
            event_name   => $event_name,
            event_id     => $event_id,
            publish_auth => $publish_auth,
        );
    }

    eval {
        $context->{store}->publish_event_name($context->{store_game_root}, $event_name);
        1;
    } or die 'storage: ' . $@;

    my $after_context = _reload_context($context);
    my $after_exit = _result_exit($after_context->{replay_result});

    return {
        exit       => $after_exit,
        stage      => 'published',
        context    => $after_context,
        event_name => $event_name,
        event_id   => $event_id,
        defined($publish_auth) ? (publish_auth => $publish_auth) : (),
    };
}

sub _publish_ack_result {
    my (%args) = @_;

    my $context   = $args{context};
    my $target_id = $args{target_id};

    my $pre_exit = _result_exit($context->{replay_result});
    if ($pre_exit == EXIT_VALIDATION) {
        return {
            exit    => $pre_exit,
            stage   => 'preexisting',
            context => $context,
        };
    }

    my ($event_name, $event_id) = eval {
        build_ack_for_target(
            game_descriptor => $context->{game_descriptor},
            replay_result   => $context->{replay_result},
            target_id       => $target_id,
            defined($args{nonce}) ? (nonce => $args{nonce}) : (),
        );
    };
    if ($@) {
        my $diagnostic = _ack_target_diagnostic($target_id, $@);
        return {
            exit    => EXIT_VALIDATION,
            stage   => 'candidate',
            context => {
                %$context,
                replay_result => _result_with_diagnostic($context->{replay_result}, $diagnostic),
            },
        };
    }

    my @validation_events = sort_event_basenames(@{ $context->{events} }, $event_name);
    my $validation_result = replay(
        game_descriptor => $context->{game_descriptor},
        events          => \@validation_events,
    );
    my $validation_exit = _result_exit($validation_result);
    if ($validation_exit == EXIT_VALIDATION) {
        my $validation_context = {
            %$context,
            events        => \@validation_events,
            replay_result => $validation_result,
        };
        return {
            exit       => $validation_exit,
            stage      => 'candidate',
            context    => $validation_context,
            event_name => $event_name,
            event_id   => $event_id,
        };
    }

    my $publish_auth = _publish_auth_preflight(
        config     => $args{publish_auth},
        context    => $context,
        event_name => $event_name,
        event_id   => $event_id,
    );
    if (ref($publish_auth) eq 'HASH' && !$publish_auth->{authorized}) {
        return _publish_auth_denied_result(
            context      => $context,
            event_name   => $event_name,
            event_id     => $event_id,
            publish_auth => $publish_auth,
        );
    }

    eval {
        $context->{store}->publish_event_name($context->{store_game_root}, $event_name);
        1;
    } or die 'storage: ' . $@;

    my $after_context = _reload_context(
        $context,
        policy => $args{reload_policy} // 'conservative',
    );
    my $after_exit = _result_exit($after_context->{replay_result});

    return {
        exit       => $after_exit,
        stage      => 'published',
        context    => $after_context,
        event_name => $event_name,
        event_id   => $event_id,
        defined($publish_auth) ? (publish_auth => $publish_auth) : (),
    };
}

sub _print_publish_result {
    my ($command, $result) = @_;

    _print_summary(
        $command,
        _status_for_exit($result->{exit}),
        $result->{context},
        event_set => ($result->{stage} // '') ne 'candidate'
            && ($result->{stage} // '') ne 'auth',
    );
    _print_event_result($result);
    _print_publish_auth_result($result);
    _print_diagnostics($result->{context}{replay_result});
}

sub _print_event_result {
    my ($result) = @_;

    print STDOUT "event=$result->{event_name}\n" if defined $result->{event_name};
    print STDOUT "event_id=$result->{event_id}\n" if defined $result->{event_id};
}

sub _print_publish_auth_result {
    my ($result) = @_;

    my $auth = $result->{publish_auth};
    return if ref($auth) ne 'HASH';

    my $diagnostics = $auth->{diagnostics} // [];
    print STDOUT "publish_auth.scope=$auth->{scope}\n"
        if defined($auth->{scope});
    print STDOUT 'publish_auth.production_authorization='
        . ($auth->{production_authorization} ? 1 : 0) . "\n"
        if exists($auth->{production_authorization});
    print STDOUT "publish_auth.status=$auth->{status}\n";
    print STDOUT "publish_auth.profile_id=$auth->{profile_id}\n"
        if defined($auth->{profile_id});
    print STDOUT "publish_auth.key_id=$auth->{key_id}\n"
        if defined($auth->{key_id});
    print STDOUT 'publish_auth.diagnostic_codes='
        . _stdout_value([diagnostic_codes($diagnostics)]) . "\n";
    print STDOUT 'publish_auth.diagnostic_classes='
        . _stdout_value([diagnostic_classes($diagnostics)]) . "\n";
    print STDOUT 'publish_auth.diagnostic_count=' . scalar(@$diagnostics) . "\n";
}

sub _load_context {
    my ($game_root_arg, %opts) = @_;

    my $context = eval { context_for_game_arg($game_root_arg) };
    die 'storage: ' . $@ if !$context;

    return _reload_context($context, %opts);
}

sub _v1_witness_from_fixture {
    my (%opts) = @_;

    my $profile_id = $opts{profile_id};
    my $fixture    = $opts{fixture};
    my $game_path  = File::Spec->catfile($fixture, 'game.name');
    my $listing_profile_id = $opts{substrate_profile_id} // $profile_id;
    my $listing_path = File::Spec->catfile($fixture, $listing_profile_id, 'listing.names');

    my $game = _read_single_nonblank($game_path);
    my @raw_names = _read_nonblank_lines($listing_path);
    my @attestations = defined($opts{attestations})
        ? _read_attestations_file($opts{attestations})
        : ();
    my %trusted_hmac_keys = _trusted_hmac_key_map(@{ $opts{trusted_hmac_keys} // [] });
    my %trusted_hmac_file_keys = _trusted_hmac_key_file_map(@{ $opts{trusted_hmac_key_files} // [] });
    for my $key_id (keys %trusted_hmac_file_keys) {
        die _v1_witness_usage_line() if exists $trusted_hmac_keys{$key_id};
        $trusted_hmac_keys{$key_id} = $trusted_hmac_file_keys{$key_id};
    }
    my %trusted_hmac_key_statuses = _trusted_hmac_key_status_map(
        \%trusted_hmac_keys,
        @{ $opts{trusted_hmac_statuses} // [] },
    );

    my $witness = witness_for_listing(
        profile_id              => $profile_id,
        game_descriptor         => $game,
        raw_names               => \@raw_names,
        hmac_attestations       => \@attestations,
        trusted_hmac_keys       => \%trusted_hmac_keys,
        trusted_hmac_key_statuses => \%trusted_hmac_key_statuses,
        defined($opts{substrate_profile_id}) ? (
            substrate_profile_id => $opts{substrate_profile_id},
        ) : (),
        defined($opts{surface}) ? (include_projection_text => 1) : (),
    );

    return (
        $witness,
        scalar(@attestations),
        [sort keys %trusted_hmac_keys],
        [values %trusted_hmac_keys],
    );
}

sub _option_value {
    my ($usage, @argv) = @_;
    die $usage if !@argv || $argv[0] !~ /\A--/;

    my $option = $argv[0];
    my ($name, $value);
    if ($option =~ /\A--([^=]+)=(.*)\z/) {
        ($name, $value) = ($1, $2);
    }
    elsif ($option =~ /\A--(.+)\z/) {
        $name = $1;
        die $usage if @argv < 2;
    }
    else {
        die $usage;
    }

    die $usage if !defined($name) || $name eq '';
    return ($name, $value);
}

sub _reject_control_path {
    my ($path, $usage) = @_;

    die $usage if defined($path) && $path =~ /[\x00-\x1f\x7f]/;
    return 1;
}

sub _reject_control_paths {
    my ($paths, $usage) = @_;

    return 1 if !defined $paths;
    _reject_control_path($_, $usage) for @$paths;
    return 1;
}

sub _publish_move_usage_line {
    return 'usage: publish-move [--json] [--nonce n] ' . _publish_auth_usage_suffix()
        . ' <game-root|game-descriptor> <aa|play-aa|pass|resign>';
}

sub _publish_ack_usage_line {
    return 'usage: publish-ack [--json] [--nonce n] ' . _publish_auth_usage_suffix()
        . ' <game-root|game-descriptor> <event-id>';
}

sub _play_usage_line {
    return 'usage: play [--once|--live|--tui] [--count n|--max-polls n] [--interval seconds] [--move move|--ack event-id] [--nonce n] '
        . _publish_auth_usage_suffix()
        . ' <game-root|game-descriptor>';
}

sub _watch_usage_line {
    return 'usage: watch [--live] [--compact] [--once] [--count n|--max-polls n] [--interval seconds] <game-root|game-descriptor>';
}

sub _showcase_usage_line {
    return 'usage: showcase --out dir [--json] | showcase preview --dir dir [--port n|0] [--once]';
}

sub _publish_auth_usage_suffix {
    return '[--publish-auth-token publish-token.jsonl] '
        . '[--publish-auth-profile signed-hmac-goftp1] '
        . '[--publish-auth-trusted-hmac-key id=key] '
        . '[--publish-auth-trusted-hmac-key-file hmac-key-file] '
        . '[--publish-auth-trusted-hmac-status id=status]';
}

sub _publish_auth_default_opts {
    return (
        publish_auth_trusted_hmac_keys      => [],
        publish_auth_trusted_hmac_key_files => [],
        publish_auth_trusted_hmac_statuses  => [],
    );
}

sub _consume_publish_auth_option {
    my ($option, $argv, $opts, $usage) = @_;

    my ($name, $value);
    if ($option =~ /\A--([^=]+)=(.*)\z/) {
        ($name, $value) = ($1, $2);
    }
    elsif ($option =~ /\A--(.+)\z/) {
        $name = $1;
    }
    else {
        return 0;
    }

    return 0 if !_is_publish_auth_option($name);
    if (!defined $value) {
        die $usage if !@$argv;
        $value = shift @$argv;
    }
    die $usage if !defined($value) || $value eq '';

    if ($name eq 'publish-auth-profile') {
        die $usage if defined $opts->{publish_auth_profile};
        $opts->{publish_auth_profile} = $value;
        return 1;
    }
    if ($name eq 'publish-auth-token') {
        die $usage if defined $opts->{publish_auth_token};
        _reject_control_path($value, $usage);
        $opts->{publish_auth_token} = $value;
        return 1;
    }
    if ($name eq 'publish-auth-trusted-hmac-key') {
        push @{ $opts->{publish_auth_trusted_hmac_keys} }, $value;
        return 1;
    }
    if ($name eq 'publish-auth-trusted-hmac-key-file') {
        _reject_control_path($value, $usage);
        push @{ $opts->{publish_auth_trusted_hmac_key_files} }, $value;
        return 1;
    }
    if ($name eq 'publish-auth-trusted-hmac-status') {
        push @{ $opts->{publish_auth_trusted_hmac_statuses} }, $value;
        return 1;
    }

    return 0;
}

sub _is_publish_auth_option {
    my ($name) = @_;
    return defined($name) && (
        $name eq 'publish-auth-profile'
            || $name eq 'publish-auth-token'
            || $name eq 'publish-auth-trusted-hmac-key'
            || $name eq 'publish-auth-trusted-hmac-key-file'
            || $name eq 'publish-auth-trusted-hmac-status'
    );
}

sub _publish_auth_config_or_usage {
    my ($opts, $usage) = @_;

    my $enabled = defined($opts->{publish_auth_profile})
        || defined($opts->{publish_auth_token})
        || @{ $opts->{publish_auth_trusted_hmac_keys} // [] }
        || @{ $opts->{publish_auth_trusted_hmac_key_files} // [] }
        || @{ $opts->{publish_auth_trusted_hmac_statuses} // [] };
    return undef if !$enabled;

    my $profile_id = $opts->{publish_auth_profile} // 'signed-hmac-goftp1';
    die $usage if $profile_id ne 'signed-hmac-goftp1';
    die $usage if !defined($opts->{publish_auth_token})
        || $opts->{publish_auth_token} eq '';
    die $usage
        if !@{ $opts->{publish_auth_trusted_hmac_keys} // [] }
            && !@{ $opts->{publish_auth_trusted_hmac_key_files} // [] };

    return {
        usage                  => $usage,
        profile_id             => $profile_id,
        token_path             => $opts->{publish_auth_token},
        trusted_hmac_keys      => [ @{ $opts->{publish_auth_trusted_hmac_keys} // [] } ],
        trusted_hmac_key_files => [ @{ $opts->{publish_auth_trusted_hmac_key_files} // [] } ],
        trusted_hmac_statuses  => [ @{ $opts->{publish_auth_trusted_hmac_statuses} // [] } ],
    };
}

sub _publish_auth_preflight {
    my (%args) = @_;

    my $config = $args{config};
    return undef if ref($config) ne 'HASH';

    my $profile_id = $config->{profile_id};
    my $context    = $args{context};
    my $event_name = $args{event_name};
    my $event_id   = $args{event_id};

    my $token = eval { _read_publish_token_file($config->{token_path}) };
    if (!$token) {
        my $error = _clean_error($@ || 'publish_token');
        die $error if $error =~ /\Astorage:/;
        $error =~ s/\Aparse_publish_token://;
        return _publish_auth_failure(
            profile_id => $profile_id,
            event_name => $event_name,
            event_id   => $event_id,
            diagnostic => {
                code  => 'parse_publish_token',
                error => $error,
            },
        );
    }

    my (%trusted_hmac_keys, %trusted_hmac_key_statuses);
    my $loaded = eval {
        %trusted_hmac_keys = _trusted_hmac_key_map(
            $config->{usage},
            @{ $config->{trusted_hmac_keys} // [] },
        );
        my %trusted_hmac_file_keys = _trusted_hmac_key_file_map(
            $config->{usage},
            @{ $config->{trusted_hmac_key_files} // [] },
        );
        for my $key_id (keys %trusted_hmac_file_keys) {
            die $config->{usage} if exists $trusted_hmac_keys{$key_id};
            $trusted_hmac_keys{$key_id} = $trusted_hmac_file_keys{$key_id};
        }
        %trusted_hmac_key_statuses = _trusted_hmac_key_status_map(
            \%trusted_hmac_keys,
            $config->{usage},
            @{ $config->{trusted_hmac_statuses} // [] },
        );
        1;
    };
    if (!$loaded) {
        my $error = _clean_error($@ || 'hmac_key');
        die $error if $error =~ /\Ausage:/;
        if ($error =~ s/\Aparse_hmac_key://) {
            return _publish_auth_failure(
                profile_id => $profile_id,
                event_name => $event_name,
                event_id   => $event_id,
                diagnostic => {
                    code  => 'parse_hmac_key',
                    error => $error,
                },
            );
        }
        die $error;
    }

    my $auth = publish_authorization_result(
        profile_id                => $profile_id,
        game_descriptor           => $context->{game_descriptor},
        event_basename            => $event_name,
        token                     => $token,
        trusted_hmac_keys         => \%trusted_hmac_keys,
        trusted_hmac_key_statuses => \%trusted_hmac_key_statuses,
    );

    return _decorate_publish_auth_result(
        $auth,
        profile_id => $profile_id,
        event_name => $event_name,
        event_id   => $event_id,
        secrets    => [values %trusted_hmac_keys],
    );
}

sub _publish_auth_failure {
    my (%args) = @_;

    return _decorate_publish_auth_result(
        {
            authorized  => 0,
            status      => 'denied',
            diagnostics => [$args{diagnostic}],
        },
        %args,
    );
}

sub _decorate_publish_auth_result {
    my ($auth, %args) = @_;

    my $scope = publish_preflight_scope();
    $auth->{scope} = $scope->{scope};
    $auth->{production_authorization} = $scope->{production_authorization};
    $auth->{profile_id} = $args{profile_id};
    $auth->{event_name} = $args{event_name};
    $auth->{event_id} //= $args{event_id};
    $auth->{secrets} = $args{secrets} // [];

    return $auth;
}

sub _publish_auth_denied_result {
    my (%args) = @_;

    my $context = $args{context};
    my $auth    = $args{publish_auth};
    my $result  = _result_with_diagnostics(
        $context->{replay_result},
        @{ $auth->{diagnostics} // [] },
    );

    return {
        exit         => EXIT_VALIDATION,
        stage        => 'auth',
        context      => {
            %$context,
            replay_result => $result,
        },
        event_name   => $args{event_name},
        event_id     => $args{event_id},
        publish_auth => $auth,
    };
}

sub _v1_trust_report_from_fixture {
    my ($fixture) = @_;

    my $game = _read_single_nonblank(File::Spec->catfile($fixture, 'game.name'));
    my @raw_names = _read_nonblank_lines(File::Spec->catfile($fixture, 'listing.names'));
    my $witness = witness_for_listing(
        profile_id      => 'local-goftp1',
        game_descriptor => $game,
        raw_names       => \@raw_names,
    );

    my @public_keys = _v1_public_keys_from_fixture($fixture);
    my $trust_path = File::Spec->catfile($fixture, 'trust.tsv');
    my $trust_tsv = -e $trust_path ? _read_text_file($trust_path) : undef;
    my $trust = eval {
        trust_report_summary(
            public_keys => \@public_keys,
            defined($trust_tsv) ? (trust_tsv => $trust_tsv) : (),
        );
    };
    if (!$trust) {
        my $error = _clean_error($@ || 'parse_trust');
        die $error =~ /\Aparse_/ ? $error : "parse_trust:$error";
    }

    return (_safe_fixture_id($fixture), $witness, $trust);
}

sub _v1_public_keys_from_fixture {
    my ($fixture) = @_;

    my $keys_dir = File::Spec->catdir($fixture, 'keys');
    return () if !-e $keys_dir;
    die "storage: $keys_dir is not a directory" if !-d $keys_dir;

    opendir my $dh, $keys_dir or die "storage: opendir $keys_dir: $!";
    my @files = sort grep { /[.]pub\z/ } readdir $dh;
    closedir $dh or die "storage: closedir $keys_dir: $!";

    my @public_keys;
    for my $file (@files) {
        my $path = File::Spec->catfile($keys_dir, $file);
        my $record = eval { parse_public_key_record(_read_text_file($path)) };
        if (!$record) {
            my $error = _clean_error($@ || 'parse_public_key');
            die "parse_public_key:$error";
        }
        push @public_keys, $record;
    }

    return @public_keys;
}

sub _v1_compare_from_fixture {
    my (%opts) = @_;

    my $fixture = $opts{fixture};
    my @profiles = exists($opts{profiles})
        ? _v1_compare_profiles_from_option($opts{profiles}, $opts{usage})
        : _v1_compare_profiles_from_fixture($fixture);
    die "storage: $fixture has no profile listing directories" if !@profiles;

    my $game = _read_single_nonblank(File::Spec->catfile($fixture, 'game.name'));
    my %witnesses;
    for my $profile (@profiles) {
        my @raw_names = _read_nonblank_lines(
            File::Spec->catfile($fixture, $profile, 'listing.names'),
        );
        $witnesses{$profile} = witness_for_listing(
            profile_id      => $profile,
            game_descriptor => $game,
            raw_names       => \@raw_names,
        );
    }

    my @fields = @{ $opts{fields} // [] };
    my $baseline_profile = grep({ $_ eq 'local-goftp1' } @profiles)
        ? 'local-goftp1'
        : $profiles[0];
    my %mismatch_field;
    my %mismatch_profile;
    my %invalid_profile;
    for my $field (@fields) {
        my $baseline = _stdout_value($witnesses{$baseline_profile}{$field});
        for my $profile (@profiles) {
            my $got = _stdout_value($witnesses{$profile}{$field});
            next if $got eq $baseline;
            $mismatch_field{$field} = 1;
            $mismatch_profile{$profile} = 1;
        }
    }
    for my $profile (@profiles) {
        my $witness = $witnesses{$profile};
        my %diagnostic_code = map { $_ => 1 } @{ $witness->{diagnostic_codes} // [] };
        $invalid_profile{$profile} = 1
            if !defined($witness->{event_set_root})
                || $witness->{event_set_root} eq ''
                || $diagnostic_code{parse_game_descriptor};
    }

    return {
        fixture          => $fixture,
        fixture_id       => _safe_fixture_id($fixture),
        game_descriptor  => $game,
        profiles         => \@profiles,
        baseline_profile => $baseline_profile,
        fields           => \@fields,
        mismatch_fields  => [sort keys %mismatch_field],
        mismatch_profiles => [sort keys %mismatch_profile],
        invalid_profiles => [grep { $invalid_profile{$_} } @profiles],
        witnesses        => \%witnesses,
    };
}

sub _v1_compare_fields {
    my ($subcommand) = @_;

    return [qw(event_set_root)] if $subcommand eq 'compare-roots';
    return [qw(
        ruleset_id
        ruleset_semver
        ruleset_seal_version
        ruleset_fixture_digest
        ruleset_seal
        event_set_root
        accepted_count
        accepted_events
        rejected_count
        rejected_codes
        rejected_classes
        replay_status
        canonical_tip
        canonical_ids
        legal_ids
        board_hash
        sgf_hash
        variations_sgf_hash
        diagnostic_codes
        diagnostic_classes
        diagnostic_count
    )] if $subcommand eq 'compare-replay';

    croak "unsupported v1 compare command: $subcommand";
}

sub _v1_compare_profiles_from_option {
    my ($value, $usage) = @_;
    $usage //= 'usage: v1 compare-roots --fixture fixture-dir [--profiles profile-id,...]';

    my @profiles = split /,/, $value // '', -1;
    die $usage
        if !@profiles
            || grep { $_ eq '' || !_is_public_token($_) || !_is_v1_compare_profile($_) } @profiles;

    my %seen;
    for my $profile (@profiles) {
        die $usage if $seen{$profile}++;
    }

    return @profiles;
}

sub _v1_compare_profiles_from_fixture {
    my ($fixture) = @_;

    my @profiles = grep {
        -f File::Spec->catfile($fixture, $_, 'listing.names')
    } @V1_COMPARE_DEFAULT_PROFILES;

    return @profiles;
}

sub _safe_fixture_id {
    my ($fixture) = @_;

    my $id = basename($fixture);
    return $id if _is_public_token($id) && !contains_redactable_secret($id);
    return 'REDACTED';
}

sub _is_v1_compare_profile {
    my ($profile_id) = @_;
    return known_profile($profile_id)
        && grep({ $_ eq $profile_id } @V1_COMPARE_DEFAULT_PROFILES) ? 1 : 0;
}

sub _read_single_nonblank {
    my ($path) = @_;

    my @lines = _read_nonblank_lines($path);
    die "storage: $path must contain exactly one nonblank line" if @lines != 1;
    return $lines[0];
}

sub _read_nonblank_lines {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "storage: open $path: $!";
    my @lines;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /\A\s*\z/;
        push @lines, $line;
    }
    close $fh or die "storage: close $path: $!";

    return @lines;
}

sub _read_jsonl_file {
    my ($path, %opts) = @_;

    my $max_file_bytes = $opts{max_file_bytes} // JSONL_MAX_FILE_BYTES;
    my $max_line_bytes = $opts{max_line_bytes} // JSONL_MAX_LINE_BYTES;
    my $max_records    = $opts{max_records}    // JSONL_MAX_RECORDS;

    my $size = -s $path;
    die 'file.too_large' if defined($size) && $size > $max_file_bytes;

    open my $fh, '<:encoding(UTF-8)', $path or die "storage: open $path: $!";
    my @rows;
    while (my $line = <$fh>) {
        chomp $line;
        die 'line.too_long' if length($line) > $max_line_bytes;
        next if $line =~ /\A\s*\z/;
        die 'record_count' if @rows >= $max_records;
        push @rows, decode_json($line);
    }
    close $fh or die "storage: close $path: $!";

    return @rows;
}

sub _read_attestations_file {
    my ($path) = @_;

    my @rows = eval { _read_jsonl_file($path) };
    if ($@) {
        my $error = _clean_error($@);
        die $error if $error =~ /\Astorage:/;
        die "parse_attestations:$error";
    }

    for my $index (0 .. $#rows) {
        die "parse_attestations:record.$index" if ref($rows[$index]) ne 'HASH';
    }

    return @rows;
}

sub _read_text_file {
    my ($path) = @_;

    open my $fh, '<:encoding(UTF-8)', $path or die "storage: open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "storage: close $path: $!";

    return $text;
}

sub _write_jsonl_exclusive {
    my ($path, $rows) = @_;

    my $fh;
    sysopen $fh, $path, O_WRONLY | O_CREAT | O_EXCL, 0600
        or die "create $path: $!";
    binmode $fh, ':encoding(UTF-8)';

    my $json = JSON::PP->new->canonical(1);
    for my $row (@$rows) {
        print {$fh} $json->encode($row), "\n";
    }

    close $fh or die "close $path: $!";
    return 1;
}

sub _read_hmac_key_file_or_die {
    my ($path) = @_;

    my $record = eval { read_hmac_key_file($path) };
    return $record if $record;

    my $error = _clean_error($@ || 'hmac_key');
    die "storage: $error" if $error =~ /\A(?:stat|open|close)\s/;
    die "parse_hmac_key:$error";
}

sub _read_publish_token_file {
    my ($path) = @_;

    my @rows = eval { _read_jsonl_file($path) };
    if ($@) {
        my $error = _clean_error($@);
        die $error if $error =~ /\Astorage:/;
        die "parse_publish_token:$error";
    }

    die 'parse_publish_token:record_count' if @rows != 1;
    die 'parse_publish_token:record' if ref($rows[0]) ne 'HASH';
    return $rows[0];
}

sub _assert_attest_output_outside_game_root {
    my ($path, $context, $usage) = @_;

    return if ($context->{store_kind} // '') ne 'local';
    die $usage if !defined($path) || $path eq '';

    my $game_root = abs_path($context->{game_root});
    die "storage: game root does not exist: $context->{game_root}" if !defined $game_root;

    my $parent = dirname(File::Spec->rel2abs($path));
    my $parent_abs = abs_path($parent);
    die "storage: output parent does not exist: $parent" if !defined $parent_abs;

    my $target_abs = File::Spec->catfile($parent_abs, basename($path));
    die $usage if _path_is_inside_or_same($target_abs, $game_root);
    return 1;
}

sub _assert_output_outside_existing_game_root {
    my ($path, $context, $usage) = @_;

    return if ($context->{store_kind} // '') ne 'local';
    die $usage if !defined($path) || $path eq '';

    my $game_root = abs_path($context->{game_root});
    return 1 if !defined $game_root;

    my $parent = dirname(File::Spec->rel2abs($path));
    my $parent_abs = abs_path($parent);
    die "storage: output parent does not exist: $parent" if !defined $parent_abs;

    my $target_abs = File::Spec->catfile($parent_abs, basename($path));
    die $usage if _path_is_inside_or_same($target_abs, $game_root);
    return 1;
}

sub _path_is_inside_or_same {
    my ($path, $root) = @_;

    my ($volume_path, $dir_path, $file_path) = File::Spec->splitpath($path);
    my ($volume_root, $dir_root) = File::Spec->splitpath($root, 1);
    $volume_path //= '';
    $volume_root //= '';
    return 0 if $volume_path ne $volume_root;

    my @path_parts = grep { $_ ne '' } File::Spec->splitdir(File::Spec->catdir($dir_path, $file_path));
    my @root_parts = grep { $_ ne '' } File::Spec->splitdir($dir_root);
    return 0 if @path_parts < @root_parts;

    for my $i (0 .. $#root_parts) {
        return 0 if $path_parts[$i] ne $root_parts[$i];
    }

    return 1;
}

sub _trusted_hmac_key_map {
    my $usage = @_ && defined($_[0]) && !ref($_[0]) && $_[0] =~ /\Ausage:/
        ? shift
        : _v1_witness_usage_line();
    my (@records) = @_;

    my %keys;
    my @secret_values;
    for my $record (@records) {
        die $usage
            if !defined($record) || $record !~ /\A([^=]+)=(.+)\z/;
        my ($key_id, $key) = ($1, $2);
        die $usage
            if !_is_public_token($key_id)
                || $key_id =~ /\Ak1[.]/
                || exists $keys{$key_id}
                || $key_id eq $key;
        $keys{$key_id} = $key;
        push @secret_values, $key;
    }

    for my $key_id (keys %keys) {
        die $usage
            if grep { index($key_id, $_) >= 0 } @secret_values;
    }

    return %keys;
}

sub _trusted_hmac_key_file_map {
    my $usage = @_ && defined($_[0]) && !ref($_[0]) && $_[0] =~ /\Ausage:/
        ? shift
        : _v1_witness_usage_line();
    my (@paths) = @_;

    my %keys;
    for my $path (@paths) {
        die $usage if !defined($path) || $path eq '';
        my $record = _read_hmac_key_file_or_die($path);
        die $usage
            if exists $keys{ $record->{key_id} };
        $keys{ $record->{key_id} } = $record->{secret};
    }

    return %keys;
}

sub _trusted_hmac_key_status_map {
    my ($keys, @records) = @_;
    my $usage = @records && defined($records[0]) && !ref($records[0]) && $records[0] =~ /\Ausage:/
        ? shift @records
        : _v1_witness_usage_line();

    my %statuses;
    for my $record (@records) {
        die $usage
            if !defined($record) || $record !~ /\A([^=]+)=(.+)\z/;
        my ($key_id, $status) = ($1, $2);
        die $usage
            if !_is_public_token($key_id)
                || $key_id =~ /\Ak1[.]/
                || !exists $keys->{$key_id}
                || exists $statuses{$key_id}
                || !_is_hmac_lifecycle_status($status);
        $statuses{$key_id} = $status;
    }

    return %statuses;
}

sub _is_hmac_lifecycle_status {
    my ($status) = @_;
    return defined($status) && $status =~ /\A(?:trusted|rotated|revoked|expired)\z/;
}

sub _reload_context {
    my ($context, %opts) = @_;

    my @events = eval { normalize_listing($context->{store}->list_names("$context->{store_game_root}/events")) };
    die 'storage: ' . $@ if $@;

    my $result = replay(
        game_descriptor => $context->{game_descriptor},
        events          => \@events,
        defined($opts{policy}) ? (policy => $opts{policy}) : (),
    );
    my $event_set = event_set_root_result(
        game_descriptor => $context->{game_descriptor},
        names           => \@events,
    );

    return {
        %$context,
        events        => \@events,
        event_set     => $event_set,
        replay_result => $result,
    };
}

sub _ack_target_diagnostic {
    my ($target_id, $error) = @_;

    chomp $error;
    $error = _clean_error($error);

    my $reason = $error eq 'ack.target'       ? 'unknown'
        : $error eq 'ack.target_move'        ? 'not_move'
        : $error eq 'ack.target_legal'       ? 'not_legal'
        :                                      'invalid';

    return {
        code      => 'ack_target_invalid',
        target_id => $target_id,
        reason    => $reason,
        error     => $error,
    };
}

sub _result_with_diagnostic {
    my ($result, $diagnostic) = @_;

    return {
        policy                   => ref($result) && eval { $result->can('policy') } ? $result->policy : 'conservative',
        diagnostics              => [ _diagnostics($result), $diagnostic ],
        canonical_ids            => [ _canonical_ids($result) ],
        legal_ids                => [ _legal_ids($result) ],
        illegal_by_id            => ref($result) && eval { $result->can('illegal_by_id') } ? $result->illegal_by_id : {},
        fork                     => _fork($result),
        final_state              => _final_state($result),
        game                     => _game($result),
        events_by_id             => ref($result) && eval { $result->can('events_by_id') } ? $result->events_by_id : {},
        names_by_id              => ref($result) && eval { $result->can('names_by_id') } ? $result->names_by_id : {},
        canonical_steps          => ref($result) && eval { $result->can('canonical_steps') } ? [ $result->canonical_steps ] : [],
        legal_children_by_parent => ref($result) && eval { $result->can('legal_children_by_parent') } ? $result->legal_children_by_parent : {},
        ack_ids_by_target        => ref($result) && eval { $result->can('ack_ids_by_target') } ? $result->ack_ids_by_target : {},
        ack_assisted_choices     => ref($result) && eval { $result->can('ack_assisted_choices') } ? [ $result->ack_assisted_choices ] : [],
    };
}

sub _result_with_diagnostics {
    my ($result, @diagnostics) = @_;

    my $combined = $result;
    for my $diagnostic (@diagnostics) {
        $combined = _result_with_diagnostic($combined, $diagnostic);
    }

    return $combined;
}

sub _require_local_store_for_write {
    my ($message) = @_;

    my $mode = eval { store_mode() };
    die 'storage: ' . $@ if !$mode;
    die "storage: $message" if $mode ne 'local';

    return 1;
}

sub _print_config_summary {
    my ($summary) = @_;

    my $status = $summary->{status} // 'ok';
    print STDOUT 'gobanftp.config.show=' . _stdout_value($status) . "\n";
    print STDOUT 'schema=' . _stdout_value($summary->{schema}) . "\n";
    print STDOUT 'version=' . _stdout_value($summary->{version}) . "\n";
    print STDOUT 'store_mode=' . _stdout_value($summary->{store_mode}) . "\n";
    print STDOUT 'requested_store_mode=' . _stdout_value($summary->{requested_store_mode}) . "\n"
        if defined $summary->{requested_store_mode};
    print STDOUT 'missing_required_env=' . _stdout_value($summary->{missing_required_env} // []) . "\n";
    _print_capability_lines('capability', $summary->{capabilities});
    _print_env_summary($summary->{env});
    _print_config_diagnostics($summary->{diagnostics});
}

sub _print_doctor_report {
    my ($report) = @_;

    print STDOUT 'gobanftp.doctor=' . _stdout_value($report->{status}) . "\n";
    print STDOUT 'schema=' . _stdout_value($report->{schema}) . "\n";
    print STDOUT 'version=' . _stdout_value($report->{version}) . "\n";
    print STDOUT 'dry_run=' . _stdout_value($report->{dry_run}) . "\n";
    print STDOUT 'connect_requested=' . _stdout_value($report->{connect_requested}) . "\n";
    print STDOUT 'store_mode=' . _stdout_value($report->{store_mode}) . "\n";
    print STDOUT 'requested_store_mode=' . _stdout_value($report->{requested_store_mode}) . "\n"
        if defined $report->{requested_store_mode};
    print STDOUT 'missing_required_env=' . _stdout_value($report->{missing_required_env} // []) . "\n";
    _print_capability_lines('capability', $report->{capabilities});
    for my $check (@{ $report->{checks} // [] }) {
        my $name = $check->{name} // '';
        next if $name !~ /\A[A-Za-z0-9_.-]+\z/;
        print STDOUT "check.$name=" . _stdout_value($check->{status}) . "\n";
        print STDOUT "check.$name.code=" . _stdout_value($check->{code}) . "\n"
            if defined($check->{code}) && $check->{code} ne '';
        print STDOUT "check.$name.detail=" . _stdout_value($check->{detail}) . "\n"
            if defined($check->{detail}) && $check->{detail} ne '';
    }
    _print_config_diagnostics($report->{diagnostics});
}

sub _print_capability_lines {
    my ($prefix, $capabilities) = @_;

    return if ref($capabilities) ne 'HASH';
    for my $key (qw(store_mode can_read_events can_publish can_mkdir read_only network_required projection_write)) {
        next if !exists $capabilities->{$key};
        print STDOUT "$prefix.$key=" . _stdout_value($capabilities->{$key}) . "\n";
    }
}

sub _print_env_summary {
    my ($env) = @_;

    for my $row (@{ $env // [] }) {
        next if ref($row) ne 'HASH';
        my $name = $row->{name};
        next if !defined $name;
        next if $name !~ /\A[A-Z0-9_]+\z/;
        print STDOUT "env.$name.selected=" . _stdout_value($row->{selected}) . "\n";
        print STDOUT "env.$name.set=" . _stdout_value($row->{set}) . "\n";
        print STDOUT "env.$name.value=" . _stdout_value($row->{value}) . "\n"
            if defined $row->{value};
    }
}

sub _print_config_diagnostics {
    my ($diagnostics) = @_;

    for my $diagnostic (@{ $diagnostics // [] }) {
        next if ref($diagnostic) ne 'HASH';
        my $code = $diagnostic->{code} // '';
        next if $code !~ /\A[A-Za-z0-9_.-]+\z/;
        print STDOUT "diagnostic.$code=failed\n";
        print STDOUT "diagnostic.$code.detail=" . _stdout_value($diagnostic->{message}) . "\n"
            if defined($diagnostic->{message}) && $diagnostic->{message} ne '';
    }
}

sub _print_publish_result_json {
    my ($command, $result) = @_;

    my $context = $result->{context} // {};
    my $exit = 0 + ($result->{exit} // EXIT_INTERNAL);
    print STDOUT encode_json_doc(
        schema        => 'gobanftp.publish.result.v1',
        command       => $command,
        status        => _status_for_exit($exit),
        exit          => $exit,
        stage         => $result->{stage} // 'unknown',
        game          => $context->{game_descriptor},
        store_mode    => $context->{store_kind},
        capabilities  => store_capabilities($context->{store_kind} // store_mode()),
        event         => $result->{event_name},
        event_id      => $result->{event_id},
        event_set     => _publish_result_event_set_json($result),
        replay        => _replay_summary_json($context->{replay_result}),
        publish_state => _publish_state_json($result),
        publish_auth  => _publish_auth_json($result->{publish_auth}),
        diagnostics   => _diagnostics_json(
            [ _diagnostics($context->{replay_result}) ],
            ref($result->{publish_auth}) eq 'HASH' ? $result->{publish_auth}{secrets} : [],
        ),
    );
}

sub _publish_result_event_set_json {
    my ($result) = @_;

    my $stage = $result->{stage} // '';
    return {
        available => 0,
        reason    => 'unpublished-candidate',
    } if $stage eq 'candidate' || $stage eq 'auth';

    my $event_set = $result->{context}{event_set};
    return { available => 0, reason => 'not-computed' } if ref($event_set) ne 'HASH';

    return {
        available => 1,
        count     => 0 + ($event_set->{event_count} // 0),
        exists($event_set->{event_set_root}) ? (root => $event_set->{event_set_root}) : (),
    };
}

sub _publish_state_json {
    my ($result) = @_;

    my $stage = $result->{stage} // '';
    my $auth = ref($result->{publish_auth}) eq 'HASH' ? $result->{publish_auth} : undef;
    my $event_name = $result->{event_name};
    my %visible = map { $_ => 1 } @{ $result->{context}{events} // [] };

    return {
        preexisting_replay => $stage eq 'preexisting'
            ? _status_for_exit($result->{exit} // EXIT_INTERNAL)
            : 'ok',
        candidate_built => defined($event_name) ? 1 : 0,
        candidate_replay => $stage eq 'candidate'
            ? 'failed'
            : defined($event_name) ? 'ok' : 'not_built',
        auth_preflight => !defined($auth)
            ? 'not_requested'
            : $auth->{authorized} ? 'authorized' : 'denied',
        store_write => $stage eq 'published' ? 'attempted' : 'not_attempted',
        visibility => $stage eq 'published'
            ? (defined($event_name) && $visible{$event_name} ? 'confirmed' : 'unconfirmed')
            : 'not_checked',
        post_publish_replay => $stage eq 'published'
            ? _status_for_exit($result->{exit} // EXIT_INTERNAL)
            : 'not_available',
    };
}

sub _publish_auth_json {
    my ($auth) = @_;

    my $scope = publish_preflight_scope();
    return {
        enabled                  => 0,
        scope                    => $scope->{scope},
        production_authorization => 0,
    } if ref($auth) ne 'HASH';

    return {
        enabled                  => 1,
        scope                    => $auth->{scope} // $scope->{scope},
        production_authorization => $auth->{production_authorization} ? 1 : 0,
        authorized               => $auth->{authorized} ? 1 : 0,
        status                   => $auth->{status},
        profile_id               => $auth->{profile_id},
        key_id                   => $auth->{key_id},
        event_id                 => $auth->{event_id},
        diagnostic_codes         => [diagnostic_codes($auth->{diagnostics} // [])],
        diagnostic_classes       => [diagnostic_classes($auth->{diagnostics} // [])],
        diagnostic_count         => 0 + scalar(@{ $auth->{diagnostics} // [] }),
    };
}

sub _replay_summary_json {
    my ($result) = @_;

    my $exit = _result_exit($result);
    my @diagnostics = _diagnostics($result);
    return {
        status             => _status_for_exit($exit),
        canonical_ids      => [_canonical_ids($result)],
        legal_ids          => [_legal_ids($result)],
        diagnostic_codes   => [diagnostic_codes(\@diagnostics)],
        diagnostic_classes => [diagnostic_classes(\@diagnostics)],
        diagnostic_count   => 0 + scalar(@diagnostics),
    };
}

sub _diagnostics_json {
    my ($diagnostics, $secrets) = @_;

    my @rows;
    for my $diagnostic (@{ $diagnostics // [] }) {
        next if ref($diagnostic) ne 'HASH';
        my %row;
        for my $key (sort keys %$diagnostic) {
            my $value = $diagnostic->{$key};
            if (ref($value) eq 'ARRAY') {
                $row{$key} = [map { _diagnostic_token($_, $secrets) } @$value];
            }
            elsif (!ref($value)) {
                $row{$key} = _diagnostic_token($value, $secrets);
            }
        }
        push @rows, \%row;
    }

    return \@rows;
}

sub _print_v1_compare_json {
    my ($subcommand, $status, $comparison) = @_;

    my %witnesses = map {
        $_ => _witness_compare_json($comparison->{witnesses}{$_})
    } @{ $comparison->{profiles} // [] };

    print STDOUT encode_json_doc(
        schema             => "gobanftp.$subcommand.v1",
        command            => "v1 $subcommand",
        status             => $status,
        comparison_scope   => 'fixture-read-normalizer',
        fixture_id         => $comparison->{fixture_id},
        game_descriptor    => $comparison->{game_descriptor},
        profiles           => $comparison->{profiles},
        baseline_profile   => $comparison->{baseline_profile},
        compared_fields    => $comparison->{fields},
        mismatch_fields    => $comparison->{mismatch_fields},
        mismatch_profiles  => $comparison->{mismatch_profiles},
        invalid_profiles   => $comparison->{invalid_profiles},
        witnesses          => \%witnesses,
    );
}

sub _witness_compare_json {
    my ($witness) = @_;

    my %row;
    for my $field (qw(
        profile_id
        adapter_id
        substrate_profile_id
        substrate_adapter_id
        game_descriptor
        raw_count
        normalized_count
        accepted_count
        rejected_count
        event_set_root
        replay_status
        canonical_tip
        diagnostic_count
        board_hash
        sgf_hash
        variations_sgf_hash
    )) {
        $row{$field} = $witness->{$field} if exists $witness->{$field};
    }
    for my $field (qw(
        normalized_events
        accepted_events
        rejected_codes
        rejected_classes
        canonical_ids
        legal_ids
        diagnostic_codes
        diagnostic_classes
    )) {
        $row{$field} = $witness->{$field} if exists $witness->{$field};
    }

    return \%row;
}

sub _showcase_expected_files {
    return expected_files();
}

sub _prepare_showcase_out_dir {
    my ($out_abs, $files) = @_;

    if (!-e $out_abs) {
        make_path($out_abs);
        die "storage: $out_abs is not a directory" if !-d $out_abs;
        return undef;
    }

    die "storage: $out_abs is not a directory" if !-d $out_abs;

    opendir my $dh, $out_abs or die "storage: opendir $out_abs: $!";
    my @entries = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh or die "storage: closedir $out_abs: $!";

    my %expected = map { $_ => 1 } @{ $files // [] };
    my @extra = grep { !$expected{$_} } @entries;
    return _showcase_out_dir_not_clean('output directory contains unexpected files') if @extra;

    for my $entry (@entries) {
        my $path = File::Spec->catfile($out_abs, $entry);
        return _showcase_out_dir_not_clean('output directory contains non-regular expected files')
            if !_is_regular_showcase_output($path);
    }

    return undef;
}

sub _showcase_out_dir_not_clean {
    my ($message) = @_;

    return {
        code    => 'showcase_out_dir_not_clean',
        class   => 'storage',
        field   => 'out',
        value   => 'not_clean',
        message => $message // 'output directory is not clean',
    };
}

sub _is_regular_showcase_output {
    my ($path) = @_;

    return 0 if !lstat($path);
    return 0 if -l _;
    return -f _;
}

sub _showcase_failure_doc {
    my ($out_abs, $files, $diagnostic) = @_;

    return json_doc(
        schema        => 'gobanftp.showcase.v1',
        status        => 'failed',
        boundary      => 'static-fixture-only',
        out           => $out_abs,
        files         => [@{ $files // [] }],
        diagnostics   => [$diagnostic],
        auth_boundary => auth_boundary_record(),
    );
}

sub _write_showcase_artifacts {
    my ($out_abs, $files) = @_;

    $out_abs = File::Spec->rel2abs($out_abs);
    die "storage: $out_abs is not a directory" if !-d $out_abs;

    my @cases = (
        _showcase_case(clean => 'minimal'),
        _showcase_case(fork  => 'fork'),
    );
    my @summaries = map { $_->{summary} } @cases;
    my @files = @{ $files // [_showcase_expected_files()] };

    my $doc = json_doc(
        schema         => 'gobanftp.showcase.v1',
        status         => 'ok',
        boundary       => 'static-fixture-only',
        out            => $out_abs,
        files          => \@files,
        cases          => \@summaries,
        auth_boundary  => auth_boundary_record(),
    );

    _write_text_file(
        File::Spec->catfile($out_abs, 'witness-clean.html'),
        render_witness_html(
            witness     => $cases[0]{witness},
            projections => $cases[0]{witness}{projection_text} // {},
        ),
    );
    _write_text_file(
        File::Spec->catfile($out_abs, 'witness-fork.html'),
        render_witness_html(
            witness     => $cases[1]{witness},
            projections => $cases[1]{witness}{projection_text} // {},
        ),
    );
    _write_text_file(File::Spec->catfile($out_abs, 'index.html'), _showcase_index_html($doc));
    _write_text_file(File::Spec->catfile($out_abs, 'demo-transcript.txt'), _showcase_transcript($doc));
    _write_text_file(File::Spec->catfile($out_abs, 'release-evidence.txt'), _showcase_release_evidence());
    _write_text_file(File::Spec->catfile($out_abs, 'roots.json'), encode_json_doc(%$doc));

    return $doc;
}

sub _showcase_case {
    my ($id, $fixture_id) = @_;

    my $fixture = File::Spec->catdir(
        _repo_root(),
        qw(t fixtures v1 cross-substrate),
        $fixture_id,
    );
    die "storage: missing showcase fixture: $fixture" if !-d $fixture;

    my $profile_id = 'local-goftp1';
    my $game = _read_single_nonblank(File::Spec->catfile($fixture, 'game.name'));
    my @raw_names = _read_nonblank_lines(File::Spec->catfile($fixture, $profile_id, 'listing.names'));
    my $witness = witness_for_listing(
        profile_id              => $profile_id,
        game_descriptor         => $game,
        raw_names               => \@raw_names,
        include_projection_text => 1,
    );

    return {
        id      => $id,
        witness => $witness,
        summary => {
            id               => $id,
            fixture_id       => $fixture_id,
            profile_id       => $profile_id,
            game_descriptor  => $game,
            replay_status    => $witness->{replay_status},
            event_set_root   => $witness->{event_set_root},
            accepted_count   => 0 + ($witness->{accepted_count} // 0),
            rejected_count   => 0 + ($witness->{rejected_count} // 0),
            diagnostic_count => 0 + ($witness->{diagnostic_count} // 0),
            signature_status => _signature_status($witness),
        },
    };
}

sub _showcase_index_html {
    my ($doc) = @_;

    my @case_items = map {
        my $href = $_->{id} eq 'clean' ? 'witness-clean.html'
            : $_->{id} eq 'fork' ? 'witness-fork.html'
            : undef;
        my $label = defined($href)
            ? '<a href="' . _html_escape($href) . '"><code>' . _html_escape($_->{id}) . '</code></a>'
            : '<code>' . _html_escape($_->{id}) . '</code>';
        $label . ': '
            . _html_escape($_->{replay_status})
            . ' root <code>' . _html_escape($_->{event_set_root} // '') . '</code></li>'
    } @{ $doc->{cases} // [] };
    my @artifact_items = (
        ['witness-clean.html',   'Clean witness'],
        ['witness-fork.html',    'Fork witness'],
        ['demo-transcript.txt',  'Demo transcript'],
        ['release-evidence.txt', 'Release evidence'],
        ['roots.json',           'Roots JSON'],
    );

    return '<!doctype html>' . "\n"
        . '<html lang="en" data-boundary="static-fixture-only">' . "\n"
        . '<head><meta charset="utf-8"><title>GobanFTP v1.1 Static Showcase</title></head>' . "\n"
        . '<body>' . "\n"
        . '<h1>GobanFTP v1.1 Static Showcase</h1>' . "\n"
        . '<p>Boundary: static fixture output only. These files are display artifacts, not replay input.</p>' . "\n"
        . '<nav aria-label="Static showcase files"><a href="#cases">Cases</a> '
        . '<a href="#artifacts">Artifacts</a> '
        . '<a href="witness-clean.html">Clean witness</a> '
        . '<a href="witness-fork.html">Fork witness</a> '
        . '<a href="roots.json">Roots JSON</a></nav>' . "\n"
        . '<h2 id="cases">Cases</h2>' . "\n"
        . '<ul>' . join('', @case_items) . '</ul>' . "\n"
        . '<h2 id="artifacts">Artifacts</h2>' . "\n"
        . '<ul>' . join('', map {
            '<li><a href="' . _html_escape($_->[0]) . '">' . _html_escape($_->[1]) . '</a></li>'
        } @artifact_items) . '</ul>' . "\n"
        . '</body></html>' . "\n";
}

sub _showcase_transcript {
    my ($doc) = @_;

    my @lines = (
        'GOFTP-SHOWCASE/1',
        'boundary=static-fixture-only',
        'output=display-artifact-not-replay-input',
        'auth.scope=' . publish_preflight_scope()->{scope},
        'auth.production_authorization=0',
    );
    for my $case (@{ $doc->{cases} // [] }) {
        push @lines,
            "case.$case->{id}.fixture=$case->{fixture_id}",
            "case.$case->{id}.profile=$case->{profile_id}",
            "case.$case->{id}.replay_status=$case->{replay_status}",
            "case.$case->{id}.event_set_root=" . ($case->{event_set_root} // '');
    }
    return join("\n", @lines, '');
}

sub _showcase_release_evidence {
    return join "\n",
        'GOFTP-SHOWCASE-EVIDENCE/1',
        'scope=local-fixture-source-candidate',
        'no_tag_push_upload_deploy=1',
        'no_make_dist_family=1',
        'recommended_checks=prove -l t/showcase-v1_1.t t/static-witness-specimen.t t/v1-cli-compare.t',
        '';
}

sub _print_showcase_summary {
    my ($showcase) = @_;

    print STDOUT 'gobanftp.showcase=' . _stdout_value($showcase->{status} // 'ok') . "\n";
    print STDOUT 'schema=' . _stdout_value($showcase->{schema}) . "\n";
    print STDOUT 'version=' . _stdout_value($showcase->{version}) . "\n";
    print STDOUT 'boundary=' . _stdout_value($showcase->{boundary}) . "\n";
    print STDOUT 'out=' . _stdout_value($showcase->{out}) . "\n";
    print STDOUT 'files=' . _stdout_value($showcase->{files} // []) . "\n";
    for my $case (@{ $showcase->{cases} // [] }) {
        print STDOUT "case.$case->{id}.replay_status=" . _stdout_value($case->{replay_status}) . "\n";
        print STDOUT "case.$case->{id}.event_set_root=" . _stdout_value($case->{event_set_root}) . "\n"
            if defined $case->{event_set_root};
    }
}

sub _print_showcase_failure {
    my ($showcase) = @_;

    my $diagnostics = $showcase->{diagnostics} // [];
    _print_showcase_summary($showcase);
    print STDOUT 'diagnostic_codes=' . _stdout_value([diagnostic_codes($diagnostics)]) . "\n";
    print STDOUT 'diagnostic_count=' . _stdout_value(scalar(@$diagnostics)) . "\n";
    for my $diagnostic (@$diagnostics) {
        next if ref($diagnostic) ne 'HASH';
        my $code = $diagnostic->{code} // '';
        next if $code !~ /\A[A-Za-z0-9_.-]+\z/;
        print STDOUT "diagnostic.$code=failed\n";
        print STDOUT "diagnostic.$code.detail=" . _stdout_value($diagnostic->{message}) . "\n"
            if defined($diagnostic->{message}) && $diagnostic->{message} ne '';
    }
}

sub _write_text_file {
    my ($path, $text) = @_;

    if (lstat($path)) {
        die "storage: open $path: non-regular output file" if -l _ || !-f _;
    }
    my $flags = O_WRONLY | O_CREAT | O_TRUNC | _o_nofollow();
    sysopen my $fh, $path, $flags, 0644 or die "storage: open $path: $!";
    binmode $fh, ':encoding(UTF-8)' or die "storage: binmode $path: $!";
    print {$fh} $text;
    close $fh or die "storage: close $path: $!";
    return 1;
}

sub _o_nofollow {
    state $flag = eval { Fcntl::O_NOFOLLOW() } // 0;
    return $flag;
}

sub _html_escape {
    my ($text) = @_;

    $text = '' if !defined $text;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    $text =~ s/'/&#39;/g;
    return $text;
}

sub _repo_root {
    return File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..', '..'));
}

sub _descriptor_from_create_args {
    my (@argv) = @_;

    if (@argv == 1) {
        my ($fields, $error) = parse_basename($argv[0]);
        return ($argv[0], undef) if !defined $error;
        return (undef, $error);
    }

    my %opts = (
        size  => 19,
        rules => 'chinese-area-v1',
        komi  => 7500,
    );

    while (@argv && $argv[0] =~ /\A--/) {
        my $option = shift @argv;
        my ($name, $value);

        if ($option =~ /\A--([^=]+)=(.*)\z/) {
            ($name, $value) = ($1, $2);
        }
        else {
            $name = substr($option, 2);
            return (undef, 'option.value') if !@argv;
            $value = shift @argv;
        }

        return (undef, 'option.name')
            if $name !~ /\A(?:id|size|rules|komi|black|white)\z/;

        $opts{ $name eq 'id' ? 'game_id' : $name } = $value;
    }

    if (@argv == 3 && !defined($opts{game_id}) && !defined($opts{black}) && !defined($opts{white})) {
        @opts{qw(game_id black white)} = @argv;
        @argv = ();
    }

    return (undef, 'argument.count') if @argv;

    my $descriptor = eval {
        build_basename(
            game_id => $opts{game_id},
            size    => $opts{size},
            rules   => $opts{rules},
            komi    => $opts{komi},
            black   => $opts{black},
            white   => $opts{white},
        );
    };
    return ($descriptor, undef) if defined $descriptor;

    my $error = $@ || 'gamespec';
    chomp $error;
    return (undef, _clean_error($error));
}

sub _print_summary {
    my ($command, $status, $context, %opts) = @_;

    my $result = $context->{replay_result};
    print STDOUT "gobanftp.$command=$status\n";
    print STDOUT "game=$context->{game_descriptor}\n";
    print STDOUT 'events=' . scalar(@{ $context->{events} }) . "\n";
    _print_event_set_summary($context) if $opts{event_set};
    print STDOUT 'canonical_moves=' . scalar(_canonical_ids($result)) . "\n";
    print STDOUT 'legal_moves=' . scalar(_legal_ids($result)) . "\n";
}

sub _print_event_set_summary {
    my ($context) = @_;

    my $event_set = $context->{event_set};
    return if ref($event_set) ne 'HASH';

    print STDOUT "event_set_count=$event_set->{event_count}\n";
    print STDOUT "event_set_root=$event_set->{event_set_root}\n"
        if exists $event_set->{event_set_root};
}

sub _print_v1_witness {
    my ($witness, $status, $attestation_count, $trusted_key_ids) = @_;

    print STDOUT "gobanftp.v1.witness=$status\n";
    for my $field (qw(
        profile_id
        profile_consensus_version
        adapter_id
        substrate_profile_id
        substrate_adapter_id
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
        board_hash
        sgf_hash
        variations_sgf_hash
    )) {
        next if !exists $witness->{$field};
        print STDOUT "$field=" . _stdout_value($witness->{$field}) . "\n";
    }
    print STDOUT "attestation_count=$attestation_count\n";
    print STDOUT 'trusted_hmac_key_ids=' . join(',', @$trusted_key_ids) . "\n";
    print STDOUT "signature.status=" . _signature_status($witness) . "\n";
}

sub _print_v1_witness_surface {
    my ($witness, $surface) = @_;

    my %args = (
        witness     => $witness,
        projections => $witness->{projection_text} // {},
    );

    if ($surface eq 'html') {
        print STDOUT render_witness_html(%args);
        return;
    }
    if ($surface eq 'terminal') {
        print STDOUT render_witness_terminal(%args);
        return;
    }

    print STDOUT render_witness_text(%args);
}

sub _print_v1_keyid {
    my ($record) = @_;

    print STDOUT "gobanftp.v1.keyid=ok\n";
    for my $field (qw(
        key_id
        key_id_version
        public_key_version
        suite
        public_key_bytes
    )) {
        print STDOUT "$field=$record->{$field}\n";
    }
}

sub _print_v1_trust_report {
    my ($fixture_id, $witness, $trust, $status) = @_;

    print STDOUT "gobanftp.v1.trust-report=$status\n";
    print STDOUT "fixture_id=$fixture_id\n";
    for my $field (qw(
        profile_id
        profile_consensus_version
        adapter_id
        game_descriptor
        raw_count
        normalized_count
        accepted_count
        rejected_count
        rejected_codes
        rejected_classes
        event_set_root
        replay_status
        diagnostic_codes
        diagnostic_classes
        diagnostic_count
    )) {
        next if !exists $witness->{$field};
        print STDOUT "$field=" . _stdout_value($witness->{$field}) . "\n";
    }

    for my $field (qw(
        status
        public_key_count
        record_count
        trusted_count
        trusted_key_ids
        rotated_count
        rotated_key_ids
        revoked_count
        revoked_key_ids
        expired_count
        expired_key_ids
    )) {
        print STDOUT "trust.$field=" . _stdout_value($trust->{$field}) . "\n";
    }
    print STDOUT "signature.status=unsigned\n";
}

sub _print_v1_publish_auth_fields {
    my (%args) = @_;

    my $scope = publish_preflight_scope();
    print STDOUT 'profile_id=' . _stdout_value($args{profile_id}) . "\n";
    print STDOUT 'game=' . _stdout_value($args{game}) . "\n";
    print STDOUT 'event=' . _stdout_value($args{event}) . "\n";
    print STDOUT 'event_id=' . _stdout_value($args{event_id}) . "\n"
        if defined $args{event_id};
    print STDOUT 'key_id=' . _stdout_value($args{key_id}) . "\n"
        if defined $args{key_id};
    print STDOUT 'publish_auth.scope=' . _stdout_value($scope->{scope}) . "\n";
    print STDOUT 'publish_auth.production_authorization='
        . _stdout_value($scope->{production_authorization}) . "\n";
    print STDOUT 'publish_auth.status=' . _stdout_value($args{status}) . "\n";
    print STDOUT 'diagnostic_codes='
        . _stdout_value([diagnostic_codes($args{diagnostics} // [])]) . "\n";
    print STDOUT 'diagnostic_classes='
        . _stdout_value([diagnostic_classes($args{diagnostics} // [])]) . "\n";
    print STDOUT 'diagnostic_count=' . _stdout_value(scalar(@{ $args{diagnostics} // [] })) . "\n";
}

sub _print_publish_auth_diagnostics {
    my ($result, $secrets) = @_;

    my %seen;
    for my $diagnostic (@{ $result->{diagnostics} // [] }) {
        next if ref($diagnostic) ne 'HASH';
        my $line = _diagnostic_line($diagnostic, $secrets);
        next if $seen{$line}++;
        print STDERR redact_text($line, @{ $secrets // [] }), "\n";
    }
}

sub _stdout_value {
    my ($value) = @_;
    return _escape_control_chars(join(',', map { !defined($_) || ref($_) ? '' : $_ } @$value))
        if ref($value) eq 'ARRAY';
    return '' if !defined $value || ref($value);
    return _escape_control_chars($value);
}

sub _signature_status {
    my ($witness) = @_;

    my $profile_id = $witness->{profile_id} // '';
    return 'unsigned' if $profile_id ne 'signed-hmac-goftp1';
    return grep({ $_ eq 'signature' } @{ $witness->{rejected_classes} // [] }) ? 'failed' : 'ok';
}

sub _v1_witness_exit {
    my ($witness) = @_;

    return EXIT_VALIDATION if ($witness->{rejected_count} // 0) > 0;
    return EXIT_VALIDATION if ($witness->{replay_status} // '') eq 'validation';
    return EXIT_CONFLICT   if ($witness->{replay_status} // '') eq 'fork';
    return EXIT_SUCCESS;
}

sub _print_v1_witness_diagnostics {
    my ($witness, $secrets) = @_;

    my %seen;
    for my $diagnostic (
        @{ $witness->{replay_diagnostics} // [] },
        @{ $witness->{rejected_diagnostics} // [] },
    ) {
        next if ref($diagnostic) ne 'HASH';
        my $line = _diagnostic_line($diagnostic, $secrets);
        next if $seen{$line}++;
        print STDERR redact_text($line, @{ $secrets // [] }), "\n";
    }
}

sub _print_v1_compare {
    my ($subcommand, $status, $comparison) = @_;

    my $command_key = "gobanftp.v1.$subcommand";
    my @profiles = @{ $comparison->{profiles} };
    my $baseline = $comparison->{baseline_profile};
    my $witnesses = $comparison->{witnesses};
    my $baseline_witness = $witnesses->{$baseline};

    print STDOUT "$command_key=$status\n";
    print STDOUT "comparison_scope=fixture-read-normalizer\n";
    print STDOUT "fixture_id=$comparison->{fixture_id}\n";
    print STDOUT "game_descriptor=$comparison->{game_descriptor}\n";
    print STDOUT 'profile_count=' . scalar(@profiles) . "\n";
    print STDOUT 'profiles=' . join(',', @profiles) . "\n";
    print STDOUT "baseline_profile=$baseline\n";
    print STDOUT 'compared_fields=' . join(',', @{ $comparison->{fields} }) . "\n";
    print STDOUT 'mismatch_count=' . scalar(@{ $comparison->{mismatch_fields} }) . "\n";
    print STDOUT 'mismatch_fields=' . join(',', @{ $comparison->{mismatch_fields} }) . "\n";
    print STDOUT 'mismatch_profiles=' . join(',', @{ $comparison->{mismatch_profiles} }) . "\n";
    print STDOUT 'invalid_profile_count=' . scalar(@{ $comparison->{invalid_profiles} }) . "\n";
    print STDOUT 'invalid_profiles=' . join(',', @{ $comparison->{invalid_profiles} }) . "\n";
    print STDOUT 'profile_roots=' . _profile_field_pairs($witnesses, \@profiles, 'event_set_root') . "\n";
    print STDOUT 'profile_replay_statuses='
        . _profile_field_pairs($witnesses, \@profiles, 'replay_status') . "\n";

    for my $field (qw(
        ruleset_id
        ruleset_semver
        ruleset_seal_version
        ruleset_fixture_digest
        ruleset_seal
        event_set_root
        accepted_count
        accepted_events
        rejected_count
        rejected_codes
        rejected_classes
        replay_status
        canonical_tip
        canonical_ids
        legal_ids
        diagnostic_codes
        diagnostic_classes
        diagnostic_count
        board_hash
        sgf_hash
        variations_sgf_hash
    )) {
        next if !exists $baseline_witness->{$field};
        print STDOUT "$field=" . _stdout_value($baseline_witness->{$field}) . "\n";
    }
}

sub _profile_field_pairs {
    my ($witnesses, $profiles, $field) = @_;

    return join ',', map {
        $_ . ':' . _stdout_value($witnesses->{$_}{$field})
    } @$profiles;
}

sub _print_diagnostics {
    my ($result) = @_;

    for my $diagnostic (_diagnostics($result)) {
        print STDERR redact_text(_diagnostic_line($diagnostic)), "\n";
    }
}

sub _print_unique_diagnostics {
    my (@diagnostics) = @_;

    my %seen;
    for my $diagnostic (@diagnostics) {
        my $line = redact_text(_diagnostic_line($diagnostic));
        next if $seen{$line}++;
        print STDERR "$line\n";
    }
}

sub _print_terminal_snapshot {
    my ($command, $context, %opts) = @_;

    my $result = $context->{replay_result};
    my $exit   = _result_exit($result);
    my $status = $exit == EXIT_SUCCESS ? 'ok' : $exit == EXIT_CONFLICT ? 'fork' : 'failed';

    _print_summary($command, $status, $context, event_set => 1);
    print STDOUT "snapshot=$opts{snapshot}\n" if defined $opts{snapshot};
    print STDOUT "live=1\n" if $opts{live};
    if ($opts{compact}) {
        print STDOUT "compact=1\n";
        print STDOUT "observer.delta_events=$opts{observer_delta_events}\n"
            if defined $opts{observer_delta_events};
        print STDOUT "observer.event_set_root_changed=$opts{observer_delta_root_changed}\n"
            if defined $opts{observer_delta_root_changed};
    }
    _print_turn($result);
    _print_worldline($result);
    return $exit if $opts{compact};

    my $rendered = render_projection(
        game_descriptor => $context->{game_descriptor},
        events          => $context->{events},
        replay_result   => $result,
    );
    print STDOUT $rendered->{board};

    return $exit;
}

sub _print_turn {
    my ($result) = @_;

    my $state = _final_state($result);
    my $game  = _game($result);
    my $color = ref($state) eq 'HASH' ? ($state->{next_color} // '') : '';

    print STDOUT "turn_color=$color\n";
    if (ref($game) eq 'HASH') {
        my $player = $color eq 'b' ? $game->{black}
            : $color eq 'w'        ? $game->{white}
            :                        undef;
        print STDOUT "turn_player=$player\n" if defined $player;
    }
}

sub _print_worldline {
    my ($result) = @_;

    my @diagnostics = _diagnostics($result);
    my $fork = _fork($result) // _fork_diagnostic(@diagnostics);
    my $has_validation = grep { ($_->{code} // '') ne 'fork' } @diagnostics;
    my $status = $has_validation ? 'validation' : defined($fork) ? 'fork' : 'main';

    print STDOUT "worldline.status=$status\n";
    print STDOUT 'worldline.canonical_ids=' . join(',', _canonical_ids($result)) . "\n";
    print STDOUT 'worldline.legal_ids=' . join(',', _legal_ids($result)) . "\n";

    if (defined $fork) {
        print STDOUT 'worldline.fork.parent_id=' . ($fork->{parent_id} // '') . "\n";
        print STDOUT 'worldline.fork.child_ids=' . join(',', @{ $fork->{child_ids} // [] }) . "\n";
    }
}

sub _diagnostic_line {
    my ($diagnostic, $secrets) = @_;

    my @fields = ('diagnostic');
    for my $key (sort keys %$diagnostic) {
        my $value = $diagnostic->{$key};
        if (ref($value) eq 'ARRAY') {
            $value = join(',', @$value);
        }
        elsif (ref($value)) {
            next;
        }
        push @fields, "$key=" . _diagnostic_token($value, $secrets);
    }

    return join(' ', @fields);
}

sub _diagnostic_token {
    my ($value, $secrets) = @_;

    return '' if !defined $value;
    return 'REDACTED' if contains_redactable_secret($value, @{ $secrets // [] });
    $value = redact_text($value, @{ $secrets // [] });
    $value =~ s/\[REDACTED\]/REDACTED/g;
    $value =~ s/([^A-Za-z0-9._:\/,-])/sprintf('%%%02X', ord($1))/eg;
    return $value;
}

sub _is_public_token {
    my ($value) = @_;
    return defined($value) && $value =~ /\A[A-Za-z0-9._:-]+\z/;
}

sub _v1_usage {
    return join "\n",
        'usage: v1 keygen --profile signed-hmac-goftp1 --out hmac-key-file',
        'usage: v1 keyid --fixture public-key-file',
        'usage: v1 attest --profile signed-hmac-goftp1 --key hmac-key-file --out attestations.jsonl <game-root|game-descriptor>',
        'usage: v1 publish-token --profile signed-hmac-goftp1 --key hmac-key-file --out publish-token.jsonl [--key-status trusted|rotated|revoked|expired] <game-root|game-descriptor> <event-basename>',
        'usage: v1 publish-auth --profile signed-hmac-goftp1 --token publish-token.jsonl [--trusted-hmac-key id=key] [--trusted-hmac-key-file hmac-key-file] [--trusted-hmac-status id=status] <game-root|game-descriptor> <event-basename>',
        'usage: v1 trust-report --fixture fixture-dir',
        _v1_witness_usage_line(),
        'usage: v1 compare-roots --fixture fixture-dir [--profiles profile-id,...] [--json]',
        'usage: v1 compare-replay --fixture fixture-dir [--profiles profile-id,...] [--json]';
}

sub _v1_witness_usage_line {
    return 'usage: v1 witness --profile profile-id [--substrate-profile profile-id] --fixture fixture-dir [--attestations jsonl] [--trusted-hmac-key id=key] [--trusted-hmac-key-file hmac-key-file] [--trusted-hmac-status id=status] [--surface text|html|terminal]';
}

sub _result_exit {
    my ($result) = @_;

    my @diagnostics = _diagnostics($result);
    return EXIT_SUCCESS if !@diagnostics;
    return EXIT_VALIDATION if grep { ($_->{code} // '') ne 'fork' } @diagnostics;
    return EXIT_CONFLICT;
}

sub _status_for_exit {
    my ($exit) = @_;
    return $exit == EXIT_SUCCESS  ? 'ok'
        : $exit == EXIT_CONFLICT ? 'fork'
        :                          'failed';
}

sub _canonical_ids {
    my ($result) = @_;
    return $result->canonical_ids if ref($result) && eval { $result->can('canonical_ids') };
    return @{ $result->{canonical_ids} // [] } if ref($result) eq 'HASH';
    return ();
}

sub _legal_ids {
    my ($result) = @_;
    return $result->legal_ids if ref($result) && eval { $result->can('legal_ids') };
    return @{ $result->{legal_ids} // [] } if ref($result) eq 'HASH';
    return ();
}

sub _diagnostics {
    my ($result) = @_;
    return $result->diagnostics if ref($result) && eval { $result->can('diagnostics') };
    return @{ $result->{diagnostics} // [] } if ref($result) eq 'HASH';
    return ();
}

sub _final_state {
    my ($result) = @_;
    return undef if !ref $result;
    return $result->final_state if eval { $result->can('final_state') };
    return $result->{final_state} if (reftype($result) // '') eq 'HASH';
    return undef;
}

sub _fork {
    my ($result) = @_;
    return undef if !ref $result;
    return $result->fork if eval { $result->can('fork') };
    return $result->{fork} if (reftype($result) // '') eq 'HASH';
    return undef;
}

sub _game {
    my ($result) = @_;
    return undef if !ref $result;
    return $result->game if eval { $result->can('game') };
    return $result->{game} if (reftype($result) // '') eq 'HASH';
    return undef;
}

sub _terminal_replay {
    my ($result) = @_;
    my $state = _final_state($result);
    return ref($state) eq 'HASH' && $state->{terminal} ? 1 : 0;
}

sub _fork_diagnostic {
    for my $diagnostic (@_) {
        return $diagnostic if ($diagnostic->{code} // '') eq 'fork';
    }
    return undef;
}

sub _usage {
    my ($fh, $status) = @_;

    print {$fh} <<'USAGE';
usage: gobanftp <command> <game-root>

commands:
  --version
  config show [--json]
  doctor [--json] [--connect]
  showcase --out dir [--json]
  create-game <game-descriptor>
  create-game --id id --black player --white player [--size n] [--rules id] [--komi milli]
  verify <game-root|game-descriptor>
  replay <game-root|game-descriptor>
  sgf [--write] <game-root|game-descriptor>
  sgf --variations <game-root|game-descriptor>
  project <game-root|game-descriptor>
  publish-move [--json] [--nonce n] [--publish-auth-token publish-token.jsonl] [--publish-auth-trusted-hmac-key-file hmac-key-file] <game-root|game-descriptor> <aa|play-aa|pass|resign>
  publish-ack [--json] [--nonce n] [--publish-auth-token publish-token.jsonl] [--publish-auth-trusted-hmac-key-file hmac-key-file] <game-root|game-descriptor> <event-id>
  play [--once|--live|--tui] [--count n|--max-polls n] [--interval seconds] [--move move|--ack event-id] [--nonce n] [--publish-auth-token publish-token.jsonl] [--publish-auth-trusted-hmac-key-file hmac-key-file] <game-root|game-descriptor>
  watch [--live] [--compact] [--once] [--count n|--max-polls n] [--interval seconds] <game-root|game-descriptor>
  v1 keygen --profile signed-hmac-goftp1 --out hmac-key-file
  v1 keyid --fixture public-key-file
  v1 attest --profile signed-hmac-goftp1 --key hmac-key-file --out attestations.jsonl <game-root|game-descriptor>
  v1 publish-token --profile signed-hmac-goftp1 --key hmac-key-file --out publish-token.jsonl [--key-status trusted|rotated|revoked|expired] <game-root|game-descriptor> <event-basename>
  v1 publish-auth --profile signed-hmac-goftp1 --token publish-token.jsonl [--trusted-hmac-key id=key] [--trusted-hmac-key-file hmac-key-file] [--trusted-hmac-status id=status] <game-root|game-descriptor> <event-basename>
  v1 trust-report --fixture fixture-dir
  v1 witness --profile profile-id [--substrate-profile profile-id] --fixture fixture-dir [--attestations jsonl] [--trusted-hmac-key id=key] [--trusted-hmac-key-file hmac-key-file] [--trusted-hmac-status id=status] [--surface text|html|terminal]
  v1 compare-roots --fixture fixture-dir [--profiles profile-id,...] [--json]
  v1 compare-replay --fixture fixture-dir [--profiles profile-id,...] [--json]
USAGE

    return $status;
}

sub _clean_error {
    my ($error) = @_;

    chomp $error;
    $error =~ s/\s+at \S+ line [0-9]+(?:,\s+.*)?\.?\z//;
    return _escape_control_chars($error);
}

sub _escape_control_chars {
    my ($text) = @_;

    $text = '' if !defined $text;
    $text =~ s/\n/\\n/g;
    $text =~ s/\r/\\r/g;
    $text =~ s/\t/\\t/g;
    $text =~ s/([\x00-\x08\x0b\x0c\x0e-\x1f\x7f])/sprintf('\\x%02X', ord($1))/eg;
    return $text;
}

1;

__END__

=head1 NAME

GobanFTP::CLI - local GobanFTP command entry points

=cut
