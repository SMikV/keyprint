#!/usr/bin/perl


use 5.16.1;

##
# DEFAULTS
##
use constant {
   DFLT_WAIT_BEFORE_SEND =>  5,
   DFLT_MISPRINT_FRQ 	 =>  20, # than lesser, than more often. Like 1/N
   DFLT_GO2WC_FRQ	 =>  250,
   DFLT_CLI_TOOL 	 => 'xdotool',
   MIN_BREAK_DURATION	 =>  300,  # 5 minuites
   MAX_BREAK_DURATION	 =>  1200, # 20 minutes
};

##
# Key aliases
##
use constant {
   KEY_SPACE 	 => 'space',
   KEY_ENTER 	 => 'KP_Enter',
   KEY_BACKSPACE => 'BackSpace'
};


unless (@ARGV) {
   print_usage() and exit 0;
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

my $xdo = XDoTool->new;

while ( 1 ) {
  for my $file ( @ARGV ) {
    handle_file($file);
  }
}

exit 0;

sub handle_file
{
   my $path = shift;

   open my $fh, '<:utf8', $path or do {
      warn 'Failed to open file ' . $path . ': ' . $! . '. Skipping it!';
      return;
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
      
      int(rand DFLT_GO2WC_FRQ) or do_short_break;
      
      $xdo->key(KEY_SPACE) if $_ != $#words;
   }
   
   $xdo->key(KEY_ENTER)
}

sub print_word
{
   my $word = shift;

   for my $letter ( split '' => $word ) {
      int(rand DFLT_MISPRINT_FRQ) or do {
         $xdo->type(substr $mistaken_chrs, int(rand $l_mistaken_chrs), 1);
         $xdo->key(KEY_BACKSPACE);
      };
      $letter =~ /[a-zA-Z]/
         ? $xdo->key(  $letter =~ /[A-Z]/ ? ('Shift', lc $letter) : $letter )
         : $xdo->type( $letter );
   }
}

sub print_usage
{
   print <<EOF;
USAGE: $0 path_to_file
EXAMPLE: $0 ./my_text.txt
EOF

}

sub get_break_duration
{
  MIN_BREAK_DURATION + int(rand(MAX_BREAK_DURATION - MIN_BREAK_DURATION))
}

sub do_short_break
{
  my $break_dur = get_break_duration;
  printf "We did a good job, but we need to do a short break sometimes. Break for %d seconds\n", $break_dur;
  sleep $break_dur;
}

sub check_cli_tool { `which $_[0]` ? 1 : 0; }

package XDoTool;

use constant { 
   MIN_DELAY_BTW_INPUTS => 200_000,
   MAX_DELAY_BTW_INPUTS => 1_300_000,
};

BEGIN {
  no strict 'refs';
  for my $func (qw/key type/) {
    *{__PACKAGE__ . '::' . $_} = sub {
      my $tool = shift;
      my $what2out = $func eq 'key' ? join('+' => @_) : $_[1];
      
      $tool->__delay;
      system(sprintf q(%s 			 %s         --window  %s 	  %s),
                       $tool->{'cli_tool'}	$func, 	    $tool->{'window_id'}, __safe4shell($what2out)
      )
    }
  } # loop through "key" and "type" methods
}

use Time::HiRes qw(usleep);

sub new {
   state $dflt_props = {
      min_delay => MIN_DELAY_BTW_INPUTS,
      max_delay => MAX_DELAY_BTW_INPUTS,
      cli_tool  => 'xdotool',
   };

   my ($class, %params) = @_;
   my $class_name = ref($class) || $class;
   my $props = {};

   for ( qw/min_delay max_delay cli_tool/ ) {
      $props->{$_} = $params{$_} // $dflt_props->{$_} 
                     // die $class_name . ': mandatory constructor argument "' . $_ . '" is missing';
   }

   bless $props, $class_name;

   $props->{'window_id'} = $params{'window_id'} // $props->__get_active_window_id;
   $props
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
   usleep __rnd(@{$_[0]}{qw/min_delay max_delay/}) 
}

sub __safe4shell {
   $_[0] =~ /'/
      ? q<"> . ($_[0] =~ s%([\\`"])%\\$1%gr) . q<">
      : q<'> .  $_[0] . q<'>;
}

#sub __FUNC__ {
#    my $stack_lvl = caller(1) ? 1 : 0;
#    scalar((caller($stack_lvl))[3]) =~ s%^main::([^:]+)$%$1%r . '()'
#}

