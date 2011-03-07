package Amon2::Web;
use strict;
use warnings;
use Amon2::Util ();
use Amon2::Trigger qw/add_trigger call_trigger get_trigger_code/;
use Encode ();
use Module::Find ();
use Plack::Util ();
use URI::Escape ();
use Amon2::Web::Request;
use Amon2::Web::Response;
use Scalar::Util ();

# -------------------------------------------------------------------------
# hook points:
# you can override these methods.
sub create_request  { Amon2::Web::Request->new($_[1]) }
sub create_response { shift; Amon2::Web::Response->new(@_) }
sub create_view     { die "This is abstract method: create_view" }
sub dispatch        { die "This is abstract method: dispatch"    }

sub html_content_type { 'text/html; charset=UTF-8' }
BEGIN {
    my $encoding = Encode::find_encoding('utf-8') || die;
    sub encoding          { $encoding }
}

# -------------------------------------------------------------------------
# attributes
sub request           { $_[0]->{request} }
sub req               { $_[0]->{request} }

# -------------------------------------------------------------------------
# methods

sub redirect {
    my ($self, $location, $params) = @_;
    my $url = do {
        if ($location =~ m{^https?://}) {
            $location;
        } else {
            my $url = $self->request->base;
            $url =~ s{/+$}{};
            $location =~ s{^/+([^/])}{/$1};
            $url .= $location;
        }
    };
    if (my $ref_params = ref $params) {
        if ($ref_params eq 'ARRAY') {
            my $uri = URI->new($url);
            $uri->query_form($uri->query_form, map { Encode::encode($self->encoding, $_) } @$params);
            $url = $uri->as_string;
        } elsif ($ref_params eq 'HASH') {
            my @ary;
            my $encoding = $self->encoding;
            while (my ($k, $v) = each %$params) {
                push @ary, Encode::encode($encoding, $k);
                push @ary, Encode::encode($encoding, $v);
            }
            my $uri = URI->new($url);
            $uri->query_form($uri->query_form, @ary);
            $url = $uri->as_string;
        }
    }
    $self->create_response(
        302,
        ['Location' => $url],
        []
    );
}

sub res_404 {
    my ($self) = @_;
    my $content = <<'...';
<!doctype html>
<html>
    <head>
        <meta charset=utf-8 />
        <style type="text/css">
            body {
                text-align: center;
                font-family: 'Menlo', 'Monaco', Courier, monospace;
                background-color: whitesmoke;
                padding-top: 10%;
            }
            .number {
                font-size: 800%;
                font-weight: bold;
                margin-bottom: 40px;
            }
            .message {
                font-size: 400%;
            }
        </style>
    </head>
    <body>
        <div class="number">404</div>
        <div class="message">File Not Found</div>
    </body>
</html>
...
    $self->create_response(
        404,
        [
            'Content-Type' => 'text/html; charset=utf-8',
            'Content-Length' => length($content),
        ],
        [$content]
    );
}

sub to_app {
    my ($class, ) = @_;

    return sub {
        my ($env) = @_;
        my $req = $class->create_request($env);
        my $self = $class->new(
            request => $req,
        );

        no warnings 'redefine';
        local $Amon2::CONTEXT = $self;

        my $response;
        for my $code ($self->get_trigger_code('BEFORE_DISPATCH')) {
            $response = $code->($self);
            goto PROCESS_END if Scalar::Util::blessed($response) && $response->isa('Plack::Response');
        }
        $response = $self->dispatch() or die "cannot get any response";
    PROCESS_END:
        $self->call_trigger('AFTER_DISPATCH' => $response);
        return $response->finalize;
    };
}

sub uri_for {
    my ($self, $path, $query) = @_;
    my $root = $self->req->{env}->{SCRIPT_NAME} || '/';
    $root =~ s{([^/])$}{$1/};
    $path =~ s{^/}{};

    my @q;
    while (my ($key, $val) = each %$query) {
        $val = URI::Escape::uri_escape(Encode::encode($self->encoding, $val));
        push @q, "${key}=${val}";
    }
    $root . $path . (scalar @q ? '?' . join('&', @q) : '');
}

sub render {
    my $self = shift;
    my $html = $self->create_view()->render(@_);

    for my $code ($self->get_trigger_code('HTML_FILTER')) {
        $html = $code->($self, $html);
    }

    $html = $self->encode_html($html);

    return $self->create_response(
        200,
        ['Content-Type' => $self->html_content_type, 'Content-Length' => length($html)],
        $html,
    );
}

# you can override this method on your application
sub encode_html {
    my ($self, $html) = @_;
    return Encode::encode($self->encoding, $html);
}

1;
__END__

=head1 NAME

Amon2::Web - Web Application Base.

=head1 SYNOPSIS

    package MyApp;
    use parent qw/Amon2::Web/;

=head1 DESCRIPTION

This is a web application base class.

=head1 METHODS

TBD
