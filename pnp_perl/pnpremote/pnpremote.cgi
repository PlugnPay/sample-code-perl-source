#!/usr/local/bin/perl
# you may need to change the above perl path

# these scripts and the pnpremote.pm module contain sensitive information
# DO NOT DISTRIBUTE THIS SCRIPT OR pnpremote.pm

require 5.001;
$|=1;

# enter a path to the location of the pnpremote.pm
use lib '';
use pnpremote;
use strict;

#print "Content-type: text/html\n\n";

my(%query);

# this part collects any data to send that was sent to the script and sends it
# to the pnpremote function.  You do not have to use the below to collect the
# data as long as you collect the proper fields in a hash you could
# skip this and continue at the @array = %query line where %query
# is your hash

if (($ENV{'REQUEST_METHOD'} eq "GET") && ($ENV{'QUERY_STRING'} ne '')) {
  $_ = $ENV{'QUERY_STRING'};
}
elsif ($ENV{'REQUEST_METHOD'} eq "POST") {
  read(STDIN,$_, $ENV{'CONTENT_LENGTH'});
}
foreach my $pair (split('&')) {
  if ($pair =~ /(.*)=(.*)/) {
    my ($key,$value) = ($1,$2);
    $value =~ s/%(..)/pack('c',hex($1))/eg;
    $value =~ s/\+/ /g;
    $query{$key} = $value;
  }
}

# the rest of this is very important
my @array = %query;

# does some input testing to make sure everything is set correctly
my $payment = pnpremote->new(@array);

# does the actual connection and purchase. Transaction result is returned in query hash.
# variable to test for success is $query{'FinalStatus'}.  Possible values are success, badcard or problem

%query = $payment->purchase();

# Post Transaction processing. (Optional) 
# Depending on desired behavior and values of 'success-link', 'badcard-link' & 'problem-link'
# this script call either redirect to a web page or perform a post to a different script.
# if you will performing your own validity test on the transaction results, you may comment out the follow line.
$payment->final();

exit;
