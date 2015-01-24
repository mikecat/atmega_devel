AVRのプログラムを書くやつ(仮)
=============================

AVRのプログラムを書くためのツールです。

プログラムをAVRに書き込むには、
[AVRを読み書きするやつ](https://github.com/mikecat/avr_io)などが利用できます。

### 仕様

#### 使い方

* mnemonic2bin.pl  
  ```$ perl mnemonic2bin.pl [--bintext] < input_file > output_file```  
  * 標準入力からスクリプトを入力すると、標準出力にhexファイルを書き出す。
  * ```--bintext```オプションを指定すると、hexファイルではなく2進テキストを書き出す。
  * errorが出た場合の出力は未定義。

* bin2mnemonic.pl  
  ```$ perl bin2mnemonic.pl < input_file > output_file```  
  * 標準入力からhexファイルを入力すると、標準出力にスクリプトを書き出す。

#### 擬似命令
* ```!ORG address```  
  プログラムの出力位置をaddressに設定する。戻ることはできない。
* ```!CONST name value```  
  nameを値valueの定数として定義する。nameはラベルと同様に扱われる。
* ```!WORD value```  
  1ワードのデータを直接指定して配置する。

#### その他
* X,Y,Zレジスタを使う命令は、このプログラムではX,Y,Zを命令にくっつけて書く。  
  例：```ST Y+, r1``` → ```STY+ r1```
* 英字の大文字と小文字は区別しない。

### 参考資料
* [Atmel AVR 8-bit and 32-bit Microcontrollers](http://www.atmel.com/products/microcontrollers/avr/?tab=documents)  
  このページの"AVR Instruction Set"にAVRの命令(ニモニックと機械語)が載っています。

### 命令に関するメモ

* 基本的に第一オペランドを第二オペランドを用いて処理し、第一オペランドに結果を格納する。  
  例：```SUB r1, r2``` → ```r1 -= r2```
* ジャンプ関連
  * 条件分岐(brCC)の相対ジャンプは-64～63ワード
  * 相対ジャンプ(rjmp、rcall)は-2K～(2K-1)ワード
  * 絶対ジャンプ(jmp、call)命令は2ワード使用する
* メモリ関連
  * IN命令、OUT命令などで使用する「IOレジスタ」はRAMの0x20～0x5F番地
  * RAMの0x20番地 = 「IOレジスタ」の0番地
  * 0x20番地～0xFF番地のPICでいうSFR的な奴はLDS命令やSTS命令などでアクセス可能
  * レジスタはRAMの0x00番地～0x1F番地

x86命令     |似たAVR命令
------------|-----------
add r8,r8   |add
add r16,imm8|(adiw)
adc r8,r8   |adc
sub r8,r8   |sub
sub r8,imm8 |subi
sbb r8,r8   |sbc
sbb r8,imm8 |sbci
sub r16,imm8|(sbiw)
and r8,r8   |and
and r8,imm8 |andi
or r8,r8    |or
or r8,imm8  |ori
xor r8,r8   |eor
not r8      |com
neg r8      |neg
inc r8      |inc
dec r8      |dec
mul r8      |(mul)
imul r8     |(muls)
jmp rel16   |rjmp
jmp r16     |(ijmp)
call rel16  |rcall
call r16    |(icall)
ret         |ret
cmp r8,r8   |cp
cmp r8,imm8 |cpi
je/jz       |breq
jne/jnz     |brne
jb/jnae/jc  |brcs/brlo
jae/jnb/jnc |brcc/brsh
js          |brmi
jns         |brpl
jge/jnl     |brge
jl/jnge     |brlt
jo          |brvs
jno         |brvc
mov r8,r8   |mov
mov r16,r16 |(movw)
mov r8,imm8 |ldi
mov r8,m8   |lds/ld/ldd
mov m8,r8   |sts/st/std
push r8     |push
pop r8      |pop
xchg m8,r8  |(xch)
shl r8,1    |lsl
shr r8,1    |lsr
rcl r8,1    |rol
rcr r8,1    |ror
sar r8,1    |asr
stc         |sec
clc         |clc
nop         |nop

### ATmega328Pの機能に関するメモ

#### EEPROM

     |  7  |  6  |  5  |  4  |  3  |  2  |  1  |  0
-----|-----|-----|-----|-----|-----|-----|-----|-----
EEADH|  -  |  -  |  -  |  -  |  -  |  -  |EEAR9|EEAR8
EEADL|EEAR7|EEAR6|EEAR5|EEAR4|EEAR3|EEAR2|EEAR1|EEAR0
EEDR | MSB |     |     |     |     |     |     | LSB
EECR |  -  |  -  |EEPM1|EEPM0|EERIE|EEMPE|EEPE |EERE

* EEAR : アクセスするEEPROMのアドレス。初期値は未定義。
* EEDR : EEPROMから読んだ/EEPROMに書き込むデータ
* EEPM : 操作の選択(初期値は00)
  * 00 : 消して書き込む(3.4ms)
  * 01 : 消す(1.8ms)
  * 10 : 書き込む(1.8ms)
  * 11 : 予約
* EERIE : 1にするとEEPEが0(ready)の時に割り込みを起こす
* EEMPE : 1にしないとEEPEを1にしても何も起きない。1にした4サイクル後に0にされる。
* EEPE : 0のときに1にすることでEEPROMに書き込む。
* EERE : 1にするとEEPROMを読み込む(EEPEが0の時じゃないとダメ)。

書き込み方
1. EEPEとSPMEN(SPMCSR)が0になるまで待つ
2. EEARとEEDRにアドレスとデータを設定する
3. EEPEに0を書き込みながら、EEMPEに1を書き込む
4. 4サイクル以内にEEPEに1を書き込む

#### ピン変更割り込み
割り込みは出力モードでも起こるので、ソフトウェア割り込みとして使える。

      |   7   |   6   |   5   |    4  |   3   |   2   |   1   |   0
------|-------|-------|-------|-------|-------|-------|-------|-------
EICRA |   -   |   -   |   -   |   -   | ISC11 | ISC10 | ISC01 | ISC00
EIMSK |   -   |   -   |   -   |   -   |   -   |   -   | INT1  | INT0
EIFR  |   -   |   -   |   -   |   -   |   -   |   -   | INTF1 | INTF0
PCICR |   -   |   -   |   -   |   -   |   -   | PCIE2 | PCIE1 | PCIE0
PCIFR |   -   |   -   |   -   |   -   |   -   | PCIF2 | PCIF1 | PCIF0
PSMSK2|PCINT23|PCINT22|PCINT21|PCINT20|PCINT19|PCINT18|PCINT17|PCINT16
PSMSK1|   -   |PCINT14|PCINT13|PCINT12|PCINT11|PCINT10|PCINT9 |PCINT8
PSMSK0|PCINT7 |PCINT6 |PCINT5 |PCINT4 |PCINT3 |PCINT2 |PCINT1 |PCINT0

* ISC1 : INT1ピンによる割り込みの設定
  * 00 : INT1ピンがLOWのとき割り込み要求する
  * 01 : INT1ピンが切り替わった時割り込み要求する
  * 10 : INT1ピンの立ち下がりで割り込み要求する
  * 11 : INT1ピンの立ち上がりで割り込み要求する
* ISC0 : INT0ピンによる割り込みの設定
  * 00 : INT0ピンがLOWのとき割り込み要求する
  * 01 : INT0ピンが切り替わった時割り込み要求する
  * 10 : INT0ピンの立ち下がりで割り込み要求する
  * 11 : INT0ピンの立ち上がりで割り込み要求する
* INT1 : 1のときINT1ピンによる割り込み有効
* INT0 : 1のときINT0ピンによる割り込み有効
* INTF1 : INT1ピンによる割り込み要求(エッジ・切り替え)時に1になる
* INTF0 : INT0ピンによる割り込み要求(エッジ・切り替え)時に1になる
* PCIE2 : 1のとき有効にしたPCINT[23:16]ピンの切り替わりで割り込みする
* PCIE1 : 1のとき有効にしたPCINT[14:8]ピンの切り替わりで割り込みする
* PCIE0 : 1のとき有効にしたPCINT[7:0]ピンの切り替わりで割り込みする
* PCIF2 : PCINT[23:16]ピンの切り替わりによる割り込み要求時に1になる
* PCIF1 : PCINT[14:8]ピンの切り替わりによる割り込み要求時に1になる
* PCIF0 : PCINT[7:0]ピンの切り替わりによる割り込み要求時に1になる
* PCMSK2, PCMSK1, PCMSK0 : 1のとき対応するピンの切り替わり時に割り込み有効

#### ピンのI/O設定

DDxn|PORTxn|PUD(MCUCR)|方向|プルアップ|説明
----|------|----------|----|----------|-----------------------------
 0  |   0  |    X     |入力|   無し   |ハイインピーダンス
 0  |   1  |    0     |入力|   あり   |LOWに接続された場合電流が出る
 0  |   1  |    1     |入力|   無し   |ハイインピーダンス
 1  |   0  |    X     |出力|   無し   |LOW(電流を引き込む)
 1  |   1  |    X     |出力|   無し   |HIGH(電流を出す)
