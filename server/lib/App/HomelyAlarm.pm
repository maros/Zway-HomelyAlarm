package App::HomelyAlarm {
    use 5.016;
    
    use App::HomelyAlarm::Type;
    use App::HomelyAlarm::Message;
    use App::HomelyAlarm::Recipient;
    
    use MooseX::App::Simple qw(Config);
    
    no if $] >= 5.018000, warnings => qw(experimental::smartmatch);
    
    our $INSTANCE;
    my %LANGUAGES = (
        en  => 'en-GB',
        es  => 'es-ES',
        fr  => 'fr-FR',
        it  => 'it-IT',
        da  => 'da-DK',
        ru  => 'ru-RU',
        sv  => 'sv-SE',
        cn  => 'zh-CN',
    );
    
    use AnyEvent::HTTP;
    use Twiggy::Server;
    use AnyEvent;
    use Plack::Request;
    use Try::Tiny;
    use JSON::XS;
    use Digest::HMAC_SHA1 qw(hmac_sha1_hex hmac_sha1);
    use MIME::Base64 qw(encode_base64);
    use URI::Escape qw(uri_escape);
    
    option 'duplicate_timeout' => (
        is              => 'rw',
        isa             => 'Int',
        documentation   => 'Number of minutes between two identical messages',
        default         => 60,
    );
    
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
        isa             => 'App::HomelyAlarm::Type::Telephone',
        documentation   => 'Caller telephone number',
        required        => 1,
    );
    
    option 'sender_email' => (
        is              => 'ro',
        isa             => 'App::HomelyAlarm::Type::Email',
        documentation   => 'Sender e-mail address',
        required        => 1,
    );
    
    has 'timer' => (
        is              => 'ro',
        isa             => 'HashRef',
        traits          => ['Hash'],
        handles         => {
            has_timer       => 'defined',
            clear_timer     => 'delete',
        },
        default         => sub { return {} },
    );
    
     has 'messages' => (
        is              => 'ro',
        isa             => 'ArrayRef[App::HomelyAlarm::Message]',
        traits          => ['Array'],
        handles         => {
            add_message     => 'unshift',
            all_messages    => 'elements',
            message_index   => 'first_index',
            message_delete  => 'delete',
            
        },
        default         => sub { return [] },
    );

    has 'self_url' => (
        is              => 'rw',
        predicate       => 'has_self_url',
    );
    
    sub instance {
        return $INSTANCE;
    }
    
    sub remove_message {
        my ($self,$message) = @_;
        my $index = $self->message_index($message);
        $self->message_delete($index);
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
                _log('Recieved TERM signal');
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
        
        _log('Shutdown server');
        
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
        
        _log('Got %s',$req->body_parameters);
        
        if ($sid = $req->param('CallSid')) {
            my $recipient = $self->find_recipient( call_id => $sid );
            return _reply_error(404,"Call not found",$req)
                unless $recipient;
            
            _log("Call status ".$recipient->call.": ".$req->param('CallStatus'));
            if ($req->param('CallStatus') ne 'completed') {
                # send fallback SMS
                $recipient->set_fail('call');
            } else {
                $recipient->set_success('call');
            }
        } elsif ($sid = $req->param('SmsSid')) {
            my $recipient = $self->find_recipient( sms_id => $sid);
            return _reply_error(404,"SMS not found",$req)
                unless $recipient;
            
            _log("SMS status ".$recipient->sms.": ".$req->param('SmsStatus'));
            if ($req->param('SmsStatus') eq 'delivered') {
                $recipient->set_fail('sms');
            } else {
                $recipient->set_success('sms');
            }
        } else {
            return _reply_error(404,"Missing parameters",$req);
        }
        
        return _reply_ok();
    }
    
    sub dispatch_GET_twilio_twiml {
        my ($self,$req) = @_;
        
        my $recipient = $self->find_recipient( call_id => $req->param('CallSid'));
        return _reply_error(404,"Call not found",$req)
            unless $recipient;
        
        my $message = $recipient->message;
        my $text = $message->message;
        $text =~ s/&/&amp;/g;
        $text =~ s/>/&gt;/g;
        $text =~ s/</&lt;/g;
        $text =~ s/'/&apos;/g;
        $text =~ s/"/&quot;/g;
        
        my $language    = $message->language;
        
        if ($language =~ /^[A-Za-z]{2}$/
            && defined $LANGUAGES{lc($language)}) {
            $language = $LANGUAGES{$language};
        } elsif ($language !~ /^[a-z]-[A-Z]$/) {
            _log('Invalid language %s. Fallback to en-GB',$language);
            $language = 'en-GB';
        }
        
        # More than one participant - start a conference
        my $conference = '';
        my @recipients = $message->find_recipients(sub { $_->has_call });
        if (scalar @recipients) {
            $conference = qq[<Dial timeLimit="300"><Conference beep="false" startConferenceOnEnter="true" endConferenceOnExit="true">].
                $message->type.
                q[</Conference></Dial>];
        }
        
        return [
            200,
            [ 'Content-Type' => 'text/xml' ],
            [ <<TWIML
<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Say voice="alice" language="$language">$text</Say>
    $conference
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
        $args{From} ||= $self->caller_number;
        $args{StatusCallback} ||= $self->self_url.'/twilio/status';
        $args{StatusMethod} ||= 'POST';
        
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
                    _log("Error placing call: ".$data);
                }

            }
        );
    }
    
    sub run_notify {
        my ($self,$payload) = @_;
        
        my $message = App::HomelyAlarm::Message->new(
            (
                map { $_ => $payload->{$_} }
                grep { defined  $payload->{$_} }
                qw(message title type language)
            )
        );
        
        foreach my $previous ($self->all_messages) {
            if ($previous->type eq $message->type) {
                _log("Ignoring message. Same message already in queue");
                return;
            }
        }
        
        foreach my $recipient (@{$payload->{recipients}}) {
            $message->add_recipient($recipient);
        }
        
        $message->process();
        $self->add_message($message);
    }
    
    sub find_recipient {
        my ($self,%params) = @_;
        
        foreach my $message ($self->all_messages) {
            RECIPIENT:foreach my $recipient ($message->all_recipients) {
                foreach my $key (keys %params) {
                    next RECIPIENT
                        unless ($recipient->$key eq $params{$key});
                }
                return $recipient;
            }
        }
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
    
    sub add_timer {
        my ($self,$id,$delay,$data) = @_;
        
        _log("Start %s alarm timer",$id);
        $self->timer->{$id} = AnyEvent->timer( 
            after   => $delay || 60, 
            cb      => sub { 
                $self->clear_timer($id);
                $self->run_notify($data);
            }
        );
    }
    
    sub _log {
        my ($message,@params) = @_;
        if (scalar @params) {
            $message = sprintf($message,@params);
        }
        say STDERR "[LOG] ".$message;
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
            my $json = JSON::XS::decode_json($req->content);
            return $json;
        }
        
        warn "No PUT/POST with valid content type";
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

1;
