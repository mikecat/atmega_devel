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

my $output_hex = 1;

for (my $i = 0; $i < @ARGV; $i++) {
	if ($ARGV[$i] eq "--bintext") {
		$output_hex = 0;
	}
}

my %label_list={};
my @input_data=();
my $addr=0;
my $lineno=0;
while(my $line=<STDIN>) {
	chomp($line);
	$lineno++;
	# コメントの削除
	$line =~ s/#.*\z//;
	$line =~ s/;.*\z//;
	$line =~ s/\/\/.*\z//;
	$line =~ s/'.*\z//;
	# タブを空白に変換
	$line =~ s/\t/ /g;
	# 先頭と末尾の空白の削除
	$line =~ s/\A +//;
	$line =~ s/ +\z//;
	if($line eq ""){next;}
	# 大文字化
	$line=uc($line);
	if(substr($line,length($line)-1,1) eq ":") {
		#ラベル
		my $label_name=substr($line,0,length($line)-1);
		if(defined($label_list{$label_name})) {
			warn "line $lineno: label $label_name already defined\n";
		} else {
			$label_list{$label_name}=$addr;
		}
	} elsif($line =~ /\A!CONST /) {
		# 定数定義
		my ($const,$name,$value_str)=split(/ +/,$line,3);
		if(defined($label_list{$name})) {
			warn "line $lineno: label $name already defined\n";
		} else {
			my ($value,$error)=&str2int($value_str);
			if($error ne "") {
				warn "line $lineno: $error\n";
			} else {
				$label_list{$name}=$value;
			}
		}
	} elsif($line =~ /\A!ORG/) {
		# 出力位置(word単位)の指定、後戻りはできない
		my ($org,$value_str)=split(/ +/,$line,2);
		my ($value,$error)=&str2int($value_str);
		if($error ne "") {
			warn "line $lineno: $error\n";
		} else {
			$addr=$value;
		}
	} else {
		# 命令
		my ($command_name,$oplands)=split(/ +/,$line,2);
		if(defined($convert_table{$command_name})) {
			my $bindata=(split(/\t/,$convert_table{$command_name}))[0];
			my @bindata_arr=split(/\|/,$bindata);
			push(@input_data,"$lineno\t$addr\t$line\t$oplands\t$convert_table{$command_name}");
			$addr+=0+@bindata_arr;
		} else {
			warn "line $lineno: command $command_name not found\n";
		}
	}
}

my @output_bin = ();
my $printed_lines = 0;

for(my $i=0;$i<@input_data;$i++) {
	my ($lineno,$addr,$line,$oplands,$bin,$bin_tmpl,$masks)=split(/\t/,$input_data[$i]);
	my @opland_list=split(/ *, */,$oplands);
	my @bin_list=split(/\|/,$bin);
	my @bin_tmpl_list=split(/ /,$bin_tmpl);
	my @mask_list=split(/ /,$masks);
	my $output=$bin;
	for(my $j=0;$j<@bin_tmpl_list;$j++) {
		# 数値データを得る
		my $num_invalid=0;
		my $num;
		if($opland_list[$j] =~ /\A-?(0X?)[0-9]+\z/) {
			# 数値
			my ($num_ret,$error)=&str2int($opland_list[$j]);
			if($error ne "") {
				warn "line $lineno: $error\n";
				$num_invalid=1;
			} else {
				$num=$num_ret;
			}
		} elsif($opland_list[$j] =~ /\AR[0-9]{1,8}\z/) {
			# レジスタ
			$num = int(substr($opland_list[$j],1));
		} else {
			# ラベル
			if(defined($label_list{$opland_list[$j]})) {
				$num=$label_list{$opland_list[$j]};
			} else {
				warn "line $lineno: label $opland_list[$j] is not defined\n";
				$num_invalid=1;
			}
		}
		if($num_invalid!=0) {
			for(my $k=0;$k<@bin_list;$k++){print "$nop\n";}
			next;
		}
		# マスクに当てはめたデータを得る
		my ($masked_data,$mask_error)=&num2mask($num,$mask_list[$j],$addr+@bin_list);
		if($mask_error ne "") {
			warn "line $lineno: $mask_error\n";
			for(my $k=0;$k<@bin_list;$k++){print "$nop\n";}
			next;
		}
		my $masked_data_len=length($masked_data);
		# バイナリにマスクを適用する
		my $target=$bin_tmpl_list[$j];
		my $data_pos=0;
		if(substr($target,0,1) eq "R") {
			if(substr($opland_list[$j],0,1) ne "R") {
				warn "line $lineno: warning: number or label found where register expected\n";
			}
			$target=substr($target,1);
		}
		for(my $k=0;$k<@bin_list;$k++) {
			my $cur_len=length($bin_list[$k]);
			for(my $l=0;$l<$cur_len;$l++) {
				if(substr($bin_list[$k],$l,1) eq $target) {
					substr($bin_list[$k],$l,1)=substr($masked_data,$data_pos,1);
					$data_pos++;
					if($data_pos>=$masked_data_len){$data_pos=0;}
				}
			}
		}
	}
	for(my $j=0;$j<@bin_list;$j++) {
		if ($output_hex) {
			if (@output_bin > int($addr)+$j) {
				warn "line $lineno: address to output is over current address\n";
			} else {
				while (@output_bin < int($addr)+$j) {push(@output_bin, -1);}
				push(@output_bin, &bintext_to_hex($bin_list[$j]));
			}
		} else {
			if ($printed_lines > int($addr)+$j) {
				warn "line $lineno: address to output is over current address\n";
			} else {
				while ($printed_lines < int($addr)+$j) {
					print "1111 1111 1111 1111\n";
					$printed_lines++;
				}
				print $bin_list[$j];
				if($j==0){print " $line";}
				print "\n";
				$printed_lines++;
			}
		}
	}
}

if ($output_hex) {
	for (my $i = 0; $i < @output_bin; $i += 8) {
		my $start = 0;
		my $data_exist = 0;
		for (my $j = 0; $j <= 8 && $i + $j <= @output_bin; $j++) {
			if ($j < 8 && $i + $j < @output_bin && $output_bin[$i + $j] >= 0) {
				$data_exist = 1;
			} else {
				if ($data_exist && $start < $j) {
					my $out = sprintf("%02X%04X00", ($j - $start) * 2, ($i + $start) * 2);
					for (my $k = $start; $k < $j; $k++) {
						$out .= sprintf("%02X%02X",
							$output_bin[$i + $k] & 0xff, ($output_bin[$i + $k] >> 8) & 0xff);
					}
					my $len = length($out);
					my $check = 0;
					for (my $k = 0; $k < $len; $k += 2) {
						$check += hex(substr($out, $k, 2));
					}
					printf ":%s%02X\n", $out, (256 - $check) & 0xff;
				}
				$start = $j + 1;
				$data_exist = 0;
			}
		}
	}
	print ":00000001FF\n";
}

sub str2int {
	my ($input)=@_;
	my $sign=1;
	my $num=0;
	my $i=0;
	my $radix=10;
	if(substr($input,0,1) eq "-") {
		$sign=-1;
		$i++;
	}
	if(substr($input,$i,1) eq "0") {
		$radix=8;
		$i++;
		if(substr($input,$i,1) eq "X") {
			$radix=16;
			$i++;
		} elsif(substr($input,$i,1) eq "B") {
			$radix=2;
			$i++;
		}
	}
	for(my $len=length($input);$i<$len;$i++) {
		my $cur=index("0123456789ABCDEF",substr($input,$i,1));
		if($cur<0 | $radix<=$cur) {
			return (0,"invalid number $input");
		} else {
			$num=$num*$radix+$cur;
			if($num>=0x01000000) {
				return (0,"number $input is too large");
			}
		}
	}
	return ($num*$sign,"");
}

sub num2bin {
	my ($value,$bits)=@_;
	my $ret="";
	my $minus=0;
	if($value<0) {
		$value=-$value-1;
		$minus=1;
	}
	my ($zero,$one)=$minus?("1","0"):("0","1");
	for(my $i=$bits-1;$i>=0;$i--) {
		$ret.=(($value&(1<<$i))!=0?$one:$zero);
	}
	return $ret;
}

sub num2mask {
	my ($num,$mask,$addr)=@_;
	if(substr($mask,0,1) eq "R") {
		$mask=substr($mask,1);
		$num-=$addr;
	}
	my $mask_len=length($mask);
	if($num<-(1<<($mask_len-1)) || (1<<$mask_len)<=$num) {
		return ("","number $num is too large for $mask_len bits");
	}
	my $bin=num2bin($num,$mask_len);
	my $ret="";
	for(my $i=0;$i<$mask_len;$i++) {
		my $cur_mask=substr($mask,$i,1);
		my $cur_num=substr($bin,$i,1);
		if(($cur_mask eq "0" && $cur_num eq "1") || ($cur_mask eq "1" && $cur_num eq "0")) {
			return ("","number $num mismatch (expected $mask, got $bin)");
		} elsif($i>0 && $cur_mask eq "s" && $cur_num ne substr($bin,0,1)) {
			return ("","number $num mismatch to sign bit (expected $mask, got $bin)");
		} elsif($cur_mask eq "x") {
			$ret.=$cur_num;
		} elsif($cur_mask eq "X") {
			$ret.=(($cur_num eq "0")?"1":"0");
		}
	}
	return ($ret,"");
}

sub bintext_to_hex {
	my ($in) = @_;
	$in =~ s/[^01]//g;
	return oct("0b" . $in);
}
