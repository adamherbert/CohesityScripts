#!/usr/bin/perl

our $VERSION = '1.0.6';

use strict;
use REST::Client;
use Getopt::Std;
use JSON;

#Set Environment Variable to no verify certs
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;

#Variables
my %options = ();

my $client = REST::Client->new();
my $accessToken;
my $tokenType;
my $authCookie;

# Main
getopts("hdc:u:p:j:", \%options);

if (exists $options{h}) {
  HELP_MESSAGE();
  exit;
}

if ($options{j} eq "") {
  HELP_MESSAGE();
  exit;
}

# Check for client switch and IP/Host
if (exists $options{c} && $options{c} ne "") {
  print "Cluster: $options{c}\n" if exists $options{d};
  $authCookie = $ENV{"HOME"} . "/.cohesity.$options{c}.auth";
}
else {
  print "Error: Cluster not specified, please provide cluster information\n";
  HELP_MESSAGE();
  exit(2);
}

#Check for user and prompt for password if necessary
if (exists $options{u} && $options{u} ne "") {
  if (exists $options{p}) {
    print "User: $options{u}\nPassword: $options{p}\n"
      if exists $options{d};
    unlink $authCookie;
  }
  else {
    if (-e $authCookie) {
      print "Authentication cookie exists you can delete the cookie $authCookie to prompt for password\n"
        if exists $options{d};
    }
    else {
      print "Please enter password: ";
      ReadMode('noecho');
      chomp($options{p} = <STDIN>);
      print "\n";
      ReadMode(0);
      print "\nUser: $options{u}\nPassword: $options{p}\n"
        if exists $options{d};
    }
  }
}
else {
  print "Error: User not specified\n";
  HELP_MESSAGE();
  exit(3);
}

authorize();
my $response = getJobById($options{j});
if (!exists $response->{id}) {
  $response = getJobByName($options{j});
}
if (!exists $response->{id}) {
  print "Couldn't find job id " . $options{j} . "\n";
  exit(4);
}
eval {
  resumeJob($response->{id});
  sleep 15;
};
pauseJob($response->{id});

#runJob($response->{id});
exit;

## Subs
sub HELP_MESSAGE {
  print <<EOF;
usage: $0 -c clusterVIP/Hostname -u user [-hd] [-p password] -j Job_Name_or_ID
    -h - Help Menu
    -d - Debug Mode
    -c cluster - Cohesity cluster VIP/IP/Hostname
    -u user - Cohesity user
    -p password - Cohesity user password
    -j Job_Name_or_ID
EOF
  exit(1);
}


sub authorize {

  # Set Host
  $client->setHost("https://$options{c}");
  $client->addHeader("Accept", "application/json", "Content-Type", "application/json");

  # Check for authorization token cookie
  print "$authCookie\n" if exists $options{d};
  my $authLine;
  if (-e $authCookie) {

    # Check if the authentication cookie exists and is valid
    open(FH, "<", "$authCookie");    #Open file for read access
    foreach (my $line = <FH>) {
      print "Line: $line\n" if exists $options{d};
      ($tokenType, $accessToken) = split(/,/, $line);
      print "Type: $tokenType\nToken: $accessToken\n"
        if exists $options{d};
    }
    close(FH);

    # Check for invalid or expired token
    my $testAccess = REST::Client->new();
    $testAccess->setHost("https://$options{c}");
    $testAccess->addHeader("Accept",        "application/json");
    $testAccess->addHeader("Authorization", "$tokenType $accessToken");
    $testAccess->GET('/irisservices/api/v1/public/alerts?alertSeverityList[]=kCritical&alertCategoryList[]=kBackupRestore&alertStateList[]=kOpen');

    print "Code: " . $testAccess->responseCode() . "\n"
      if exists $options{d};

    print "Content: " . $testAccess->responseContent() . "\n"
      if exists $options{d};

    # Check for successful status 200-299
    if ($testAccess->responseCode() >= 300) {

      #if access token is expired or invalid remove cookie and request new token
      unlink $authCookie;
      requestToken();
    }
  }
  else {

    #Request token since cookie doesn't exist
    requestToken();
  }

  # Valid Cookie so set tokentype and accesstoken variables
  open(FH, "<", "$authCookie");    #Open file for read
  foreach (my $line = <FH>) {
    print "Line: $line\n" if exists $options{d};
    ($tokenType, $accessToken) = split(/,/, $line);
    print "Type: $tokenType\nToken: $accessToken\n" if exists $options{d};
  }

  # Close the open file
  close(FH);
  print "AccessToken: $accessToken\n" if exists $options{d};
  print "TokenType: $tokenType\n"     if exists $options{d};
}


sub getJobById {
  my $jobId = shift;
  return unless $jobId;
  my $responseJSON;

  #Get alert information
  $client = REST::Client->new();
  $client->setHost("https://$options{c}");    #Set host

  $client->addHeader("Accept",        "application/json");
  $client->addHeader("Authorization", "$tokenType $accessToken");

  #Authorize request
  $client->GET('/irisservices/api/v1/public/protectionJobs/' . $jobId);
  print 'Response: ' . $client->responseContent() . "\n"
    if exists $options{d};
  print 'Response status: ' . $client->responseCode() . "\n"
    if exists $options{d};

  # Test if response is null meaning no results found
  my $responseContent = $client->responseContent();
  chomp $responseContent;

  if ($responseContent ne "null") {
    $responseJSON = decode_json $responseContent;
    return $responseJSON;
  }
}


sub getJobByName {
  my $jobName = shift;
  return unless $jobName;
  my $responseJSON;
  my $jobId;

  #Get alert information
  $client = REST::Client->new();
  $client->setHost("https://$options{c}");    #Set host
  $client->addHeader("Accept",        "application/json");
  $client->addHeader("Authorization", "$tokenType $accessToken");    #Authorize request
  $client->GET('/irisservices/api/v1/public/protectionJobs?names=' . $jobName);
  print 'Response: ' . $client->responseContent() . "\n"
    if exists $options{d};
  print 'Response status: ' . $client->responseCode() . "\n"
    if exists $options{d};
  my $responseContent = $client->responseContent();                  # Test if response is null meaning no results found
  chomp $responseContent;

  if ($responseContent ne "null") {
    $responseJSON = decode_json $responseContent;
    if (@{$responseJSON} ne 1) {
      return;
    }
    return $responseJSON->[0];
  }
}


sub resumeJob {
  my $jobId = shift;
  return unless $jobId;
  my $responseJSON;

  #Create REST Client
  $client = REST::Client->new();
  $client->setHost("https://$options{c}");    #Set host
  $client->addHeader("Accept", "application/json");

  #Authorize request
  $client->addHeader("Authorization", "$tokenType $accessToken");
  $client->POST('/irisservices/api/v1/public/protectionJobState/' . $jobId, '{ "pause": false }');

  print 'Response: ' . $client->responseContent() . "\n"
    if exists $options{d};
  print 'Response status: ' . $client->responseCode() . "\n"
    if exists $options{d};

  if ($client->responseCode() eq "204") {
    print "Job id $jobId successfully resumed\n";
    return;
  }

  # Test if response is null meaning no results found
  my $responseContent = $client->responseContent();
  chomp $responseContent;
  if ($responseContent ne "null") {
    print $responseContent. "\n";
  }
  exit;
}


sub pauseJob {
  my $jobId = shift;
  return unless $jobId;
  my $responseJSON;

  #Create REST Client
  $client = REST::Client->new();
  $client->setHost("https://$options{c}");    #Set host
  $client->addHeader("Accept", "application/json");

  #Authorize request
  $client->addHeader("Authorization", "$tokenType $accessToken");
  $client->POST('/irisservices/api/v1/public/protectionJobState/' . $jobId, '{ "pause": true }');

  print 'Response: ' . $client->responseContent() . "\n"
    if exists $options{d};
  print 'Response status: ' . $client->responseCode() . "\n"
    if exists $options{d};

  if ($client->responseCode() eq "204") {
    print "Job id $jobId successfully paused\n";
    return;
  }

  # Test if response is null meaning no results found
  my $responseContent = $client->responseContent();
  chomp $responseContent;
  if ($responseContent ne "null") {
    print $responseContent. "\n";
  }
  exit;
}


sub runJob {
  my $jobId = shift;
  return unless $jobId;
  my $responseJSON;

  #Get alert information
  $client = REST::Client->new();
  $client->setHost("https://$options{c}");    #Set host
  $client->addHeader("Accept", "application/json");

  #Authorize request
  $client->addHeader("Authorization", "$tokenType $accessToken");
  $client->POST('/irisservices/api/v1/public/protectionJobs/run/' . $jobId, "{}");
  print 'Response: ' . $client->responseContent() . "\n"
    if exists $options{d};
  print 'Response status: ' . $client->responseCode() . "\n"
    if exists $options{d};

  if ($client->responseCode() eq "204") {
    print "Job id $jobId successfully admitted\n";
    return;
  }

  # Test if response is null meaning no results found
  my $responseContent = $client->responseContent();
  chomp $responseContent;
  if ($responseContent ne "null") {
    print $responseContent. "\n";
  }
  exit;
}


sub requestToken {

  my ($domain, $user) = ("LOCAL", $options{u});
  if ($options{u} =~ /\\/) {
    ($domain, $user) = split(/\\/, $options{u});
  }
  my $requestJSON = encode_json(
    {
      "domain"   => $domain,
      "username" => $user,
      "password" => $options{p}
    }
  );

  #Request new authorization Token
  $client->POST('/irisservices/api/v1/public/accessTokens', $requestJSON);
  die $client->responseContent() if ($client->responseCode() >= 300);

  open(FH, ">$authCookie");
  my $test = decode_json($client->responseContent());
  print FH"$test->{'tokenType'},$test->{'accessToken'}";
  close(FH);

  print 'Response: ' . $client->responseContent() . "\n"
    if exists $options{d};
  print 'Response status: ' . $client->responseCode() . "\n"
    if exists $options{d};

  foreach ($client->responseHeaders()) {
    print 'Header: ' . $_ . '=' . $client->responseHeader($_) . "\n"
      if exists $options{d};
  }
}
