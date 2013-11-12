package Kossy::Request;

use strict;
use warnings;
use parent qw/Plack::Request/;
use Hash::MultiValue;
use Encode;
use Kossy::Validator;
use Kossy::BodyParser;
use Kossy::BodyParser::UrlEncoded;
use Kossy::BodyParser::MultiPart;
use Kossy::BodyParser::JSON;

sub new {
    my($class, $env, %opts) = @_;
    Carp::croak(q{$env is required})
        unless defined $env && ref($env) eq 'HASH';

    bless {
        %opts,
        env => $env,
    }, $class;
}

sub request_body_parser {
    my $self = shift;
    unless (exists $self->{request_body_parser}) {
        $self->{request_body_parser} = $self->_build_request_body_parser();
    }
    return $self->{request_body_parser};
}

sub _build_request_body_parser {
    my $self = shift;

    my $parser = Kossy::BodyParser->new();
    $parser->register(
        'application/x-www-form-urlencoded',
        'Kossy::BodyParser::UrlEncoded'
    );
    $parser->register(
        'multipart/form-data',
        'Kossy::BodyParser::MultiPart'
    );
    if ( $self->{parse_json_body} ) {
            $parser->register(
                'application/json',
                'Kossy::BodyParser::JSON'
            );
    }
    $parser;
}

sub _parse_request_body {
    my $self = shift;
    $self->request_body_parser->parse($self->env);
}

sub uploads {
    my $self = shift;
    unless ($self->env->{'kossy.request.upload_parameters'}) {
        $self->_parse_request_body;
    }
    $self->env->{'plack.request.upload'} ||= 
        Hash::MultiValue->new(@{$self->env->{'kossy.request.upload_parameters'}});
}

sub body_parameters {
    my ($self) = @_;
    $self->env->{'kossy.request.body'} ||= $self->_decode_parameters(@{$self->_body_parameters()});
}

sub query_parameters {
    my ($self) = @_;
    $self->env->{'kossy.request.query'} ||= $self->_decode_parameters(@{$self->_query_parameters()});
}

sub parameters {
    my $self = shift;
    $self->env->{'kossy.request.merged'} ||= do {
        Hash::MultiValue->new(
            $self->query_parameters->flatten,
            $self->body_parameters->flatten,            
        );
    };
}

sub _decode_parameters {
    my ($self, @flatten) = @_;
    my @decoded;
    while ( my ($k, $v) = splice @flatten, 0, 2 ) {
        push @decoded, Encode::decode_utf8($k), Encode::decode_utf8($v);
    }
    return Hash::MultiValue->new(@decoded);
}

sub _body_parameters {
    my $self = shift;
    unless ($self->env->{'kossy.request.body_parameters'}) {
        $self->_parse_request_body;
    }
    return $self->env->{'kossy.request.body_parameters'};    
}

sub _query_parameters {
    my $self = shift;
    unless ( $self->env->{'kossy.request.query_parameter'} ) {
        $self->env->{'kossy.request.query_parameters'} = 
            URL::Encode::url_params_flat($self->env->{'QUERY_STRING'});
    }
    return $self->env->{'kossy.request.query_parameters'};
}

sub body_parameters_raw {
    my $self = shift;
    unless ($self->env->{'plack.request.body'}) {
        $self->env->{'plack.request.body'} = Hash::MultiValue->new(@{$self->_body_parameters});
    }
    return $self->env->{'plack.request.body'};
}

sub query_parameters_raw {
    my $self = shift;
    unless ($self->env->{'plack.request.query'}) {
        $self->env->{'plack.request.query'} = Hash::MultiValue->new(@{$self->_query_parameters});
    }
    return $self->env->{'plack.request.query'};
}

sub parameters_raw {
    my $self = shift;
    $self->env->{'plack.request.merged'} ||= do {
        Hash::MultiValue->new(
            @{$self->_query_parameters},
            @{$self->_body_parameters}
        );
    };
}

sub param_raw {
    my $self = shift;

    return keys %{ $self->parameters_raw } if @_ == 0;

    my $key = shift;
    return $self->parameters_raw->{$key} unless wantarray;
    return $self->parameters_raw->get_all($key);
}

sub base {
    my $self = shift;
    $self->{_base} ||= {};
    my $base = $self->_uri_base;
    $self->{_base}->{$base} ||= $self->SUPER::base;
    $self->{_base}->{$base}->clone;
}

sub uri_for {
     my($self, $path, $args) = @_;
     my $uri = $self->base;
     my $base = $uri->path eq "/"
              ? ""
              : $uri->path;
     $uri->path( $base . $path );
     $uri->query_form(@$args) if $args;
     $uri;
}

sub validator {
    my ($self, $rule) = @_;
    Kossy::Validator->check($self,$rule);
}

1;