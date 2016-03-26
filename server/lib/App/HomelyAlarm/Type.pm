package App::HomelyAlarm::Type {
    use 5.016;
    use warnings;
    
    use Moose::Util::TypeConstraints;
    
    our %METHODS = (
        email       => 'App::HomelyAlarm::Type::Email',
        call        => 'App::HomelyAlarm::Type::Telephone',
        sms         => 'App::HomelyAlarm::Type::Telephone',
        pushbullet  => 'Str',
    );
    
    enum 'App::HomelyAlarm::Type::Prefered', [keys %METHODS];
    
    subtype 'App::HomelyAlarm::Type::Email',
        as 'Str',
        where { m/^[[:alnum:].-]+\@[[:alnum:].-]+$/ },
        message { 'Not a valid e-mail address' };
    
    subtype 'App::HomelyAlarm::Type::Telephone',
        as 'Str',
        where { m/^(00|\+)\d+$/ },
        message { 'Not a valid telephone number (needs to begin with intl. prefix)' };
}

1;