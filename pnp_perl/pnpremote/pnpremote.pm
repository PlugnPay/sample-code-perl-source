#!/usr/local/bin/perl
$| = 1;

package pnpremote;

#  Package pnpremote.pm  Ver.  1.5  02/04/2003
#                                                   
#  Copyright Plug and Pay Technologies, Inc. 1999-2003
#  This software is for use by customers of         
#  Plug and Pay Technologies, Inc and their         
#  authorized representatives only.                 
#                                                   
#
#  PERL Modules required: Available from CPAN
#  libwww
#      requires:
#      URI
#      MIME-Base64
#      HTML-Parser
#      libnet
#      Digest::MD5
#  Data-Dumper-2.101
#  LWP::UserAgent with SSL support
#      requires
#      Crypt::SSLeay
#      OpenSSL-0.9.6  (try http://www.openssl.org/)
#  Time::Local;
#  IO::Socket;
#  Socket;
#
#  CHANGELOG:
#  03/04/2003 changed required list
#  12/16/2002 added check support modified formpost to use LWP cleaned up a bit
#  07/20/2001 removed local in new so pnpremote.cgi works correctly
#  05/26/2000 removed orderID generation from new should be handled by mckutils::new
#  06/08/2000 fixed luhn10 check so if mode is not empty or auth luhn10 is called with 41111...
#  02/28/2001 modified to follow "strict" guidelines

require 5.001;
 
use LWP::UserAgent;
use Time::Local;
use IO::Socket;
use Socket; 
use strict;

my $version = "PERL.1.5";

sub new {
  my $type = shift;
  %pnpremote::query = @_;
  $pnpremote::query{'version'} = $version;
  $pnpremote::query{'IPaddress'} = $ENV{'REMOTE_ADDR'};
  $pnpremote::query{'User-Agent'} = $ENV{'HTTP_USER_AGENT'};

  $pnpremote::query{'path_merchant'} = "https://pay1.plugnpay.com/payment/pnpremote.cgi";
 
  return [], $type;
}


sub purchase {

  # Card number filter
  $pnpremote::query{'card-number'} =~ s/[^0-9]//g;
  $pnpremote::query{'card-number'} = substr($pnpremote::query{'card-number'},0,20);

  # Expiration Date Filter
  my $card_exp = $pnpremote::query{'card-exp'};
  $card_exp =~ s/[^0-9]//g;
  my $length = length($card_exp);
  my $year = substr($card_exp,-2);
  if ($length == 4) {
    $pnpremote::query{'card-exp'} = substr($card_exp,0,2) . "/" . $year;
  }
  elsif ($length == 3) {
    $pnpremote::query{'card-exp'} = "0" . substr($card_exp,0,1) . "/" . $year;
  }
  $pnpremote::query{'month-exp'} = substr($pnpremote::query{'month-exp'},0,2);
  $pnpremote::query{'year-exp'} = substr($pnpremote::query{'year-exp'},0,2);
  if ($pnpremote::query{'month-exp'} ne "") {
    $pnpremote::query{'card-exp'} = $pnpremote::query{'month-exp'} . "/" . $pnpremote::query{'year-exp'};
  }

  # Email Address Filter
  $pnpremote::query{'email'} =~ s/\;/\,/g;
  $pnpremote::query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.\,]//g;

  # Card Amount Filter
  $pnpremote::query{'card-amount'} =~ s/[^0-9\.]//g;

  my ($luhntest);
  if (($pnpremote::query{'mode'} eq "") || ($pnpremote::query{'mode'} eq "auth")) {
    if (($pnpremote::query{'routingnum'} ne "") && ($pnpremote::query{'accountnum'} ne "") && ($pnpremote::query{'accttype'} ne "")) {
      $luhntest = &modulus10($pnpremote::query{'card-number'});
    }
    else {
      $luhntest = &luhn10($pnpremote::query{'card-number'});
    }
  }
  else {
    $luhntest = &luhn10("4111111111111111");
  }

  if ($luhntest ne "failure") {
    if ($pnpremote::query{'mode'} eq "") {
      $pnpremote::query{'mode'} = "auth";
    }
    my @array = %pnpremote::query;
    my $page = &formpost($pnpremote::query{'path_merchant'},@array);
    
    if ($page eq "") {
      $pnpremote::query{'FinalStatus'} = "problem";
      $pnpremote::query{'MErrMsg'} = "Unable to connect to payment gateway.";
    }
    else {
      %pnpremote::query = &split_hash($page);
    }
  }
  else {
    $pnpremote::query{'FinalStatus'} = "badcard";
    $pnpremote::query{'MErrMsg'} = "The Credit Card entered is not a valid credit card number.  It failed a Luhn-10 checksum test."; 
  }
  return %pnpremote::query;
}


sub split_hash {
  my($page) = @_;
  foreach my $pair (split('&',$page)) {
    if ($pair =~ /(.*)=(.*)/) {
      my ($key,$value) = ($1,$2);
      $key =~ s/%(..)/pack('c',hex($1))/eg;
      $key =~ s/\+/ /g;
      $value =~ s/%(..)/pack('c',hex($1))/eg;
      $value =~ s/\+/ /g;
      $pnpremote::query{$key} = $value;
    }
  }
  return (%pnpremote::query);
}


sub final {

  if ($pnpremote::query{'FinalStatus'} eq "success") {
    if ($pnpremote::query{'success-link'} =~ /\.htm/) {
      &gotolocation(\%pnpremote::query);
    }
    elsif ($pnpremote::query{'success-link'} eq "") {
      my $response_message = "Thank You for your order";
      &response_page($response_message);
    }
    else {
      &gotocgi(\%pnpremote::query);
    }
  }
  elsif ($pnpremote::query{'FinalStatus'} eq "badcard") {
    if($pnpremote::query{'badcard-link'} =~ /\.htm/) {
      &gotolocation(\%pnpremote::query);
    }
    elsif ($pnpremote::query{'badcard-link'} eq ""){
      my $response_message = "Sorry, your credit card has been declined.\n";
      &response_page($response_message);
    }
    else {
      &gotocgi(\%pnpremote::query);
    }
  }
  else {
    if($pnpremote::query{'problem-link'} =~ /\.htm/) {
      &gotolocation(\%pnpremote::query);
    }
    elsif ($pnpremote::query{'badcard-link'} eq ""){
      my $response_message = "Sorry, your payment request can not be processed at this time for the following reason:<p> $pnpremote::query{'MErrMsg'}";
      &response_page($response_message);
    }
    else {
      &gotocgi(\%pnpremote::query);
    }
  }
}


sub response_page {
  my($response_message) = @_;
  print "Content-type: text/html\n\n";
  print "<html>\n";
  print "<head>\n";
  print "<title>System Response Message</title>\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<div align=center>\n";
  print "<p>\n";
  print "<font size=+2>$response_message</font>\n";
  print "</body>\n";
  print "</html>\n";
  exit;
}


sub gotolocation {
  my ($query) = @_;
  print "Location: " . $$query{"$$query{'FinalStatus'}-link"} . "\n\n";
}


sub gotocgi {
  my ($query) = @_;
  my (%output) = ();
  if ($$query{'FinalStatus'} ne "success") {
    $$query{'orderID'} = "";
    $$query{'success'} = "no";
  }
  else{
    $$query{'success'} =  "yes";
    $$query{'MErrMsg'} = "";
  }
  $$query{'id'} = $$query{'orderID'};
  foreach my $key (keys %$query) {
    if(($key ne "card-number")
        && ($key ne "card-exp")
        && ($key ne "year-exp")
        && ($key ne "month-exp")
        && ($key ne "max")
        && ($key ne "pass")
        && ($key ne "$pnpremote::query{'FinalStatus'}-link")
        && ($key ne 'User-Agent')) {
      $output{$key} = $$query{$key};
    }
  }
  my @array = %output;

  $$query{"$$query{'FinalStatus'}-link"} =~  s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=]/x/g;
  $_ = $$query{"$$query{'FinalStatus'}-link"};

  my $page = &formpost($_,@array);

  print "Content-type: text/html\n\n";
  print $page;

}

sub modulus10{ # used to test check routing numbers
  my($ABAtest) = @_;
  my @digits = split('',$ABAtest);
  my ($modtest);
  my $sum = $digits[0] * 3 + $digits[1] * 7 + $digits[2] * 1 + $digits[3] * 3 + $digits[4] * 7 + $digits[5] * 1 + $digits[6] * 3 + $digits[7] * 7;
  my $check = 10 - ($sum % 10);
  $check = substr($check,-1);
  my $checkdig = substr($ABAtest,-1);
  if ($check eq $checkdig) {
    $modtest = "success";
  } else {
    $modtest = "failure";
  }
  return($modtest);
}

sub luhn10 {
  my ($cardnumber) = @_;
  my ($a,$b,$c,$temp,$sum,@digits,$len,$j,$k,$check);
  $sum = 0;
  $len = length($cardnumber);
  if ($len < 12 ) {
    return "failure";
  }
  @digits = split('',$cardnumber);
  for($k=0; $k<$len; $k++) {
    $j = $len - 1 - $k;
    if (($j - 1) >= 0) {
      $a = $digits[$j-1] * 2;
    }
    else {
      $a = 0;
    }
    if (length($a) > 1) {
      ($b,$c) = split('',$a);
      $temp = $b + $c;
    }
    else {
      $temp = $a;
    }
    $sum = $sum + $digits[$j] + $temp;
    $k++;
  }
  $check = substr($sum,length($sum)-1);
  if ($check eq "0") {
    return "success";
  }
  else {
    return "failure";
  }
}

sub formpost {
  my ($addr,@post_pairs) = @_;

  my %input = @post_pairs;
  my $pairs = "";
  my $result = "";

  foreach my $key (keys %input) {
    $_ = $input{$key};
    s/(\W)/'%' . unpack("H2",$1)/ge;
    if($pairs ne "") {
      $pairs = "$pairs\&$key=$_" ;
    }
    else{
      $pairs = "$key=$_" ;
    }
  }

  my $ua = new LWP::UserAgent;
  $ua->agent("MSIE 4.0b2");
  $ua->timeout(1200);
  my $req = new HTTP::Request POST => $addr;
  $req->content_type('application/x-www-form-urlencoded');
  $req->content($pairs);
  my $res = $ua->request($req);

  if ($res->is_success) {
    if ($res->content =~ /\(Operation already in progress\)/i) {
      return "";
    }
    else {
      $result = $res->content;
    }
  }
  else {
    if ($res->error_as_HTML =~ /\(Operation already in progress\)/i) {
      return "";
    }
    else {
      $result = $res->error_as_HTML;
    }
  }

  return $result;
}
