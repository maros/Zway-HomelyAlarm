package App::HomelyAlarm::Recipient {
    use 5.016;
    
    use Moose;
    
    use Email::Stuffer;
    
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
    
    has 'email' => (
        is              => 'ro',
        isa             => 'Str',
        predicate       => 'has_email'
    );
    
    has 'call' => (
        is              => 'ro',
        isa             => 'Str',
        predicate       => 'has_call'
    );
    
    has 'sms' => (
        is              => 'ro',
        isa             => 'Str',
        predicate       => 'has_sms'
    );
    
    has 'call_sid' => (
        is              => 'rw',
        isa             => 'Str',
        predicate       => 'has_call_sid'
    );
    
    has 'sms_sid' => (
        is              => 'rw',
        isa             => 'Str',
        predicate       => 'has_sms_sid'
    );
    
    has 'email_message_id' => (
        is              => 'rw',
        isa             => 'Str',
        predicate       => 'has_email_message_id'
    );
    
    sub set_success {
        my ($self) = @_;
        $self->status('success');
    }
    
    sub set_fail {
        my ($self) = @_;
        $self->status('fail');
        $self->process;
    }
    
    sub process {
        my ($self) = @_;
        
        return
            if $self->status eq 'success';
        
        if ($self->has_call && ! $self->has_call_sid) {
            $self->process_call();
        } elsif ($self->has_sms && ! $self->has_sms_sid) {
            $self->process_sms();
        } elsif ($self->has_email() && ! $self->has_email_message_id) {
            $self->process_email();
        }
    }
    
    sub process_email {
        my ($self) = @_;
        
        my $app     = App::HomelyAlarm->instance;
        my $message = $self->message->message;
        my $type    = $self->message->type;
        
        Homely::Alarm::_log('Send email to %s',$self->email);
        
        # TODO message id
        my $result = Email::Stuffer
            ->from($app->sender_email)
            ->to($self->email)
            ->subject("HomelyAlarm.$type:$message")
            ->text_body(qq[
                Message:  $message
                Type: $type
                --
                Sent by HomelyAlarm
            ])
            ->send();
    }
    
    sub process_sms {
        my ($self) = @_;
        
        my $app     = App::HomelyAlarm->instance;
        my $message = $self->message->message;
        
        Homely::Alarm::_log('Send SMS to %s',$self->sms);
        
        $app->run_twilio(
            'POST',
            'Messages',
            To              => $self->sms,
            Body            => $message,
            sub {
                my ($data,$headers) = @_;
                Homely::Alarm::_log($data);
                $self->sms_sid($data->{sid});
            },
        );
    }
    
    sub run_call {
        my ($self) = @_;
        
        my $app     = App::HomelyAlarm->instance;
        my $message = $self->message->message;
        
        Homely::Alarm::_log('Call %s',$self->call);
        
        $self->run_twilio(
            'POST',
            'Calls',
            To              => $self->call,
            Url             => $app->self_url.'/twilio/twiml',
            Method          => 'GET',
            Record          => 'false',
            Timeout         => 60,
            sub {
                my ($data,$headers) = @_;
                Homely::Alarm::_log($data);
                $self->call_sid($data->{sid});
            },
        );
    }
}

1;