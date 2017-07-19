package App::HomelyAlarm::Recipient {
    use 5.016;

    use Moose;
    no if $] >= 5.018000, warnings => qw(experimental::smartmatch);

    use AnyEvent::HTTP;
    use Email::Stuffer;

    has 'prefered' => (
        is              => 'rw',
        isa             => 'App::HomelyAlarm::Type::Prefered',
        default         => 'call',
    );

    has 'status' => (
        is              => 'rw',
        isa             => 'Str',
        default         => 'init',
    );

    has 'message' => (
        is              => 'ro',
        isa             => 'App::HomelyAlarm::Message',
        required        => 1,
        weak_ref        => 1,
    );

    foreach my $method (keys %App::HomelyAlarm::Type::METHODS) {
        has $method => (
            is              => 'ro',
            isa             => $App::HomelyAlarm::Type::METHODS{$method},
            predicate       => 'has_'.$method
        );
        has "${method}_id" => (
            is              => 'rw',
            isa             => 'Str',
            predicate       => 'has_'.$method.'_id'
        );
    }

    sub set_success {
        my ($self,$source) = @_;
        App::HomelyAlarm::_log('Mark recipient as successful');
        $self->status('success');
    }

    sub set_fail {
        my ($self,$source) = @_;
        App::HomelyAlarm::_log('Mark recipient as failed. Retry if possible');
        $self->status('fail');
        my $id_method = $source.'_id';
        my $has_method = 'has_'.$id_method;
        if (! $self->$has_method) {
            $self->$id_method('fail');
        }
        $self->process;
    }

    sub process {
        my ($self) = @_;

        return
            if $self->status eq 'success';

        App::HomelyAlarm::_log('Processing recipient');

        my @methods = ($self->prefered);
        foreach (qw(pushbullet sms email call)) {
            push(@methods,$_)
                unless $_ ~~ \@methods;
        }

        foreach my $method (@methods) {
            no strict 'refs';
            my $check_id    = 'has_'.$method.'_id';
            my $check       = 'has_'.$method;
            my $process     = 'process_'.$method;

            if ($self->$check && ! $self->$check_id) {
                $self->$process();
                return;
            }
        }
    }

    sub process_email {
        my ($self) = @_;

        my $app     = App::HomelyAlarm->instance;
        my $message = $self->message->message;
        my $type    = $self->message->type;
        my $title   = $self->message->title;

        # TODO sanitize $title, $message, $type

        App::HomelyAlarm::_log('Send email to %s',$self->email);

        my $body = <<MAILBODY;
Zone:     $title
Message:  $message
Type:     $type
--
Sent by HomelyAlarm
MAILBODY
        $body =~ s/\n/\r\n/g;

        # TODO message id
        my $result = Email::Stuffer
            ->from($app->sender_email)
            ->to($self->email)
            ->subject("HomelyAlarm.$type:$message")
            ->text_body($body)
            ->send();
         $self->email_id('ok');
    }

    sub process_sms {
        my ($self) = @_;

        my $app     = App::HomelyAlarm->instance;
        my $message = $self->message->message;

        App::HomelyAlarm::_log('Send SMS to %s',$self->sms);

        $app->run_twilio(
            'POST',
            'Messages',
            To              => $self->sms,
            Body            => $message,
            Fail            => sub {
                $self->set_fail('sms');
            },
            Success         => sub {
                my ($data,$headers) = @_;
                App::HomelyAlarm::_log("Processed SMS %s",$data);
                $self->sms_id($data->{sid});
            },
        );
    }

    sub process_call {
        my ($self) = @_;

        my $app     = App::HomelyAlarm->instance;
        my $message = $self->message->message;

        App::HomelyAlarm::_log('Call %s',$self->call);

        $app->run_twilio(
            'POST',
            'Calls',
            To              => $self->call,
            Url             => $app->self_url.'/twilio/twiml',
            Method          => 'GET',
            Record          => 'false',
            Timeout         => 60,
            Fail            => sub {
                $self->set_fail('call');
            },
            Success         => sub {
                my ($data,$headers) = @_;
                App::HomelyAlarm::_log("Processed call %s",$data);
                $self->call_id($data->{sid});
            },
        );
    }

    sub process_pushbullet {
        my ($self) = @_;

        my $message = $self->message;
        my $app     = App::HomelyAlarm->instance;
        App::HomelyAlarm::_log('Send pushbullet to %s',$self->email);

        my $guard;
        $guard = http_request(
            'POST',
            "https://api.pushbullet.com/v2/pushes",
            timeout => 120,
            headers => {
                'Content-Type'  => 'application/json',
                'Access-Token'  => $self->pushbullet
            },
            body    => JSON::XS::encode_json({
                type        => 'note',
                title       => $message->title,
                body        => $message->message.' ('.$message->type.')',
            }),
            sub {
                my ($data,$headers) = @_;
                $guard = undef;
                if ($headers->{Status} =~ /^2/) {
                    $self->pushbullet_id('ok');
                } else {
                    App::HomelyAlarm::_log("Error sending pushbullet note: %s",$data);
                    $self->set_fail('pushbullet');
                }
            }
        );
    }
}

1;