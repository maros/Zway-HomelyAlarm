package App::HomelyAlarm::Type {
    use 5.016;
    use warnings;
    
    use Moose::Util::TypeConstraints;
    
    enum 'App::HomelyAlarm::Type::Prefered', [qw(call sms email)];
    
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