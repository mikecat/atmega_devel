#!/usr/bin/perl

use strict;

my $command_list_file="command_list.txt";

my %convert_table={};
my $nop = "0000 0000 0000 0000";

open(COMMAND,"< $command_list_file") or die("failed to open the command list\n");
while(my $line=<COMMAND>) {
	chomp($line);
	if($line eq "" || substr($line,0,1) eq "#"){next;}
	# 命令名を取得する
	my $name="";
	$line =~ s/\t([A-Z]+)([ \t])/$name=$1,$2 eq "\t"?"\t\t":"\t"/e;
	if($name ne "") {
		$convert_table{$name}=$line;
	}
}
close(COMMAND);

my @input_data=();
my $offset = 0;
my $line_count = 0;
while(my $line = <STDIN>) {
	$line_count++;
	chomp($line);
	if (substr($line,0,1) ne ":") {
		warn "line $line_count: warning: line not starts from :\n";
		next;
	}
	my @data = ();
	my $len = length($line);
	for (my $i = 1; $i < $len; $i += 2) {
		push(@data,hex(substr($line,$i,2)));
	}
	my $check = 0;
	for (my $i = 0; $i < @data; $i++) {
		$check = ($check + $data[$i]) & 0xff;
	}
	if ($check != 0x00 || @data < 5) {
		warn "line $line_count: warning: line too short or checksum mismatch\n";
		next;
	}
	if($data[3] == 0x02) {
		if(@data == 7) {$offset = (($data[4] << 8) | $data[5]) << 4;}
	} elsif ($data[3] == 0x04) {
		if(@data == 7) {$offset = (($data[4] << 8) | $data[5]) << 16;}
	} elsif ($data[3] == 0x00) {
		my $addr = ($data[1] << 8) | $data[2];
		for (my $i = 0; $i < $data[0]; $i++) {
			my $cur_addr = $offset + $addr + $i;
			while (@input_data <= $cur_addr){push(@input_data,-1);}
			$input_data[$cur_addr] = $data[4 + $i];
		}
	}
}
