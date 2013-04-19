package Spellunker;
use strict;
use warnings FATAL => 'all';
use utf8;
use 5.008001;

use version; our $VERSION = version->declare("v0.0.13");

use File::Spec ();
use File::ShareDir ();
use Regexp::Common qw /URI/;

# Ref http://www.din.or.jp/~ohzaki/mail_regex.htm#Simplify
my $MAIL_REGEX = (
    q{(?:[-!#-'*+/-9=?A-Z^-~]+(?:\.[-!#-'*+/-9=?A-Z^-~]+)*|"(?:[!#-\[\]-} .
    q{~]|\\\\[\x09 -~])*")@[-!#-'*+/-9=?A-Z^-~]+(?:\.[-!#-'*+/-9=?A-Z^-~]+} .
    q{)*}
);

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    my $self = bless {}, $class;

    # From https://code.google.com/p/dotnetperls-controls/downloads/detail?name=enable1.tx
    $self->load_dictionary(File::Spec->catfile(File::ShareDir::dist_dir('Spellunker'), 'enable1.txt'));
    $self->load_dictionary(File::Spec->catfile(File::ShareDir::dist_dir('Spellunker'), 'spellunker-dict.txt'));

    unless ($ENV{PERL_SPELLUNKER_NO_USER_DICT}) {
        $self->_load_user_dict();
    }
    return $self;
}

sub _load_user_dict {
    my $self = shift;
    my $home = $ENV{HOME};
    return unless defined $home;
    return unless -d $home;
    my $dictpath = File::Spec->catfile($home, '.spellunker.en');
    if (-f $dictpath) {
        $self->load_dictionary($dictpath);
    }
}

sub load_dictionary {
    my ($self, $filename) = @_;
    open my $fh, '<:utf8', $filename
        or die "Cannot open '$filename' for reading: $!";
    while (defined(my $line = <$fh>)) {
        chomp $line;
        $line =~ s/\s*#.*$//; # remove comments.
        $self->add_stopwords(split /\s+/, $line);
    }
}

sub add_stopwords {
    my $self = shift;
    for (@_) {
        $self->{stopwords}->{$_}++
    }
    return undef;
}

sub check_word {
    my ($self, $word) = @_;
    return 0 unless defined $word;

    return 1 if _is_perl_code($word);

    # There is no alphabetical characters.
    return 1 if $word !~ /[A-Za-z]/;

    if ($word =~ /\A_([a-z]+)_\z/) {
        return $self->check_word($1);
    }

    # 19xx 2xx
    return 1 if $word =~ /^[0-9]+(xx|yy)$/;

    # Method name
    return 1 if $word =~ /\A([a-zA-Z0-9]+_)+[a-zA-Z0-9]+\z/;

    # Ignore apital letter words like RT, RFC, IETF.
    # And so "IT'S" should be allow.
    return 1 if $word =~ /\A[A-Z']+\z/;

    # "foo" - quoted word
    if (my ($body) = ($word =~ /\A"(.+)"\z/)) {
        return $self->check_word($body);
    }

    # good
    return 1 if $self->{stopwords}->{$word};

    # ucfirst-ed word.
    # 'How'
    # Dan
    if ($word =~ /\A[A-Z][a-z]+\z/) {
        return 1;
    }

    # AUTHORS
    if ($word =~ /\A[A-Z]+\z/) {
        return 1 if $self->{stopwords}->{lc $word};
    }

    # Dan's
    return 1 if $word =~ /\A(.*)'s\z/ && $self->check_word($1);
    # cookies'
    return 1 if $word =~ /\A(.*)s'\z/ && $self->check_word($1);
    # You've
    return 1 if $word =~ /\A(.*)'ve\z/ && $self->check_word($1);
    # We're
    return 1 if $word =~ /\A(.*)'re\z/ && $self->check_word($1);
    # You'll
    return 1 if $word =~ /\A(.*)'ll\z/ && $self->check_word($1);
    # doesn't
    return 1 if $word =~ /\A(.*)n't\z/ && $self->check_word($1);
    # You'd
    return 1 if $word =~ /\A(.*)'d\z/ && $self->check_word($1);
    # Perl-ish
    return 1 if $word =~ /\A(.*)-ish\z/ && $self->check_word($1);
    # {at}
    return 1 if $word =~ /\A\{(.*)\}\z/ && $self->check_word($1);
    # com>
    return 1 if $word =~ /\A(.*)>\z/ && $self->check_word($1);

    # comE<gt>
    ## Prefixes
    return 1 if $word =~ /\Anon-(.*)\z/ && $self->check_word($1);
    return 1 if $word =~ /\Are-(.*)\z/ && $self->check_word($1);

    if ($word =~ /-/) {
        my @words = split /-/, $word;
        my $ok = 0;
        for (@words) {
            if ($self->check_word($_)) {
                $ok++;
            }
        }
        return 1 if @words == $ok;
    }

    return 0;
}

sub check_line {
    my ($self, $line) = @_;
    return unless defined $line;

    $line = $self->_clean_text($line);
    return unless defined $line;

    my @bad_words;
    for ( grep /\S/, split /[#~\|*=\[\]\/`"< \t,.()?;!]+/, $line) {
        s/\n//;

        if (/\A'(.*)'\z/) {
            push @bad_words, $self->check_line($1);
        } else {
            next if length($_)==0;
            next if length($_)==1;
            next if /^[0-9]+$/;
            next if /^[A-Za-z]$/; # skip single character
            next if /^\\?[%\$\@*][A-Za-z_][A-Za-z0-9_]*$/; # perl variable

            # Ignore Text::MicroTemplate code.
            # And do not care special character only word.
            next if /\A[<%>\\.\@%#_]+\z/; # special characters

            # JSON::XS-ish boolean value
            next if /\A\\[01]\z/;

            # Ignore command line options
            next if /\A
                --
                (?: [a-z]+ - )+
                [a-z]+
            \z/x;

            $self->check_word($_)
                or push @bad_words, $_;
        }
    }
    return @bad_words;
}

    # Perl method call
sub _is_perl_code {
    my $PERL_NAME = '[A-Za-z_][A-Za-z0-9_]*';

    # Class name
    # Foo::Bar
    return 1 if $_[0] =~ /\A
        (?: $PERL_NAME :: )+
        $PERL_NAME
    \z/x;

    # Spellunker->bar
    # Foo::Bar->bar
    # $foo->bar
    # $foo->bar()
    return 1 if $_[0] =~ /\A
        (?:
            \$ $PERL_NAME
            | ( $PERL_NAME :: )* $PERL_NAME
        )
        ->
        $PERL_NAME
        (?:\([^\)]*\))?
    \z/x;

    # hash access
    return 1 if $_[0] =~ /\A
        \$ $PERL_NAME \{ $PERL_NAME \}
    \z/x;

    return 0;
}

sub _clean_text {
    my ($self, $text) = @_;
    return unless $text;

    $text =~ s!<$MAIL_REGEX>|$MAIL_REGEX!!; # Remove E-mail address.
    $text =~ s!$RE{URI}{HTTP}!!g; # Remove HTTP URI
    $text =~ s!\(C\)!!gi; # Copyright mark
    $text =~ s/\s+/ /gs;
    $text =~ s/[()\@,;"\/.]+/ /gs;     # Remove punctuation

    return $text;
}

1;
__END__

=encoding utf-8

=head1 NAME

Spellunker - Pure perl spelling checker implementation

=head1 DESCRIPTION

Spellunker is pure perl spelling checker implementation.
You can use this spelling checker as a library.

And this distribution provides L<spellunker> and L<spellunker-pod> command.

If you want to use this spelling checker in test script, you can use L<Test::Spellunker>.

=head1 METHODS

=over 4

=item my $spellunker = Spellunker->new();

Create new instance.

=item $spellunker->add_stopwords(@stopwords)

Add some C<< @stopwords >> to the on memory dictionary.

=item $spellunker->check_word($word);

Check the word looks good or not.

=item @bad_words = $spellunker->check_line($line)

Check the text and returns bad word list.

=back

=head1 HOW DO I USE CUSTOM DICTIONARY?

You can put your personal dictionary at C<$HOME/.spellunker.en>.

=head1 LICENSE

Copyright (C) tokuhirom

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

tokuhirom E<lt>tokuhirom@gmail.comE<gt>

