package GobanFTP::Redact;

use v5.34;
use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(contains_redactable_secret redact_text);

sub redact_text {
    my ($text, @extra_secrets) = @_;
    $text //= '';

    for my $secret (_redaction_secrets(@extra_secrets)) {
        for my $variant (_secret_variants($secret)) {
            _redact_literal(\$text, $variant);
        }
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

sub contains_redactable_secret {
    my ($text, @extra_secrets) = @_;
    return 0 if !defined($text) || $text eq '';

    my @candidates = ($text);
    my $decoded = $text;
    while (1) {
        my $next = _percent_decode($decoded);
        last if $next eq $decoded;
        push @candidates, $next;
        $decoded = $next;
    }

    for my $candidate (@candidates) {
        for my $secret (_redaction_secrets(@extra_secrets)) {
            return 1 if _contains_literal($candidate, $secret);
        }
    }

    return 0;
}

sub _redaction_secrets {
    my (@extra_secrets) = @_;

    my %seen;
    return sort { length($b) <=> length($a) }
        grep { defined($_) && $_ ne '' && !$seen{$_}++ }
        (_secret_env_values(), @extra_secrets);
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

sub _contains_literal {
    my ($text, $secret) = @_;

    my $quoted = quotemeta $secret;
    if (length($secret) < 4 && $secret =~ /\A[A-Za-z0-9_]+\z/) {
        return $text =~ /(?<![A-Za-z0-9_])$quoted(?![A-Za-z0-9_])/ ? 1 : 0;
    }

    return index($text, $secret) >= 0 ? 1 : 0;
}

sub _secret_variants {
    my ($secret) = @_;

    my @variants = ($secret);
    my $encoded = $secret;
    for (1 .. 2) {
        $encoded = _percent_encode($encoded);
        last if $encoded eq $variants[-1];
        push @variants, $encoded;
    }

    return @variants;
}

sub _percent_encode {
    my ($value) = @_;

    $value =~ s/([^A-Za-z0-9._:\/,-])/sprintf('%%%02X', ord($1))/eg;
    return $value;
}

sub _percent_decode {
    my ($value) = @_;

    $value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return $value;
}

1;

__END__

=head1 NAME

GobanFTP::Redact - shared secret redaction for diagnostics and recovery

=cut
