requires 'Regexp::Common';
requires 'Pod::Simple';

on test => sub {
    requires 'Test::More', 0.98;
};

on configure => sub {
};

on 'develop' => sub {
};

