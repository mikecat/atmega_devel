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
my @out_data = ();
my %requested_labels = {};
my %available_labels = {};
for (my $i = 0; $i < @input_data - 1; $i += 2) {
	if ($input_data[$i] < 0 || $input_data[$i + 1] < 0) {next;}
	my $current_data = $input_data[$i] | ($input_data[$i + 1] << 8);
	my $current_bin = &num_to_bintext($current_data);
	my $matched = 0;
	if (($i >> 1) != $current_addr) {
		push(@out_data, sprintf("\t!ORG 0x%04X", ($i >> 1)));
	}
	$available_labels{sprintf("L%04X", $i >> 1)} = 1;
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
				my ($opecode, $operand) = split(/ /, $inst, 2);
				my @operand2 = &decode_operands($current_bin2, $data, $tmpl, $operand, ($i + 2 * @bin_data) >> 1);
				my $operand_out = "";
				my @operands = split(/ /, $operand);
				for (my $i = 0; $i < @operand2; $i++) {
					if ($i > 0) {$operand_out .= ", ";}
					if (substr($operands[$i], 0, 1) eq "R") {
						# レジスタ
						$operand_out .= "r$operand2[$i]";
					} elsif ($operands[$i] eq "K") {
						# データ定数
						$operand_out .= sprintf("0x%02X", $operand2[$i]);
					} elsif ($operands[$i] eq "k") {
						# プログラムアドレス定数
						my $label = sprintf("L%04X", $operand2[$i]);
						$requested_labels{$label} = 1;
						$operand_out .= $label;
					} elsif ($operands[$i] eq "m") {
						# メモリアドレス定数
						$operand_out .= sprintf("0x%04X", $operand2[$i]);
					} else {
						# その他
						$operand_out .= $operand2[$i];
					}
				}
				push(@out_data, sprintf("L%04X\t%s %s", $i >> 1, $opecode, $operand_out));
				$i += 2 * (@bin_data - 1);
				$matched = 1;
				last;
			}
		}
	}
	unless ($matched) {
		push(@out_data, sprintf("L%04X\t!WORD 0x%04X", $i >> 1));
	}
	$current_addr = ($i >> 1) + 1;
}

for (my $i = 0; $i < @out_data; $i++) {
	my ($label, $line) = split(/\t/, $out_data[$i], 2);
	if (exists($requested_labels{$label})) {
		print "$label:\n";
	}
	$line =~ s/(L([0-9A-F]{4}))/exists($available_labels{$1})?$1:"0x".$2/eg;
	print "\t$line\n";
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

sub decode_operands {
	my ($data, $template_data, $operand_template, $operands_str, $address) = @_;
	my @templates = split(/ /, $operand_template);
	my @operands = split(/ /, $operands_str);
	my $len = length($template_data);
	for (;;) {
		# データを順に見ていく
		for (my $i = 0; $i < $len; $i++) {
			# 各オペランドのテンプレートを処理
			for (my $j = 0; $j < @templates; $j++) {
				# そのオペランドに対応するデータか?
				if (substr($template_data, $i, 1) eq substr($operands[$j], -1, 1)) {
					# テンプレートを見ていく
					for (my $k = 0; $k < length($templates[$j]); $k++) {
						if (substr($templates[$j], $k, 1) eq "x") {
							# そのまま反映
							substr($templates[$j], $k, 1) = substr($data, $i, 1);
							last;
						} elsif (substr($templates[$j], $k, 1) eq "X") {
							# 反転して反映
							substr($templates[$j], $k, 1) = (substr($data, $i, 1) eq "0" ? "1" : "0");
							last;
						}
					}
					last;
				}
			}
		}
		# オペランドを補完する
		my $need_again = 0;
		for (my $i = 0; $i < @templates; $i++) {
			for (my $j = 0; $j < length($templates[$i]); $j++) {
				if (substr($templates[$i], $j, 1) eq "s") {
					# MSB(符号ビット)と同じ
					if (substr($templates[$i], 0, 1) eq "R") {
						substr($templates[$i], $j, 1) = substr($templates[$i], 1, 1);
					} else {
						substr($templates[$i], $j, 1) = substr($templates[$i], 0, 1);
					}
				} elsif (substr($templates[$i], $j, 1) eq "*") {
					# ドントケア
					substr($templates[$i], $j, 1) = "0";
				} elsif (substr($templates[$i], $j, 1) eq "x" || substr($templates[$i], $j, 1) eq "X") {
					# データを入れる位置が残っている(無いだろうけど)
					$need_again = 1;
				}
			}
		}
		unless ($need_again) {last;}
	}
	my @ret = ();
	for (my $i = 0; $i < @templates; $i++) {
		my $num_str = $templates[$i];
		my $num;
		my $offset = 0;
		if (substr($num_str, 0, 1) eq "R") {
			$num_str = substr($num_str, 1);
			$offset = $address;
			if (substr($num_str, 0, 1) eq "1") {
				$num_str =~ s/0/z/g;
				$num_str =~ s/1/0/g;
				$num_str =~ s/z/1/g;
				$num = -(oct("0b" . $num_str) + 1);
			} else {
				$num = oct("0b" . $num_str);
			}
		} else {
			$num = oct("0b" . $num_str);
		}
		push(@ret, $num + $offset);
	}
	return @ret;
}
