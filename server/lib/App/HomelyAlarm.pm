package App::HomelyAlarm {
    use 5.016;
    
    use App::HomelyAlarm::Message;
    use App::HomelyAlarm::Recipient;
    
    use MooseX::App::Simple qw(Config);
    
    no if $] >= 5.018000, warnings => qw(experimental::smartmatch);
    
    our $INSTANCE;
    
    use AnyEvent::HTTP;
    use Twiggy::Server;
    use AnyEvent;
    use Plack::Request;
    use Try::Tiny;
    use JSON::XS;
    use Digest::HMAC_SHA1 qw(hmac_sha1_hex hmac_sha1);
    use MIME::Base64 qw(encode_base64);
    use URI::Escape qw(uri_escape);
    use Email::Stuffer;
    
    option 'port' => (
        is              => 'rw',
        isa             => 'Int',
        documentation   => 'Listening port',
        default         => 1222,
    );

    option 'host' => (
        is              => 'rw',
        isa             => 'Str',
        documentation   => 'Bind host',
        default         => 'localhost',
    );
    
    option 'secret' => (
        is              => 'rw',
        isa             => 'Str',
        documentation   => 'Alarm server secret',
        required        => 1,
    );
    
    option 'twilio_sid' => (
        is              => 'ro',
        isa             => 'Str',
        documentation   => 'Twilio Account SID',
        required        => 1,
    );
    
    option 'twilio_authtoken' => (
        is              => 'ro',
        isa             => 'Str',
        documentation   => 'Twilio Authentication Token',
        required        => 1,
    );
    
    option 'caller_number' => (
        is              => 'ro',
        isa             => 'Str',
        documentation   => 'Caller telephone number',
        required        => 1,
    );
    
    option 'sender_email' => (
        is              => 'ro',
        isa             => 'Str',
        documentation   => 'Sender e-mail address',
        required        => 1,
    );
    
    has 'timer' => (
        is              => 'rw',
        isa             => 'HashRef',
        traits          => ['Hash'],
        handles         => {
            has_timer       => 'defined',
            clear_timer     => 'delete',
        },
        default         => sub { retun {} },
    );

    has 'self_url' => (
        is              => 'rw',
        predicate       => 'has_self_url',
    );
    
    sub instance {
        return $INSTANCE;
    }
    
    sub run {
        my ($self) = @_;
        
        die("Only one instance of __PACKAGE__ allowed")
            if defined $INSTANCE;
        
        $INSTANCE = $self;
 
        # Initalize condvar
        my $cv = AnyEvent->condvar;
        
        # Signal handler
        my $term_signal = AnyEvent->signal(
            signal  => "TERM", 
            cb      => sub { 
                _log('Recieved INT signal');
                $cv->send;
            }
        );
        my $int_signal = AnyEvent->signal(
            signal  => "INT", 
            cb      => sub { 
                _log('Recieved INT signal');
                $cv->send;
            }
        );
        
        _log('Startup server at %s:%i',$self->host,$self->port);
        
        # Start server
        my $server = Twiggy::Server->new(
            host => $self->host,
            port => $self->port,
        );
        
        # Register service
        $server->register_service($self->app);
        
        $cv->recv;
        
        _log('End loop');
        
        $INSTANCE = undef;
    }
    
    sub app {
        my ($self) = @_;
        
        return sub {
            my ($env)   = @_;

            _log("HomelyAlarm needs a server that supports psgi.streaming and psgi.nonblocking")
                unless ($env->{'psgi.streaming'} && $env->{'psgi.nonblocking'}) 
                || $ENV{HARNESS_ACTIVE};
            
            my $req     = Plack::Request->new($env);
            my @paths   = grep { $_ } split('/',$req->path_info);
            
            return _reply_error(404,"Not Found",$req)
                if scalar @paths != 2
                || $req->path_info =~ /_/;
            
            my $method  = join('_','dispatch',$req->method,@paths);
            my $authen  = join('_','authenticate',$paths[0]);
            
            unless ($self->has_self_url) {
                my $url = $req->scheme.'://'.$req->env->{HTTP_HOST};
                $self->self_url($url);
            }
            
            my $coderef = $self->can($method);
            if ($coderef) {
                if ($self->can($authen) && ! $self->$authen($req)) {
                    return _reply_error(401,"Not authorized",$req);
                }
                _log("Handling $method");
                
                my $response = try {
                    return $self->$coderef($req);
                } catch {
                    _log("Error processing $method: $_");
                    return _reply_error(500,"Internal Server Error",$req)
                }
            } else {
                return _reply_error(404,"Not Found",$req)
            }
        };
    }
    
    sub dispatch_POST_alarm_delayed {
        my ($self,$req) = @_;
        
        my $data = _body_data($req);
        
        unless ($self->has_timer($data->{type})) {
            $self->add_timer($data->{type},$data->{delay},$data);
        }
        
        return _reply_ok();
    }
    
    sub dispatch_POST_alarm_cancel {
        my ($self,$req) = @_;
        
        my $data = _body_data($req);
        
        _log("Cancel %s alarm timer",$data->{type});
        
        $self->clear_timer($data->{type});
        return _reply_ok();
    }
    
    sub dispatch_POST_alarm_start {
        my ($self,$req) = @_;
        
        my $data = _body_data($req);
        
        _log("Immediate %s alarm",$data->{type});
        
        $self->run_notify($data);
        
        return _reply_ok();
    }
    
    sub dispatch_POST_alarm_warning {
        my ($self,$req) = @_;
        
        my $data = _body_data($req);
        
        _log("%s messge",$data->{type});
        
        $self->run_notify($data);
        
        return _reply_ok();
    }
    
    sub dispatch_POST_twilio_status {
        my ($self,$req) = @_;
        
        my $sid;
        
        if ($sid = $req->param('CallSid')) {
            my $message = App::HomelyAlarm::MessageLog->find_message($self->storage,$sid);
            return _reply_error(404,"Call not found",$req)
                unless $message;
            
            
            _log("Transaction status ".$message->recipient->telephone.": ".$req->param('CallStatus'));
            if ($req->param('CallStatus') ne 'completed') {
                # send fallback SMS
                $message->set_failed($self->storage);
                $self->run_sms($message->recipient,$message->message,$message->severity);
            } else {
                $message->set_success($self->storage);
            }
        } elsif ($sid = $req->param('SmsSid')) {
            my $message = App::HomelyAlarm::MessageLog->find_message($self->storage,$sid);
            return _reply_error(404,"SMS not found",$req)
                unless $message;
            
            _log("SMS status ".$message->recipient->telephone.": ".$req->param('SmsStatus'));
            if ($req->param('SmsStatus') ne 'completed') {
                $message->set_failed($self->storage);
            } else {
                $message->set_success($self->storage);
            }
        } else {
            return _reply_error(404,"Missing parameters",$req);
        }
        
        return _reply_ok();
    }
    
    sub dispatch_GET_twilio_twiml {
        my ($self,$req) = @_;
        
        my $call = App::HomelyAlarm::MessageLog->find_message($self->storage,$req->param('CallSid'));
        return _reply_error(404,"Call not found",$req)
            unless $call;
        
        my $message = $call->message;
        $message =~ s/&/&amp;/g;
        $message =~ s/>/&gt;/g;
        $message =~ s/</&lt;/g;
        $message =~ s/'/&apos;/g;
        $message =~ s/"/&quot;/g;
        
        return [
            200,
            [ 'Content-Type' => 'text/xml' ],
            [ <<TWIML
<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Say voice="woman" language="en-US">$message</Say>
    <Hangup/>
</Response>
TWIML
            ],
        ];
    }
    
    sub run_twilio {
        my $self = shift;
        my $method = shift;
        my $action = shift;
        my $callback = pop;
        my %args = @_;
        
        my $url = 'https://api.twilio.com/2010-04-01/Accounts/'.$self->twilio_sid.'/'.$action.'.json';
        
        my %params = (
            timeout => 120,
            headers => {
                'Authorization' => 'Basic '.MIME::Base64::encode($self->twilio_sid.":".$self->twilio_authtoken, ''),
            },
        );
        
        my $content = '';
        my @args;
        
        for my $key ( keys %args ) {
            $args{$key} = ( defined $args{$key} ? $args{$key} : '' );
            push @args, uri_escape($key) . '=' . uri_escape($args{$key});
        }
        $content = join('&', @args) || '';
        
        if( $method eq 'GET' ) {
            $url .= '?' . $content;
        } elsif ($method eq 'POST') {
            $params{headers}{'Content-Type'} = 'application/x-www-form-urlencoded';
            $params{body} = $content;
        }
        
        _log("Twilio request $method $url");
        
        my $guard;
        $guard = http_request( 
            $method,
            $url, 
            %params, 
            sub {
                my ($data,$headers) = @_;
                
                $guard = undef;
                my $api_response = decode_json($data);
                if ($headers->{Status} =~ /^2/) {
                    $callback->($api_response,$headers);
                } else {
                    _log("Error placing call: ".$data)
                }

            }
        );
    }
    
    sub run_email {
        my ($self,$recipient,$message,$severity) = @_;
        
        unless ($recipient->has_email) {
            $self->run_sms($recipient,$message,$severity)
                if $recipient->has_telephone;
            return;
        }
        
        $recipient->add_message($self->storage,
            message     => $message,
            mode        => 'email',
            severity    => $severity,
            reference   => 'TODO msgid',
        );
        
        Email::Stuffer
            ->from($self->sender_email)
            ->to($recipient->email)
            ->subject('HomelyAlarmAlert:'.$message)
            ->text_body(qq[
                Message:  $message
                Severity: $severity
                --
                Sent by HomelyAlarm
            ])
            ->send();
    }
    
    sub run_sms {
        my ($self,$recipient,$message,$severity) = @_;
        
        unless ($recipient->has_telephone) {
            $self->run_email($recipient,$message,$severity)
                if $recipient->has_email;
            return;
        }
                
        $self->run_twilio(
            'POST',
            'Messages',
            From            => $self->caller_number,
            To              => $recipient->telephone,
            Body            => $message,
            StatusCallback  => $self->self_url.'/twilio/status',
            StatusMethod    => 'POST',
            sub {
                my ($data,$headers) = @_;
                $recipient->add_message(
                    $self->storage,
                    message     => $message,
                    mode        => 'sms',
                    severity    => $severity,
                    reference   => $data->{sid},
                );
            },
        )
    }
    
    sub run_call {
        my ($self,$recipient,$message,$severity) = @_;
        
        unless ($recipient->has_telephone) {
            $self->run_email($recipient,$message,$severity)
                if $recipient->has_email;
            return;
        }
        
        $self->run_twilio(
            'POST',
            'Calls',
            From            => $self->caller_number,
            To              => $recipient->telephone,
            Url             => $self->self_url.'/twilio/twiml',
            Method          => 'GET',
            StatusCallback  => $self->self_url.'/twilio/status',
            StatusMethod    => 'POST',
            Record          => 'false',
            Timeout         => 60,
            sub {
                my ($data,$headers) = @_;
                $recipient->add_message(
                    $self->storage,
                    message     => $message,
                    mode        => 'call',
                    severity    => $severity,
                    reference   => $data->{sid},
                );
            },
        );
    }

    sub run_notify {
        my ($self,$payload) = @_;
        
        
        
#        _log("Running $severity priority alarm: $message");
#        
#        $severity //= 'medium';
#        
#        my $severity_level = App::HomelyAlarm::Utils::severity_level($severity);
#        
#        RECIPIENT:
#        foreach my $recipient (App::HomelyAlarm::Recipient->list($self->storage)) {
#            my $recipient_severity_level = $recipient->severity_level;
#            if (defined $recipient_severity_level
#                && $recipient_severity_level > $severity_level) {
#                _log("Skip ".$recipient->stringify(1).": Severity ".$recipient->severity);
#                next;
#            };
#            
#            my $last_message = $recipient->last_message($self->storage);
#            
#            if (defined $last_message
#                && $last_message->message eq $message
#                && $last_message->ago < 60*10
#                && $last_message->status ~~ [qw(1 0)]) {
#                _log("Skip ".$recipient->stringify(1).": Duplicate message");
#                next;
#            }
#            
#            _log("Notifying ".$recipient->stringify(1));
#            
#            given ($severity) {
#                when ('low') {
#                    $self->run_email($recipient,$message,$severity);
#                }
#                when ('medium') {
#                    $self->run_sms($recipient,$message,$severity);
#                }
#                when ('high') {
#                    $self->run_call($recipient,$message,$severity);
#                }
#            }
#        }
    }
    
    sub authenticate_alarm {
        my ($self,$req) = @_;

        my $signature = $req->header('X-HomelyAlarm-Signature');
        
        my $content;
        if ($req->method eq 'POST' || $req->method eq 'PUT') {
            $content = $req->content;
        } else {
            $content = $req->uri;
        }
        
        if (defined $signature) {
            my $digest = hmac_sha1_hex($content, $self->secret);
            return 1
                if ($signature eq $digest);
        }
        return 1;
        _log('Could not authenticate alarm');
        return 0;
    }
    
    sub authenticate_twilio {
        my ($self,$req) = @_;
        my $sid         = $req->param('AccountSid');
        my $signature   = $req->header('X-Twilio-Signature');
        my $key         = $req->uri;
        if ($req->method eq 'POST') {
            my $body = $req->body_parameters;
            $key .= join('',map { $_.$body->{$_} } sort keys %{$body});
        }
        my $digest      = encode_base64(hmac_sha1($key, $self->twilio_authtoken));
        chomp($digest);
        
        unless (defined $sid
            && $sid eq $self->twilio_sid
            && defined $signature
            && $signature eq $digest) {
            _log('Could not authenticate call');
            return 0;
        }
        
        return 1;
    }
    
    sub has_timer {
        my ($self,$id,$data) = @_;
        
        my $timer = $data->{type};
        return defined $self->timer->{$timer};
    }
    
    sub add_timer {
        my ($self,$id,$delay,$data) = @_;
        
        log("Start %s alarm timer",$id);
        $self->timer->{$id} = AnyEvent->timer( 
            after   => $delay || 60, 
            cb      => sub { 
                $self->clear_timer($id)
                $self->run_notify($data);
            }
        );
    }
    
    sub _log {
        my ($message,@params) = @_;
        say STDERR "[LOG] ".sprintf($message,@params);
    }
    
    sub _reply_ok {
        my ($message) = @_;
        $message ||= 'OK';
        return [
            200,
            [ 'Content-Type' => 'text/plain' ],
            [ $message ],
        ];
    }
    
    
    sub _body_data {
        my ($req) = @_;
        
        if (($req->method eq 'POST' || $req->method eq 'PUT') 
            && $req->header('Content-Type') eq 'application/json') {
            return JSON::XS::decode_json($req->content)
        }
        return;
    }
    
    sub _reply_error {
        my ($code,$message,$req) = @_;
        
        _log("Invalid request to %s: %s (%i)",$req->uri,$message,$code);
        return [
            $code,
            [ 'Content-Type' => 'application/json' ],
            [ JSON::XS::encode_json({ type => 'error', code => $code, message => $message }) ],
        ];
    }
    
    __PACKAGE__->meta->make_immutable;
    
=head1 NAME

App::HomelyAlarm::Command::Run - Run the HomelyAlarm Server

=cut
}

App::HomelyAlarm::TimerManager {}

1;
