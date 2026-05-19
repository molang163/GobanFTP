package GobanFTP::Auth::HMACKey;

use v5.34;
use strict;
use warnings;

use Carp qw(croak);
use Exporter qw(import);
use Fcntl qw(O_CREAT O_EXCL O_WRONLY);
use MIME::Base64 qw(decode_base64);

use GobanFTP::Auth::HMAC qw(key_id_for_secret);

our @EXPORT_OK = qw(
    generate_hmac_key_record
    hmac_key_record_text
    parse_hmac_key_record
    read_hmac_key_file
    write_hmac_key_file
);

my $KEY_VERSION = 'GOFTP-HMAC-KEY/1';
my $PROFILE = 'signed-hmac-goftp1';
my $ALGORITHM = 'hmac-sha256';

sub generate_hmac_key_record {
    my %args = @_ == 1 && ref($_[0]) eq 'HASH' ? %{ $_[0] } : @_;

    my $profile = $args{profile} // $PROFILE;
    croak 'profile.unsupported' if $profile ne $PROFILE;

    my $secret = exists($args{secret})
        ? $args{secret}
        : exists($args{secret_hex})
            ? _secret_from_hex($args{secret_hex})
            : _random_bytes(32);

    croak 'secret.length' if length($secret) != 32;

    return {
        version    => $KEY_VERSION,
        profile    => $profile,
        algorithm  => $ALGORITHM,
        key_id     => key_id_for_secret($secret),
        secret     => $secret,
        secret_hex => unpack('H*', $secret),
    };
}

sub hmac_key_record_text {
    my ($record) = @_;
    croak 'record' if ref($record) ne 'HASH';

    my $normalized = _normalize_record($record);

    return join("\n",
        $KEY_VERSION,
        "profile=$normalized->{profile}",
        "algorithm=$normalized->{algorithm}",
        "key_id=$normalized->{key_id}",
        "secret_hex=$normalized->{secret_hex}",
        '',
    );
}

sub parse_hmac_key_record {
    my ($text) = @_;

    croak 'record.missing' if !defined $text;

    my @lines = grep { $_ ne '' } map { s/\r\z//r } split /\n/, $text, -1;
    croak 'header' if !@lines || shift(@lines) ne $KEY_VERSION;

    my %fields;
    for my $line (@lines) {
        croak 'line.format' if $line !~ /\A([A-Za-z][A-Za-z0-9_.-]*)=(.*)\z/;
        my ($key, $value) = ($1, $2);
        croak 'field.unknown'
            if $key ne 'profile'
                && $key ne 'algorithm'
                && $key ne 'key_id'
                && $key ne 'secret_hex';
        croak 'duplicate_field' if exists $fields{$key};
        croak 'field.nul' if index($value, "\0") >= 0;
        $fields{$key} = $value;
    }

    return _normalize_record({
        version    => $KEY_VERSION,
        profile    => $fields{profile},
        algorithm  => $fields{algorithm},
        key_id     => $fields{key_id},
        secret_hex => $fields{secret_hex},
    });
}

sub read_hmac_key_file {
    my ($path) = @_;
    croak 'path.missing' if !defined($path) || $path eq '';

    my @stat = stat $path;
    croak "stat $path: $!" if !@stat;
    croak 'mode.public' if _posix_private_mode_is_enforced() && ($stat[2] & 0077) != 0;

    open my $fh, '<:encoding(UTF-8)', $path or croak "open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or croak "close $path: $!";

    return parse_hmac_key_record($text);
}

sub write_hmac_key_file {
    my ($path, $record) = @_;
    croak 'path.missing' if !defined($path) || $path eq '';

    my $text = hmac_key_record_text($record);
    my $fh;
    sysopen $fh, $path, O_WRONLY | O_CREAT | O_EXCL, 0600
        or croak "create $path: $!";
    binmode $fh;
    print {$fh} $text;
    close $fh or croak "close $path: $!";
    my $chmod_ok = chmod 0600, $path;
    croak "chmod $path: $!" if !$chmod_ok && _posix_private_mode_is_enforced();

    return 1;
}

sub _normalize_record {
    my ($record) = @_;

    my $profile = $record->{profile};
    croak 'profile.missing' if !defined($profile) || $profile eq '';
    croak 'profile.unsupported' if $profile ne $PROFILE;

    my $algorithm = $record->{algorithm};
    croak 'algorithm.missing' if !defined($algorithm) || $algorithm eq '';
    croak 'algorithm.unsupported' if $algorithm ne $ALGORITHM;

    my $secret_hex = $record->{secret_hex};
    croak 'secret_hex.missing' if !defined($secret_hex) || $secret_hex eq '';
    my $secret = _secret_from_hex($secret_hex);
    my $key_id = key_id_for_secret($secret);

    croak 'key_id.mismatch'
        if defined($record->{key_id}) && $record->{key_id} ne '' && $record->{key_id} ne $key_id;

    return {
        version    => $KEY_VERSION,
        profile    => $profile,
        algorithm  => $algorithm,
        key_id     => $key_id,
        secret     => $secret,
        secret_hex => $secret_hex,
    };
}

sub _secret_from_hex {
    my ($secret_hex) = @_;
    croak 'secret_hex.format'
        if !defined($secret_hex) || $secret_hex !~ /\A[0-9a-f]{64}\z/;
    return pack 'H*', $secret_hex;
}

sub _random_bytes {
    my ($length) = @_;

    return _windows_random_bytes($length) if $^O eq 'MSWin32';

    open my $fh, '<:raw', '/dev/urandom'
        or croak 'csprng.unavailable';

    my $bytes = '';
    while (length($bytes) < $length) {
        my $read = read $fh, my $chunk, $length - length($bytes);
        croak 'csprng.read' if !defined($read) || $read == 0;
        $bytes .= $chunk;
    }

    close $fh or croak 'csprng.close';
    return $bytes;
}

sub _windows_random_bytes {
    my ($length) = @_;

    for my $powershell (qw(powershell.exe pwsh.exe powershell pwsh)) {
        my $command = join '; ',
            '$bytes = New-Object byte[] ' . int($length),
            '[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)',
            '[Convert]::ToBase64String($bytes)';

        my $output = '';
        if (open my $fh, '-|', $powershell, '-NoProfile', '-NonInteractive', '-Command', $command) {
            local $/;
            $output = <$fh> // '';
            close $fh or next;

            $output =~ s/\s+\z//;
            my $bytes = eval { decode_base64($output) };
            return $bytes if defined($bytes) && length($bytes) == $length;
        }
    }

    croak 'csprng.unavailable';
}

sub _posix_private_mode_is_enforced {
    return $^O ne 'MSWin32' ? 1 : 0;
}

1;

__END__

=head1 NAME

GobanFTP::Auth::HMACKey - signed-HMAC verifier key files

=cut
