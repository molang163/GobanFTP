package GobanFTP::Redact;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(redact_text);

sub redact_text {
    my ($text) = @_;
    $text //= '';

    for my $secret (_secret_env_values()) {
        _redact_literal(\$text, $secret);
    }

    $text =~ s{-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----}{[REDACTED]}gis;
    $text =~ s{(ftp://[^:\s/@]+:)[^@\s/]+(@)}{${1}[REDACTED]${2}}gi;
    $text =~ s{(\bAuthorization\s*:\s*(?:Bearer|Basic)\s+)[^\r\n\s]+}{${1}[REDACTED]}gi;
    $text =~ s{(\bCookie\s*:\s*)[^\r\n]+}{${1}[REDACTED]}gi;
    $text =~ s{(\bSet-Cookie\s*:\s*)[^\r\n]+}{${1}[REDACTED]}gi;
    $text =~ s{(\bPASS\s+)[^\r\n\s]+}{${1}[REDACTED]}gi;

    $text =~ s{
        (\b[A-Z_][A-Z0-9_]*(?:PASSWORD|PASSWD|TOKEN|SECRET|KEY)[A-Z0-9_]*=)
        (?:"[^"]*"|'[^']*'|\S+)
    }{${1}[REDACTED]}gx;

    $text =~ s{
        ((?:password|passwd|token|secret|api[_-]?key|private[_-]?key)\s*[:=]\s*)
        (?:"[^"]*"|'[^']*'|\S+)
    }{${1}[REDACTED]}gix;

    $text =~ s{
        (--(?:password|passwd|token|secret|api-key|private-key)\s+)
        (?:"[^"]*"|'[^']*'|\S+)
    }{${1}[REDACTED]}gix;

    return $text;
}

sub _secret_env_values {
    my @values;
    my %seen;
    for my $name (keys %ENV) {
        next if $name !~ /(?:PASSWORD|PASSWD|TOKEN|SECRET|KEY)/;
        my $value = $ENV{$name};
        next if !defined($value) || $value eq '';
        push @values, $value if !$seen{$value}++;
    }

    return sort { length($b) <=> length($a) } @values;
}

sub _redact_literal {
    my ($text_ref, $secret) = @_;

    my $quoted = quotemeta $secret;
    if (length($secret) < 4 && $secret =~ /\A[A-Za-z0-9_]+\z/) {
        $$text_ref =~ s/(?<![A-Za-z0-9_])$quoted(?![A-Za-z0-9_])/[REDACTED]/g;
        return;
    }

    $$text_ref =~ s/$quoted/[REDACTED]/g;
    return;
}

1;

__END__

=head1 NAME

GobanFTP::Redact - shared secret redaction for diagnostics and recovery

=cut
