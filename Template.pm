package HCKit::Template;

use strict;
use warnings;

require Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
@ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use HCKit::Template ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
%EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

@EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

@EXPORT = qw(
	
);

$VERSION = '0.01';


# Preloaded methods go here.

sub new {
    my $ref = {};
    $ref->{env} = make_default_env();
    $ref->{tmpl} = "";
    return bless $ref;
}

sub process_file {
    my ($self, @file) = @_;
    foreach my $f (@file){
	my ($tmpl, $rule, $data) = read_src($f);
	$self->{tmpl} .= $tmpl;
	parse_rule($rule, $self->{env});
	parse_data($data, $self->{env});
    }
}

sub read_data_file {
    my ($self, @file) = @_;
    foreach my $f (@file){
	my $c = file_content($f);
	parse_data($c, $self->{env});
    }
}

sub para {
    my $self = shift;
    if( @_ == 1 ){
	my ($key) = @_;
	return $self->{env}->{$key};
    }
    elsif( @_ == 2 ){
	my ($key, $val) = @_;
	$self->{env}->{$key} = $val;
    }
}

sub output {
    my ($self) = @_;
    return rewrite($self->{tmpl}, $self->{env});
}

# utilities ###########################################################

sub read_src {
    my ($file) = @_;
    local *FILE;
    my @x;  # ($tmpl, $rule, $data);
    my $mode = 0;
    open(FILE, $file) || die "can't open $file: $!";
    while(<FILE>){
	if( index($_, '---RULE---') >= 0 ){
	    $mode = 1;
	}
	elsif( index($_, '---DATA---') >= 0 ){
	    $mode = 2;
	}
	else{
	    $x[$mode] .= $_;
	}
    }
    close(FILE);
    return @x;
}

sub parse_rule {
    my ($rule, $env) = @_;
    while( $rule =~ 
	   /
	   <([\w-]+)(\s[^>]+)?>(.*?)<\/\1> |
	   (<!--.*-->)
	   /gsx ){
	my ($sym, $opt, $val, $com) = ($1,$2,$3,$4);
	if( $com ){ next }
	my $append = 0;
	my $trim = 0;
	$opt = "" if !defined($opt);
	foreach(split " ", $opt){
	    if( $_ eq 'append' || $_ eq '+' ){
		$append = 1;
	    }
	    elsif( $_ eq 'trim' ){
		$trim = 1;
	    }
	}
	if( $trim ){ $val = trim($val) }
	if( $append ){
	    $env->{$sym} .= $val;
	}
	else{
	    $env->{$sym} = $val;
	}
    }
}

sub parse_data {
    my ($data, $env) = @_;
    $data = "" if !defined($data);
    my $penv = parse_data_body($data);
    ref($penv) eq 'HASH' || return;
    while( my($key, $val) = each %$penv ){
	$env->{$key} = $val;
    }
    #debug_env($env, 0);
}

sub parse_data_body {
    my ($body) = @_;
    my %hash;
    my $text;
    my $last = 0;
    while( $body =~ /(<([\w-]+)>(.*?)<\/\2>|(<!--.*-->))/gs ){
	my ($match, $sym, $val, $comm) = ($1,$2,$3,$4);
	my $len = length($match);
	my $pre = substr($body, $last, pos($body)-$len-$last);
	$text .= $pre;
	$last = pos($body);
	if( $comm ){ next }
	my $sub = parse_data_body($val);
	if( defined($hash{$sym}) ){
	    if( ref($hash{$sym}) eq 'ARRAY' ){
		push @{$hash{$sym}}, $sub;
	    }
	    else{
		$hash{$sym} = [$hash{$sym}, $sub];
	    }
	}
	else{
	    $hash{$sym} = $sub;
	}
    }
    if( $last < length($body) ){
	$text .= substr($body, $last);
    }
    return %hash ? \%hash : $text;
}

sub rewrite {
    my ($tmpl, $env) = @_;
    $tmpl = "" if !defined($tmpl);
    my $last = 0;
    my $output = "";
    while( $tmpl =~ 
	   /(
	     <\*\s*([\w:.-]+)\s*([^>]+)?\*> |
	     <\&\s*([\w:.-]+)\s*([^>]+)?\&>(.*?)<\&\s*\4\s*\&> |
	     <\{\s*([\w:.-]+)\s*([^>]+)?\}>(.*?)<\{\s*\/\7\s*\}> |
	      (<!--.*-->)
	     )/gxs ){
	my ($match, $var, $varaux, $fun, $funaux, $funarg, 
	    $loop, $loopaux, $loopbody, $comm) = 
		($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);
	my $len = length($match);
	my $pre = substr($tmpl, $last, pos($tmpl)-$len-$last);
	$output .= $pre;
	$last = pos($tmpl);
	if( defined($comm) ){ next }
	my $aux = $varaux || $funaux || $loopaux || "";
	my ($precmd, $postcmd) = parse_aux($aux);
	my $newenv = { '__NEXT__' => $env };
	if( $fun ){
	    my $hash = parse_data_body($funarg);
	    if( ref($hash) eq "HASH" ){
		foreach my $key (keys %$hash ){
		    $newenv->{$key} = $hash->{$key};
		}
	    }
	}
	elsif( $loop ){
	    $newenv->{'__BODY__'} = $loopbody;
	}
	my $stack = [];
	process_tokens($stack, $newenv, @$precmd);
	my $key = $var || $fun || $loop;
	eval_expr($key, $stack, $newenv);
	{
	    my $n = 0;
	    my $sep = $newenv->{sep};
	    my $o = "";
	    foreach my $i (@$stack){
		if( ref($i) eq 'ARRAY' ){
		    foreach my $j (@$i){
			if( $sep && $n++ > 0 ){
			    $o .= $sep;
			} 
			$o .= $j;
		    }
		}
		else{
		    if( $sep && $n++ > 0 ){
			$o .= $sep;
		    }
		    $o .= $i;
		}
	    }
	    $stack = [$o];
	}
	process_tokens($stack, $newenv, @$postcmd);
	if( $stack->[0] ){
	    $output .= $stack->[0];
	}
    }
    if( $last < length($tmpl) ){
	$output .= substr($tmpl, $last);
    }
    return $output;
}

sub parse_aux {
    my ($aux) = @_;
    $aux = "" if !defined($aux);
    my $pre = [];
    my $post = [];
    my $ref = $pre;
    while( $aux =~ 
	   /(
	     [\w:-]+=\"[^\"]*\" |
	     [\w:-]+=\'[^\']*\' |
	     [\w:-]+=[^\'\"\;][^;\S]* |
	     \"[^\"]*\" |
	     \'[^\"]*\' |
	     [^\s=;]+ |
	     ;
	     )/gsx ){
	if( $1 eq ';' ){ $ref = $post; next }
	push @$ref, $1;
    }
    return ($pre, $post);
}

sub var_lookup {
    my ($var, $env) = @_;
    my @i = split /\./, $var;
    my $first = shift @i;
    my $bind = lookup($first, $env);
    foreach(@i){
	$bind = $bind->{$_};
    }
    return $bind;
}

sub process_tokens {
    my ($stack, $env, @tok) = @_;
    my $i;
    for($i=0;$i<=$#tok;$i++){
	my $t = $tok[$i];
	if( $t =~ /^([\w:-]+)=\"([^\"]*)\"$/ ){
	    $env->{$1} = $2;
	}
	elsif( $t =~ /^([\w:-]+)+=\'([^\']*)\'$/ ){
	    $env->{$1} = $2;
	}
	elsif( $t =~ /^([\w:-]+)=([^\'\"\;][^;\S]*)$/ ){
	    $env->{$1} = $2;
	}
	elsif( $t =~ /^\"(.*)\"$/ ){
	    push @$stack, $1;
	}
	elsif( $t =~ /^\'(.*)\'$/ ){
	    push @$stack, $1;
	}
	elsif( $t eq "as" ){
	    push @$stack, $tok[++$i];
	}
	else{
	    eval_expr($t, $stack, $env);
	}
    }
}

sub lookup {
    my ($sym, $env) = @_;
    while( $env ){
	if( defined($env->{$sym}) ){ 
	    return $env->{$sym};
	}
	$env = $env->{'__NEXT__'};
    }
    return undef;
}

sub eval_expr {
    my ($expr, $stack, $env) = @_;
    my @tok = split /\./, $expr;
    my $first = shift @tok;
    my $val = lookup($first, $env);
    foreach my $i (@tok){
	$val = $val->{$i};
    }
    if( ref($val) eq 'CODE' ){
	&{$val}($stack, $env);
    }
    elsif( ref($val) eq 'ARRAY' ||
	   ref($val) eq 'HASH' ){
	push @$stack, $val;
    }
    else{
	push @$stack, rewrite($val, $env);
    }
}

# default env #########################################################

# op_foreach
#   stack: LIST [IDENT]
#   switches:
#     foreach:sep=SEP
#     foreach:toggle=INIT

sub op_foreach {
    my ($stack, $env) = @_;
    my $body = $env->{__BODY__};
    my ($ident, $list);
    my $top = pop @$stack;

    if( ref($top) eq "ARRAY" ){
	$ident = "iter";
	$list  = $top;
    }
    else{
	$ident = $top;
	$list  = pop @$stack;
    }
    my $output = "";
    my $join = $env->{'foreach:sep'};
    my $n = 0;
    my $toggle = 0;
    if( defined($env->{'foreach:toggle'}) ){
	$toggle = 1;
	$env->{toggle} = $env->{'foreach:toggle'};
    }

    if( ref($list) eq "ARRAY" ){
	foreach my $e (@$list){
	    if( $join && $n++ > 0 ){
		$output .= $join;
	    }
	    $env->{$ident} = $e;
	    if( $toggle ){
		$env->{toggle} = $env->{toggle} ? 0 : 1;
	    }
	    $output .= rewrite($body, $env);
	}
    }
    push @$stack, $output;
}

sub op_read_data_file {
    my ($stack, $env) = @_;
    my $prevenv = $env->{__NEXT__} || $env;
    my $file = pop @$stack;
    my $c = file_content($file);
    parse_data($c, $prevenv);
}

sub op_trim {
    my ($stack, $env) = @_;
    my $s = pop @$stack;
    push @$stack, trim($s);
}

sub make_default_env {
    my $env = {};
    $env->{'foreach'} = \&op_foreach,
    $env->{'read-data-file'} = \&op_read_data_file;
    $env->{'nop'} = sub { };
    $env->{'trim'} = \&op_trim;
    return $env;
}

sub file_content {
    my ($file) = @_;
    local *FILE;
    local $/;
    $/ = undef;
    open(FILE, $file) || die "can't open $file: $!";
    my $c = <FILE>;
    close(FILE);
    return $c;
}

sub trim {
    my ($str) = @_;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}

sub debug_env {
    my ($env, $prefix) = @_;
    if( ref($env) eq "ARRAY" ){
	foreach(@$env){
	    debug_env($_, $prefix);
	}
    }
    elsif( ref($env) eq "HASH" ){
	while( my($key, $val) = each %$env ){
	    print " " x $prefix, "<$key>\n";
	    debug_env($val, $prefix+2);
	    print "\n";
	    print " " x $prefix, "</$key>\n";
	}
    }
    else{
	print " " x $prefix, $env;
    }
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

HCKit::Template - A template system for HTML construction

=head1 SYNOPSIS

First you make a template like this, test.tmpl:

 <html>
 <head><title><* title *></title></head>
 <body>
   <h1><* title *></h1>
   <ul>
     <{ foreach friend as f }>
       <li><* f.name *>, <* f.age *>
     <{ /foreach }>
   </ul>
 </body>
 </html>
 ---RULE---
 <title>My Friends</title>
 ---DATA---
 <friend>
   <name>Arthur Beck</name>
   <age>23</age>
 </friend>
 <friend>
   <name>Charles Douglas</name>
   <age>26</age>
 </friend>
 <friend>
   <name>Earl Fairchild</name>
   <age>18</age>
 </friend>
  
Then you can convert the template to an HTML page with the following
script.

 use HCKit::Template;
 my $tmpl = HCKit::Template->new;
 $tmpl->process_file("test.tmpl");
 print $tmpl->output;

The output becomes like this:
   
 <html>
 <head><title>My Friends</title>
 <body>
   <h1>My Friends</h1>
   <ul>
     <li>Arthur Beck, 23
     <li>Charles Douglas, 26
     <li>Earl Fairchild, 18
   </ul>
 </body>
 </html>

=head1 DESCRIPTION

This module constructs an HTML page from a template. The conversion
proceeds with the help of rewrite rules and data sources. Rewrite
rules can be specified in the template file itself, or in the Perl
script. Data sources can be XML files, or dynamically constructed in
the Perl script.

=head1 TEMPLATE FILE

A template file consists of three portions: a template itself, rewrite
rules, and data sources. A template file starts by specifying a
template itself. A line beginning with the string '---RULE---' starts
rewrite rules. A line beginning with the string '---DATA---' starts
data sources. Sections for rewrite rules and data sources are
optional.

An example template file:

 I am <* first-name *> <* last-name *>.
 ---RULE---
 <first-name>Andy</first-name>
 <last-naem>Davis</last-name>

This template lacks data source, and is converted to:

 I am Andy Davis.

=head1 TEMPLATE

Within templates, three kinds of constructs are identified and
rewritten by this module: simple constructs, funcall constructs, and
block constructs.

A simple construct.

 <* IDENTIFIER *>

When this construct is encountered, the module searches for
IDENTIFIER in the rewrite rules and data sources.

For example, with the following template file:

 <* name *>
 ---RULE---
 <name>Harold</name>
    
'name' is looked up in the rewrite rules, and the construct is
replaced with its definition, Harold.

With the following template file:

 <* name *>
 ---DATA---
 <name>Eugene</name>

'name' is looked up in the data source, and the construct is replace
with its definition, Eugene.

By concatenating identifiers with C<.>, nested data in the data
source can be accessed, as follows:

 <* name.first-name *>
 ---DATA---
 <name>
   <first-name>Andy</first-name>
   <last-name>Varmus</last-name>
 </name>

A funcall construct.
  
 <& IDENTIFIER &>
   <key1>val1</key1>
   <key2>val2</key2>
 <& /IDENTIFIED &>

This construct extends the current environment with the key-value
pairs and applies a rewrite rule specified by IDENTIFIER.

For example:

 <& full-name &>
   <first>Andy</first>
   <last>Varmus</last>
 <& /full-name &>
 ---RULE---
 <full-name><* first *> <* last *></full-name>

This template file outputs: Andy Varmus

A block construct.

 <{ IDENTIFIER }>
   ...
 <{ /IDENTIFIER }>

This construct invokes a built in block function identified by
IDENTIFIER. Currently, only one function 'foreach' is included.

For example:

 <{ foreach num as n }>
   <* n *>
 <{ /foreach }>
 ---DATA---
 <num>1</num>
 <num>2</num>
 <num>3</num>

The above template file is converted to:
   1
   2
   3

=head1 REWRITE RULE

Each rewrite rule is in the following format:

 <IDENTIFIER>
   BODY
 </IDENTIFIER>

'IDENTIFIER' indicates a name with which this rewrite rule is
invoked. BODY indicates the output of this rewrite rule. In BODY,
all kinds of constructs can appear as in templates.

For example,
  
 ---RULE---
 <greeting>
   Hello, <* guest *>!
 </greeting>

This rewrite rule uses a simple construct (<* guest *>).

=head1 PRE/POST PROCESSOR

Each construct can have multiple pre/post processors. They are
specified following IDENTIFIER in the start tag.

For example in the simple construct, the general syntax is 

 <* IDENTIFIER PRE ; POST *>

in which PRE is a space-separated list of pre-processors and POST
is a space-separated list of post-procesors. 

These processors are applied before and after the invocation of
rewrite, respectively.

Currently supported pre-processors are as follows.

=over 4

=item B<name=value>  

Extends the current environment with name/value pair. If value
includes a space, it should be quoted by ' or ".

Example:

  <* full-name first=Andy last=Varmus *>
  ---RULE---
  <full-name><* first *> <* last *></full-name>

The output becomes: Andy Varmus

=back

Currently supported post-processors are as follows.

=over 4

=item B<trim>

Removes leading and trailing spaces from the result of rewrite.

Example:

  My name is <* name *>.
  ---RULE---
  <name>
    Andy
  </name>

This becomes:

  My name is 
    Andy
  .

However,

  My name is <* name ; trim *>.
  ---RULE---
  <name>
    Andy
  </name>

This becomes:

  My name is Andy.

=back

=head1 REWRITE RULE OPTIONS

Definition of a rewrite rule can have options after its IDENTIFIER.
Options are separated by spaces with each other.

For example,

  ---RULE---
  <full-name trim>
    <* first *> <* last *>
  </full-name>

'trim' option removes leading and trailing white spaces from rewrite
rule BODY. Therefore, the above rule is equivalent to

  ---RULE---
  <full-name><* first *> <* last *></full-name>

Currently available options are as follows.

=over 4

=item B<trim>

Removes leading and trailing white spaces from rewrite rule BODY.

=item B<+>

Appends rewrite rule BODY to the previously defined rule with the same
name. Normally, multiple rewrite rules with the same name are defined,
the last definition overwrites the others. 

For exmaple:

  <style type="text/css">
  <* stylesheet *>
  </style>
  ---RULE---
  <stylesheet>
    body { background-color: #fff }
  </stylesheet>
  <stylesheet>
    frame { border:thin solid #f00 }
  </stylesheet>

This results in:
      
  <style type="text/css">
    frame { border:thin solid #f00 }
  </style>

However with C<+> option,

  <style type="text/css">
  <* stylesheet *>
  </style>
  ---RULE---
  <stylesheet>
    body { background-color: #fff }
  </stylesheet>
  <stylesheet +>
    frame { border:thin solid #f00 }
  </stylesheet>

The result is:

  <style type="text/css">
    body { background-color: #fff }
    frame { border:thin solid #f00 }
  </style>
  
=back

=head1 BUILTIN FUNCTIONS

Currently, there are only two builtin functions: C<foreach> and
C<read-data-file>.

=over 4

=item B<foreach>

  <{ foreach LIST [AS NAME] }>
    BODY
  <{ /foreach }>

For each item in LIST, it is bound to NAME and then BODY is rewritten.
If NAME is omitted, each item is bound to the name 'iter'.

For example:

  <{ foreach num }>
    <* iter *>
  <{ /foreach }>
  ---DATA---
  <num>1</num>
  <num>2</num>
  <num>3</num>

This results in:

    1
    2
    3

Another example:

  <{ foreach site as s }>
    <a href="<* s.url *>"><* s.label *></a><br>
  <{ /foreach }>
  ---DATA---
  <site>
    <href>http://www.yahoo.com</href>
    <label>Yahoo!</label>
  </site>
  <site>
    <href>http://www.google.com</href>
    <label>Google</label>
  </site>

This results in:

  <a href="http://www.yahoo.com">Yahoo!</a>
  <a href="http://www.google.com">Google</a>

C<foreach> can have options.

C<foreach:sep=SEP> option specifies separator between outputs of
iterations.

For example,

  <{ foreach num foreach:sep=' | '}>
    <* iter *>
  <{ /foreach }>
  ---DATA---
  <num>1</num>
  <num>2</num>
  <num>3</num>

This results in:

    1 | 
    2 |
    3

C<foreach:toggle=INIT> option introduces a new variable named 'toggle'
that has initial value of INIT. After each iteration, variable
'toggle' is toggled between 0 and 1.

For example,

  <{ foreach num as n foreach:toggle=0 }>
    <div class="style-<* toggle *>"><* n *></div>
  <{ /foreach }>
  ---DATA---
  <num>1</num>
  <num>2</num>
  <num>3</num>

Results in:

    <div class="style-0">1</div>
    <div class="style-1">1</div>
    <div class="style-0">1</div>
  

=item B<read-data-file>

  <* read-data-file FILE *>

Reads XML data from FILE.

Example:

  <* read-data-file './friends.xml' *>
  <{ foreach friend as f }>
    <* f.name *>, <* f.age *><br>
  <{ /foreach }>

File ./friends.xml contains:

  <friend>
    <name>Arthur</name>
    <age>23</age>
  </friend>
  <friend>
    <name>Charles</name>
    <age>26</age>
  </friend>
  <friend>
    <name>Earl</name>
    <age>18</age>
  </friend>

The output is:
  
  Arthur, 23<br>
  Charles, 26<br>
  Earl, 18<br>

=back

=head1 SEE ALSO

There are other excellent and mature Perl modules with similar
purposes, but with different concepts. For example, Sam Tregar's
HTML::Template,
L<http://theoryx5.uwinnipeg.ca/mod_perl/cpan-search?modinfo=8997> and
Andy Wardley's Template
L<http://theoryx5.uwinnipeg.ca/mod_perl/cpan-search?modinfo=18155> are
famous ones.

=head1 AUTHOR

Hangil Chang, E<lt>hangil@chang.jpE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Hangil Chang

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
