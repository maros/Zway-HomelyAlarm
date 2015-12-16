package App::HomelyAlarm::Recipient {
    use 5.016;
    
    use Moose;
    
    use Email::Stuffer;
    
    has 'message' => (
        is              => 'rw',
        isa             => 'App::HomelyAlarm::Message',
        required        => 1,
        weak_ref        => 1,
    );
    
    has 'email' => (
        is              => 'rw',
        isa             => 'Str',
        predicate       => 'has_email'
    );
    
    has 'call' => (
        is              => 'rw',
        isa             => 'Str',
        predicate       => 'has_call'
    );
    
    has 'sms' => (
        is              => 'rw',
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
    
    sub process {
        my ($self) = @_;
        
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
        
        # TODO message id
        Email::Stuffer
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
        
        $app->run_twilio(
            'POST',
            'Messages',
            To              => $self->sms,
            Body            => $message,
            sub {
                my ($data,$headers) = @_;
                $self->sms_sid($data->{sid});
            },
        );
    }
    
    sub run_call {
        my ($self) = @_;
        
        my $app     = App::HomelyAlarm->instance;
        my $message = $self->message->message;
        
        $self->run_twilio(
            'POST',
            'Calls',
            To              => $self->voive,
            Url             => $app->self_url.'/twilio/twiml',
            Method          => 'GET',
            Record          => 'false',
            Timeout         => 60,
            sub {
                my ($data,$headers) = @_;
                $self->call_sid($data->{sid});
            },
        );
    }
}

1;