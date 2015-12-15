package App::HomelyAlarm::Message {
    use 5.016;
    
    use Moose;
    
    has 'message' => (
        is              => 'rw',
        isa             => 'Str',
        required        => 1
    );
    
    has 'title' => (
        is              => 'rw',
        isa             => 'Str',
        required        => 1
    );
    
    has 'recipients' => (
        is              => 'rw',
        isa             => 'ArrayRef[App::HomelyAlarm::Recipients]',
        required        => 1,
        default         => sub { [] },
        #traits          => ['Array'],
        #handles          => {
        #    'add_recipient' => 'push'
        #},
    );
    
    has 'type' => (
        is              => 'rw',
        isa             => 'Str',
        required        => 1
    );
    
    sub add_recipient {
        my ($self,%params) = @_;
        
        my $recipient = App::HomelyAlarm::Recipients->new(
            (
                map { $_ => $params{$_} }
                grep { defined $params{$_} }
                qw(email voice sms)
            ),
            message     => $self,
        );
        push (@{$self->recipients},$recipient);
        return $recipient;
    }
    
    sub process {
        my ($self) = @_;
        foreach my $recipient (@{$self->recipients}) {
            $recipient->process();
        }
    }
}