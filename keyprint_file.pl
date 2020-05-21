#!/usr/bin/perl
package main;

use 5.16.1;
use Getopt::Std;
use POSIX qw(strftime); 
use HTTP::Date;

use subs qw/maybe_mistaken_char do_short_break/;

##
# DEFAULTS
##
use constant {
   DFLT_WAIT_BEFORE_SEND =>  5,
   DFLT_MISPRINT_FRQ 	 =>  20, # than lesser, than more often. Like 1/N
   DFLT_GO2WC_FRQ	 =>  250,
   DFLT_CLI_TOOL 	 => 'xdotool',
   MIN_BREAK_DURATION	 =>  4 * 60,  # 4 minuites
   MAX_BREAK_DURATION	 =>  12 * 60, # 12 minutes
   XC_DONE		 =>  0,
};

##
# Key aliases
##
use constant {
   KEY_SPACE 	 => 'space',
   KEY_ENTER 	 => 'KP_Enter',
   KEY_BACKSPACE => 'BackSpace'
};

getopts 'LNf:', \my %opt;
unless (@ARGV) {
   print_usage() and exit 0;
}

my $flNoDelay = $opt{'N'} and do {
   no strict 'refs';
   *{__PACKAGE__ . '::' . $_} = sub { 1 }
      for qw/do_short_break maybe_mistaken_char/
};

my $loop_decr = $opt{'L'} ? 1 : 0;

my $flExitByAlarm;
if ( my $finish_at = $opt{'f'} ) {  
  my $ts_now = time;
  $finish_at =~ /(?:^|\s)\d+:\d+$/ and $finish_at .= ':00';
  if ( $finish_at =~ /:/ and $finish_at !~ /-/ ) {
    my $HMS = strftime('%H%M%S', localtime($ts_now));
    my $Ymd = strftime( '%Y-%m-%d', localtime($ts_now + (($finish_at =~ s%:%%gr) <= $HMS ? 86400 : 0)) );
    $finish_at = join(' ' => $Ymd, $finish_at);
  }
  my $ts_finish_at = str2time($finish_at)
    or die 'failed to parse finish time';
  (my $dlt_secs = ($ts_finish_at - $ts_now)) > 0
    or die 'time to finish is in the past';
    
  alarm($dlt_secs);
  $SIG{ALRM} = sub { $flExitByAlarm = 1; exit; };
  printf "WARN: Execution will be interrupted at %s, after %d seconds of execution\n", $finish_at, $dlt_secs;
}

unless (check_cli_tool(DFLT_CLI_TOOL)) {
   die 'ERROR: ' . DFLT_CLI_TOOL . " not found!\n"
      ."Please install " . DFLT_CLI_TOOL . " and be sure that PATH env. variable is set correctly\n";
}

my $mistaken_chrs    = join('' => map chr($_), 32 .. 127);
my $l_mistaken_chrs  = length $mistaken_chrs;

printf <<EOSTR, DFLT_WAIT_BEFORE_SEND;
Now go to window where we need to send keystrokes.
Be patient, we will remember current window id after %d seconds!
EOSTR

for my $i (1 .. DFLT_WAIT_BEFORE_SEND) {
  sleep 1;
  say '=> ', $i, ($i == DFLT_WAIT_BEFORE_SEND ? '!' : ''), ($i >= (DFLT_WAIT_BEFORE_SEND - 1) ? '!' : ''), ' <=';
}

my $xdo = XDoTool->new(
  $flNoDelay ? ('no_delay' => 1) : ()
);

my $count = 1;
while ( $count ) {
  for my $file ( @ARGV ) {
    handle_file($file);
  }
  $count -= $loop_decr
}

exit XC_DONE;

sub handle_file
{
   my $path = shift;
   my $fh = 
     $path eq '-'
     ? *STDIN
     : do {
         open my $fh, '<:utf8', $path
           or (warn("Failed to open file ${path}: $!. Skipping it!"), return);
         $fh
       };

   while (my $line = readline $fh) {
     print_line($line);
   }

   $xdo->key(KEY_ENTER);
   close $fh;
}

sub print_line
{
   my $line = shift;
   chomp $line;

   my @words = split /\s/, $line;

   for ( 0..$#words ) {
      print_word($words[$_]);
      
      int(rand DFLT_GO2WC_FRQ) or do_short_break();
      
      $xdo->key(KEY_SPACE) if $_ != $#words;
   }
   
   $xdo->key(KEY_ENTER)
}

sub print_word
{
   my $word = shift;

   for my $letter ( split '' => $word ) {
      maybe_mistaken_char;
      $letter =~ /[a-zA-Z]/
         ? $xdo->key(  $letter =~ /[A-Z]/ ? ('Shift', lc $letter) : $letter )
         : $xdo->type( $letter );
   }
}

sub print_usage
{
   print <<EOF;
USAGE: $0 [-f FINAL_TIME] path_to_file
EXAMPLE: $0 -f 19:00 ./my_text.txt
EOF

}

sub get_break_duration
{
   MIN_BREAK_DURATION + int(rand(MAX_BREAK_DURATION - MIN_BREAK_DURATION))
}

sub maybe_mistaken_char
{
   int(rand DFLT_MISPRINT_FRQ) or do {
      $xdo->type(substr $mistaken_chrs, int(rand $l_mistaken_chrs), 1);
      $xdo->key(KEY_BACKSPACE);
   }
}

sub do_short_break
{
   my $break_dur = get_break_duration;
   printf "We did a good job, but we need to do a short break sometimes. Break for %d seconds\n", $break_dur;
   sleep $break_dur;
}

sub check_cli_tool { `which $_[0]` ? 1 : 0; }

END {
  say 'Interrupted by alarm' if $flExitByAlarm;
}

package XDoTool;
use Time::HiRes qw(usleep);

use constant { 
   MIN_DELAY_BTW_INPUTS => 200_000,
   MAX_DELAY_BTW_INPUTS => 1_300_000,
};

BEGIN {
  no strict 'refs';
  for my $func (qw/key type/) {
    *{__PACKAGE__ . '::' . $func} = sub {
      my $tool = shift;
      my $what2out = $func eq 'key' ? join('+' => @_) : $_[0];
      
      $tool->__delay;
      system(sprintf q(%s 			 %s         --window  %s 	    %s ),
                       $tool->cli_tool,		$func, 	    $tool->window_id,   __safe4shell($what2out)
      )
    }
  } # loop through "key" and "type" methods
}

sub new {
   state $has_properties = {
      'min_delay' 	=> {default => MIN_DELAY_BTW_INPUTS},
      'max_delay' 	=> {default => MAX_DELAY_BTW_INPUTS},
      'cli_tool'  	=> {default => 'xdotool'},
      'no_delay'	=> {default => 0},
      'window_id'	=> {}
   };

   my ($class, %params) = @_;
   my $class_name = ref($class) || $class;
   my $xdo = +{ map {
     my ($property, $vd) = each %{$has_properties};
     $property => 
       $params{$property} //
         $vd->{'default'} // (
           $vd->{'mand'}
             ? die sprintf(q<%s's mandatory constructor argument "%s" is missing>, $class_name, $property)
             : undef         )
   } 1..keys %{$has_properties} };

   bless $xdo, $class_name;
   $xdo->window_id unless $params{'window_id'};
   $xdo
}

sub window_id {
  my $tool = $_[0];
  $tool->{'window_id'} = $_[1] if $#_ > 0;
  $tool->{'window_id'} //= $tool->__get_active_window_id
}

sub __get_active_window_id {
   my $tool = $_[0];
   chomp(my $window_id = `$tool->{cli_tool} getwindowfocus -f`);
   $window_id   
}

sub __rnd {
   my $min_value = $_[0] || 100;
   my $max_value = $_[1] // ($min_value + 10_000);
   ($min_value, $max_value) = ($max_value > $min_value) ? ($min_value, $max_value) : ($max_value, $min_value);
   
   int(rand($max_value - $min_value)) + $min_value;
}

sub __delay {
   usleep __rnd(@{$_[0]}{qw/min_delay max_delay/}) unless $_[0]{'no_delay'};
}

sub __safe4shell {
   $_[0] =~ /'/
      ? q<"> . ($_[0] =~ s%([\\`"])%\\$1%gr) . q<">
      : q<'> .  $_[0] . q<'>;
}

our $AUTOLOAD;
sub AUTOLOAD {
  return unless my ($property) = $AUTOLOAD =~ m/::(.+?)$/;
  no strict 'refs';
  *{$AUTOLOAD} = sub {
    $#_ > 0 ? $_[0]{$property} = $_[1] : $_[0]{$property}
  };
  goto &{$AUTOLOAD}
}

#sub __FUNC__ {
#    my $stack_lvl = caller(1) ? 1 : 0;
#    scalar((caller($stack_lvl))[3]) =~ s%^main::([^:]+)$%$1%r . '()'
#}

