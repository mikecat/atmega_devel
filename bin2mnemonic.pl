#!/usr/bin/perl

use strict;

my $command_list_file="command_list.txt";

my @convert_table=();
my $nop = "0000 0000 0000 0000";

open(COMMAND,"< $command_list_file") or die("failed to open the command list\n");
while(my $line=<COMMAND>) {
	chomp($line);
	if($line eq "" || substr($line,0,1) eq "#"){next;}
	push(@convert_table,$line);
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

my $current_addr = 0;
for (my $i = 0; $i < @input_data - 1; $i += 2) {
	if ($input_data[$i] < 0 || $input_data[$i + 1] < 0) {next;}
	my $current_data = $input_data[$i] | ($input_data[$i + 1] << 8);
	my $current_bin = &num_to_bintext($current_data);
	my $matched = 0;
	if (($i >> 1) != $current_addr) {
		printf "!org 0x%04X\n", ($i >> 1);
	}
	for (my $j = 0; $j < @convert_table; $j++) {
		my ($data,$inst,$tmpl)=split(/\t/, $convert_table[$j]);
		my @bin_data=split(/\|/, $data);
		if (&bintext_match($bin_data[0], $current_bin)) {
			my $current_bin2 = $current_bin;
			my $ok = 1;
			for (my $k = 1; $k < @bin_data; $k++) {
				if ($i + 2 * $k >= @input_data - 1 ||
				$input_data[$i + 2 * $k] < 0 || $input_data[$i + 2 * $k + 1] < 0) {
					$ok = 0;
					last;
				}
				my $this_data = $input_data[$i + 2 * $k] | ($input_data[$i + 2 * $k + 1] << 8);
				my $this_bin = &num_to_bintext($this_data);
				if (&bintext_match($bin_data[$k], $this_data)) {
					$current_bin2.="|".$this_bin;
				} else {
					$ok = 0;
					last;
				}
			}
			if ($ok) {
				print $inst;
				print "\n";
				$i += 2 * (@bin_data - 1);
				$matched = 1;
				last;
			}
		}
	}
	unless ($matched) {
		printf "!word 0x%04X\n", $current_data;
	}
	$current_addr = ($i >> 1) + 1;
}

sub num_to_bintext {
	my ($in) = @_;
	my $out = "";
	for(my $i=0;$i<16;$i++) {
		if($i>0 && $i%4==0){$out.=" ";}
		$out.= (($in>>(15-$i))&1)?1:0;
	}
	return $out;
}

sub bintext_match {
	my ($in1, $in2) = @_;
	my ($len1, $len2) = (length($in1), length($in2));
	for (my $i = 0; $i < $len1 || $i < $len2; $i++) {
		my $char1 = ($i < $len1) ? substr($in1, $i, 1) : "";
		my $char2 = ($i < $len2) ? substr($in2, $i, 1) : "";
		if (($char1 eq "0" || $char1 eq "1") && ($char2 eq "0" || $char2 eq "1") &&
		$char1 ne $char2) {
			return 0;
		}
	}
	return 1;
}
