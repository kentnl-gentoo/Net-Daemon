# -*- perl -*-
#

require 5.004;
use strict;

use IO::Socket ();
use Config ();
use Net::Daemon::Test ();
use Fcntl ();
use Config ();


$| = 1;
$^W = 1;


if ($Config::Config{'d_fork'}  ne 'define'  ||
    $Config::Config{'d_fork'}  ne 'define') {  # -w
    print "1..0\n";
    exit 0;
}


my($handle, $port);
if (@ARGV) {
    $port = shift @ARGV;
} else {
    ($handle, $port) = Net::Daemon::Test->Child
	(10, $^X, '-Iblib/lib', '-Iblib/arch', 't/server',
	 '--mode=fork', 'logfile=stderr', 'debug');
}


sub IsNum {
    my $str = shift;
    (defined($str)  &&  $str =~ /(\d+)/) ? $1 : undef;
}


sub ReadWrite {
    my $fh = shift; my $i = shift; my $j = shift;
    if (!$fh->print("$j\n")  ||  !$fh->flush()) {
	die "Child $i: Error while writing $j: " . $fh->error() . " ($!)";
    }
    my $line = $fh->getline();
    die "Child $i: Error while reading: " . $fh->error() . " ($!)"
	unless defined($line);
    my $num;
    die "Child $i: Cannot parse result: $line"
	unless defined($num = IsNum($line));
    die "Child $i: Expected " . ($j*2) . ", got $num"
	unless $j*2 == $num;
}


sub MyChild {
    my $i = shift;

    eval {
	my $fh = IO::Socket::INET->new('PeerAddr' => '127.0.0.1',
				       'PeerPort' => $port);
	if (!$fh) {
	    die "Cannot connect: $!";
	}
	for (my $j = 0;  $j < 1000;  $j++) {
	    ReadWrite($fh, $i, $j);
	}
    };
    if ($@) {
	print STDERR "Client: Error $@\n";
	return 0;
    }
    return 1;
}


sub ShowResults {
    my @results;
    for (my $i = 1;  $i <= 10;  $i++) {
	$results[$i-1] = "not ok $i\n";
    }
    if (open(LOG, "<log")) {
	while (defined(my $line = <LOG>)) {
	    if ($line =~ /(\d+)/) {
		$results[$1-1] = $line;
	    }
	}
    }
    for (my $i = 1;  $i <= 10;  $i++) {
	print $results[$i-1];
    }
    exit 0;
}

my %childs;
sub CatchChild {
    my $pid = wait;
    if (exists $childs{$pid}) {
	delete $childs{$pid};
	ShowResults() if (keys(%childs) == 0);
    }
    $SIG{'CHLD'} = \&CatchChild;
}
$SIG{'CHLD'} = \&CatchChild;

# Spawn 10 childs, each of them running a series of test
unlink "log";
for (my $i = 0;  $i < 10;  $i++) {
    if (defined(my $pid = fork())) {
	if ($pid) {
	    # This is the parent
	    $childs{$pid} = $i;
	} else {
	    # This is the child
	    undef $handle;
	    %childs = ();
	    my $result = MyChild($i);
	    my $fh = Symbol::gensym();
	    if (!open($fh, ">>log")  ||  !flock($fh, 2)  ||
		!seek($fh, 0, 2)  ||
		!(print $fh (($result ? "ok " : "not ok "), ($i+1), "\n"))  ||
		!close($fh)) {
		print STDERR "Error while writing log file: $!\n";
		exit 1;
	    }
	    exit 0;
	}
    } else {
	print STDERR "Failed to create new child: $!\n";
	exit 1;
    }
}

my $secs = 120;
while ($secs > 0) {
    $secs -= sleep $secs;
}

END {
    if ($handle) {
	$handle->Terminate();
	undef $handle;
    }
    while (my($var, $val) = each %childs) {
	kill 1, $var;
    }
    %childs = ();
    unlink "ndtest.prt";
    exit 0;
}
