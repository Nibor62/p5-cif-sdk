package CIF::SDK::Client;

use strict;
use warnings FATAL => 'all';

use Mouse;
use HTTP::Tiny;
use CIF::SDK qw/init_logging $Logger/;
use JSON::XS qw(encode_json decode_json);
use Time::HiRes qw(tv_interval gettimeofday);
use Carp;

=head1 NAME

CIF::SDK::Client - The SDK Client

=head1 SYNOPSIS

the SDK is a thin development kit for developing CIF applications

    use 5.011;
    use CIF::SDK::Client;
    use feature 'say';

    my $context = CIF::SDK::Client->new({
        token       => '1234',
        remote      => 'https://localhost/api',
        timeout     => 10,
        verify_ssl  => 0,
    });
    
    my ($err,$ret) = $cli->ping();
    say 'roundtrip: '.$ret.' ms';
    
    ($err,$ret) = $cli->search({
        query       => $query,
        confidence  => $confidence,
        limit       => $limit,
    });
    
    my $formatter = CIF::SDK::FormatFactory->new_plugin({ format => '{ json | csv | snort | bro }' });
    my $text = $formatter->process($ret);
    say $text;

=cut

use constant {
    HEADERS => {
        'Accept'  => 'vnd.cif.v'.$CIF::SDK::API_VERSION.'+json',
    },
    AGENT   => 'cif-sdk-perl/'.$CIF::SDK::VERSION,
    TIMEOUT => 300,
    REMOTE  => 'https://localhost',
};

has 'remote' => (
    is      => 'ro',
    default => REMOTE,
);

has [qw(token proxy nolog)] => (
    is  => 'ro'
);

has 'timeout'   => (
    is      => 'ro',
    default => TIMEOUT,
);

has 'headers' => (
    is      => 'ro',
    default => sub { HEADERS },
);

has 'verify_ssl' => (
    is      => 'ro',
    default => 1,
);

has 'handle' => (
    is      => 'ro',
    isa     => 'HTTP::Tiny',
    builder => '_build_handle',
);

# helpers

sub BUILD {
    my $self = shift;
    
    unless($Logger){
        init_logging({
            level       => 'WARN',
            category    => 'CIF::SDK::Client',
        });
    }
}           

sub _build_handle {
    my $self = shift;
    
    return HTTP::Tiny->new(
        agent           => AGENT,
        default_headers => $self->headers,
        timeout         => $self->timeout,
        verify_ssl      => $self->verify_ssl,
        proxy           => $self->proxy,
    );   
}



=head1 Object Methods

=head2 new

=head2 search

=over

  $ret = $client->search({ 
      query         => 'example.com', 
      confidence    => 25, 
      limit         => 500
  });

=back

=cut

sub _make_request {
	my $self 	= shift;
	my $uri	 	= shift;
	my $params 	= shift || {};
	
	$uri = $self->remote.'/'.$uri;
	
	my $token = $params->{'token'} || $self->token;
	
	$uri = $uri.'?token='.$token;

	foreach my $p (keys %$params){
		next unless($params->{$p});
		$uri .= '&'.$p.'='.$params->{$p};
	}
	
	$Logger->debug('uri created: '.$uri);
    $Logger->debug('making request...');
    
    my $resp = $self->handle->get($uri,$params);
    return 'request failed('.$resp->{'status'}.'): '.$resp->{'reason'}.': '.$resp->{'content'} unless($resp->{'status'} eq '200');
    
    $Logger->debug('success, decoding...');
    return undef, decode_json($resp->{'content'});
}

sub search_feed {
    my $self = shift;
    my $args = shift;
    
    return $self->_make_request('feeds',$args);
}

sub search {
    my $self = shift;
    my $args = shift;

    return $self->_make_request('observables',$args);
}

sub search_id {
	my $self 	= shift;
	my $args	= shift;
	
	my $params = {
		id		=> $args->{'id'},
		token	=> $args->{'token'} || $self->token,
	};
	
	return $self->_make_request('observables',$params);
}

=head2 submit

=over

  $ret = $client->submit({ 
      observable    => 'example.com', 
      tlp           => 'green', 
      tags          => ['zeus', 'botnet'], 
      provider      => 'me@example.com' 
  });

=back

=cut

sub submit_feed {
	my $self = shift;
	my $args = shift;
	
	return $self->_submit('feeds',$args);
};

sub submit {
	my $self = shift;
	my $args = shift;
	
    return $self->_submit('observables',$args);
}

sub _submit {
    my $self = shift;
    my $uri = shift;
    my $args = shift;
    
    $args = [$args] if(ref($args) eq 'HASH');
    
    $Logger->debug('encoding args...');
    
    $args = encode_json($args);

    $uri = $self->remote.'/'.$uri.'/?token='.$self->token;
    
    $Logger->debug('uri generated: '.$uri);
    $Logger->debug('making request...');
    my $resp = $self->handle->put($uri,{ content => $args });
    
    unless($resp->{'status'} < 399){
        $Logger->fatal('status: '.$resp->{'status'}.' -- '.$resp->{'reason'});
        croak('submission failed: contact administrator');
    }
    $Logger->debug('decoding response..');
    
    my $content = decode_json($resp->{'content'});
    
    $Logger->debug('success...');
    return (undef, $content, $resp);
}	

=head2 ping

=over

  $ret = $client->ping();

=back

=cut

sub ping {
    my $self = shift;
    $Logger->debug('generating ping...');

    my $t0 = [gettimeofday()];
    
    my $ret = $self->_make_request('ping');
    
    $Logger->debug('sucesss...');
    return undef, tv_interval($t0,[gettimeofday()]);
}

1;
