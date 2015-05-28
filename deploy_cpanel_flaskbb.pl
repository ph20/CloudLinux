#!/usr/bin/perl

use strict;
use JSON qw( decode_json );
use File::Temp qw( tempdir );
use File::Copy qw( copy );
use File::Basename;

my $email = 'agrynchuk@cloudlinux.com';
my $TAR = '/bin/tar';
my $SELECTORCTL = '/usr/bin/selectorctl';
my $CURL = '/usr/bin/curl';
my $LOG = "flaskbb-install.log";
my $SUDO = "/usr/bin/sudo";
my $FLASK_SOURCE_URL = "https://github.com/sh4nks/flaskbb/tarball/master";
my $script_name = basename($0);
my $LOCK = "deploy_cpanel_flaskbb.lock"; # lock in application directory
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
my $user_summary = decode_json( $user_summary_raw );
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
