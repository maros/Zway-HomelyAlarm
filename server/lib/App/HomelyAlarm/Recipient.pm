package App::HomelyAlarm::Recipient {
    use 5.016;
    
    use Moose;
    
    has 'email' => (
        is              => 'rw',
        isa             => 'Str',
        predicate       => 'has_email'
    );
    
    has 'voice' => (
        is              => 'rw',
        isa             => 'Str',
        predicate       => 'has_voice'
    );
    
    has 'sms' => (
        is              => 'rw',
        isa             => 'Str',
        predicate       => 'has_sms'
    );
}