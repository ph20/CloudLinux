#!/usr/bin/perl

use strict;
use warnings;

use File::Temp qw( tempdir );
use File::Copy qw( copy );
use File::Basename;

my $email = 'agrynchuk@cloudlinux.com';
my $TAR = '/bin/tar';
my $SELECTORCTL = '/usr/bin/selectorctl';
my $CURL = '/usr/bin/curl';
my $SUDO = "/usr/bin/sudo";
my $FLASK_SOURCE_URL = "https://github.com/sh4nks/flaskbb/tarball/master";
my $script_name = basename($0);
my $app_name = $ARGV[0];

if ( $> == 0 ) {
    print "Don't run as root";
    exit;
}

# quit unless we have the correct number of command-line args
if ( $#ARGV != 0 ) {
    print "\nUsage: $script_name application_name\n";
    exit;
}

if ( !-x $SELECTORCTL) {
    print "Can not detect 'selectorctl' on path '$SELECTORCTL'\n";
    exit;
}

if ( !-x $TAR) {
    print "Can not detect 'tar' on path '$TAR'\n";
    exit;
}

if ( !-x $CURL) {
    print "Can not detect 'curl' on path '$CURL'\n";
    exit;
}

print "Start deploying FlaskBB...\n";
my $user_summary_raw = `$SELECTORCTL --interpreter python --user-summary --json`;
my $user_summary = decode_json( trim( $user_summary_raw ) );
if ( $user_summary->{'status'} eq "ERROR") {
    print "ERROR [selectorctl]: $user_summary->{'message'}\n";
    exit;
}
my $python = $user_summary->{'data'}{$app_name}{'interpreter'}{'binary'};
if ( !-x $python) {
    print "Can not detect python interpreter for virtual evironment on path '$python'\n";
    exit;
}
my $prefix = $user_summary->{'data'}{$app_name}{'interpreter'}{'prefix'};
my $pip = "$prefix/bin/pip";
my $app_root = "$ENV{'HOME'}/$app_name";
my $domain = $user_summary->{'data'}{$app_name}{'domain'};
my $uri = $user_summary->{'data'}{$app_name}{'alias'};

if ( !-e "$app_root/passenger_wsgi.py" ) {
    print "Can't detect $app_root/passenger_wsgi.py\n";
    exit;
}


if ( -e "$app_root/flaskbb") {
    print "Directory $app_root/flaskbb already present; Aborting\n";
    exit;
}

my $temp_dir = tempdir( CLEANUP => 1 );

print "Downloading flaskBB package...";
my $result  = `$CURL -LkSs $FLASK_SOURCE_URL -o $temp_dir/flskbb.tar.gz`;
if (-e "$temp_dir/flskbb.tar.gz" ) {
    print "Ok\n";
} else {
    print "Error\n";
    exit;
}



print "Unpack flaskBB package...";
`$TAR -xzf $temp_dir/flskbb.tar.gz --directory=$temp_dir`;
my @d = glob "$temp_dir/sh4nks-flaskbb-*";
my $flaskbb_tmp = $d[0];
print "Ok\n";


print "Install requirements...";
system($pip, "install", "--quiet", "--requirement", "$flaskbb_tmp/requirements.txt");
print "Ok\n";

print "Copy flaskBB package...";
system("/bin/cp -Rp $flaskbb_tmp/* $app_root");
print "Ok\n";





print "Configure...";
copy "$app_root/flaskbb/configs/development.py.example", "$app_root/flaskbb/configs/development.py";
copy "$app_root/flaskbb/configs/production.py.example", "$app_root/flaskbb/configs/production.py";
system($SELECTORCTL, '--interpreter', 'python', '--setup-wsgi', 'wsgi.py:flaskbb', $app_name);
print "Ok\n";

print "Initial database...";
chdir "$app_root"; # change work directory
my $initdb_log = `$python $app_root/manage.py initdb 2>/dev/null`;
my $create_admin_log = `$python $app_root/manage.py create_admin --username admin --password cloudlinux --email $email 2>/dev/null`; # add admin
my $populate_log = `$python $app_root/manage.py populate 2>/dev/null`;  # add some testing data to forum
print "Ok\n";

print "Restart service...";
system($SELECTORCTL, '--interpreter', 'python', '--restart-webapp', $app_name);
print "Ok\n";


print "flaskBB forum is up; you can enter to it http://$domain/$uri\n login: admin; password cloudlinux\n";


sub  trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };

############################################
# JSON parser; copy-past from

use Carp qw/carp croak/;
use Encode ();

my ( $TRUE, $FALSE ) = ( 1, 0 );
# Escaped special character map with u2028 and u2029
my %ESCAPE = (
  '"'     => '"',
  '\\'    => '\\',
  '/'     => '/',
  'b'     => "\x08",
  'f'     => "\x0c",
  'n'     => "\x0a",
  'r'     => "\x0d",
  't'     => "\x09",
  'u2028' => "\x{2028}",
  'u2029' => "\x{2029}"
);

sub decode_json {
  my $err = _decode(\my $value, shift);
  return defined $err ? croak $err : $value;
}

sub _decode {
  my $valueref = shift;

  eval {

    # Missing input
    die "Missing or empty input\n" unless length( local $_ = shift );

    # UTF-8
    $_ = eval { Encode::decode('UTF-8', $_, 1) } unless shift;
    die "Input is not UTF-8 encoded\n" unless defined $_;

    # Value
    $$valueref = _decode_value();
  
    # Leftover data
    return m/\G[\x20\x09\x0a\x0d]*\z/gc || _throw('Unexpected data');
  } ? return undef : chomp $@;

  return $@;
}

sub _decode_array {
  my @array;
  until (m/\G[\x20\x09\x0a\x0d]*\]/gc) {

    # Value
    push @array, _decode_value();

    # Separator
    redo if m/\G[\x20\x09\x0a\x0d]*,/gc;

    # End
    last if m/\G[\x20\x09\x0a\x0d]*\]/gc;

    # Invalid character
    _throw('Expected comma or right square bracket while parsing array');
  }

  return \@array;
}

sub _decode_object {
  my %hash;
  until (m/\G[\x20\x09\x0a\x0d]*\}/gc) {

    # Quote
    m/\G[\x20\x09\x0a\x0d]*"/gc
      or _throw('Expected string while parsing object');

    # Key
    my $key = _decode_string();

    # Colon
    m/\G[\x20\x09\x0a\x0d]*:/gc
      or _throw('Expected colon while parsing object');

    # Value
    $hash{$key} = _decode_value();

    # Separator
    redo if m/\G[\x20\x09\x0a\x0d]*,/gc;

    # End
    last if m/\G[\x20\x09\x0a\x0d]*\}/gc;

    # Invalid character
    _throw('Expected comma or right curly bracket while parsing object');
  }

  return \%hash;
}

sub _decode_string {
  my $pos = pos;
  
  # Extract string with escaped characters
  m!\G((?:(?:[^\x00-\x1f\\"]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4})){0,32766})*)!gc; # segfault on 5.8.x in t/20-mojo-json.t
  my $str = $1;

  # Invalid character
  unless (m/\G"/gc) {
    _throw('Unexpected character or invalid escape while parsing string')
      if m/\G[\x00-\x1f\\]/;
    _throw('Unterminated string');
  }

  # Unescape popular characters
  if (index($str, '\\u') < 0) {
    $str =~ s!\\(["\\/bfnrt])!$ESCAPE{$1}!gs;
    return $str;
  }

  # Unescape everything else
  my $buffer = '';
  while ($str =~ m/\G([^\\]*)\\(?:([^u])|u(.{4}))/gc) {
    $buffer .= $1;

    # Popular character
    if ($2) { $buffer .= $ESCAPE{$2} }

    # Escaped
    else {
      my $ord = hex $3;

      # Surrogate pair
      if (($ord & 0xf800) == 0xd800) {

        # High surrogate
        ($ord & 0xfc00) == 0xd800
          or pos($_) = $pos + pos($str), _throw('Missing high-surrogate');

        # Low surrogate
        $str =~ m/\G\\u([Dd][C-Fc-f]..)/gc
          or pos($_) = $pos + pos($str), _throw('Missing low-surrogate');

        $ord = 0x10000 + ($ord - 0xd800) * 0x400 + (hex($1) - 0xdc00);
      }

      # Character
      $buffer .= pack 'U', $ord;
    }
  }

  # The rest
  return $buffer . substr $str, pos $str, length $str;
}

sub _decode_value {

  # Leading whitespace
  m/\G[\x20\x09\x0a\x0d]*/gc;

  # String
  return _decode_string() if m/\G"/gc;

  # Object
  return _decode_object() if m/\G\{/gc;

  # Array
  return _decode_array() if m/\G\[/gc;

  # Number
  return 0 + $1
    if m/\G([-]?(?:0|[1-9][0-9]*)(?:\.[0-9]*)?(?:[eE][+-]?[0-9]+)?)/gc;

  # True
  return $TRUE if m/\Gtrue/gc;

  # False
  return $FALSE if m/\Gfalse/gc;

  # Null
  return undef if m/\Gnull/gc;  ## no critic (return)

  # Invalid character
  _throw('Expected string, array, object, number, boolean or null');
}