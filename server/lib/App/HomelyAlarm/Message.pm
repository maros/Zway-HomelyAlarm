package App::HomelyAlarm::Message {
    use 5.016;
    use warnings;
    
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
        required        => 1
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
}