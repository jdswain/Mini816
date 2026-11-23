#!/bin/bash
# Build mini816.jed for the ATF1504AS-10JU44.
#
#   ATF15XX=~/Developer/Tools/atf15xx_yosys ./build.sh          # synthesis + fit
#   ./build.sh sim                                              # simulation only
#
# Needs: yosys and icarus-verilog (Homebrew), Wine, and the Atmel fitter files
# (fit1504.exe, aprim.lib, atmel.std) in $ATF15XX/vendor.  See README.md.
set -e
cd "$(dirname "$0")"
NAME=mini816

# ---- simulation
iverilog -g2012 -DSIM -o tb_$NAME tb_$NAME.v $NAME.v
vvp -n tb_$NAME | grep -E "PASS|FAIL|failed"
[ "$1" = "sim" ] && exit 0

: "${ATF15XX:?set ATF15XX to your atf15xx_yosys checkout}"

# ---- synthesis (same steps as atf15xx_yosys/run_yosys.sh)
yosys -q -l yosys.log -p "
read_liberty -lib $ATF15XX/cells.lib
read_verilog $NAME.v
tribuf
synth -flatten -noabc -auto-top
techmap -map $ATF15XX/techmap.v -D skip_DFFE_XX_
simplemap
dfflibmap -liberty $ATF15XX/cells.lib
abc -liberty $ATF15XX/cells.lib
iopadmap -bits -inpad INBUF Q:A -outpad BUF A:Q -toutpad TRI ENA:A:Q -tinoutpad bibuf EN:Q:A:PAD
clean
hierarchy
splitnets -format _
rename -wire -suffix _reg t:*DFF*
rename -wire -suffix _comb
delete t:\$scopeinfo
write_edif -lsbidx $NAME.edif
"
echo "synthesis: $NAME.edif"

# ---- fit (Atmel fit1504.exe under Wine)
grep '//PIN:' $NAME.v | cut -d' ' -f2- > $NAME.pin
export WINEPREFIX=${WINEPREFIX:-$HOME/.wine_atf}
WINE=${WINE:-wine}
VENDOR=$("$WINE" winepath -w "$ATF15XX/vendor")
rm -f $NAME.fit $NAME.jed
"$WINE" "$VENDOR\\fit1504.exe" \
    -i $NAME.edif -ifmt edif -o $NAME.jed \
    -lib "$VENDOR\\aprim.lib" \
    -tech ATF1504AS -device PLCC44 -tpd 10 \
    -preassign keep -tdi_pullup on -tms_pullup on

# ---- summary
grep "^   " $NAME.fit || true
grep "^Total" $NAME.fit || true
[ -f $NAME.jed ] && echo "fitted: $NAME.jed" || { echo "no $NAME.jed: see $NAME.fit"; exit 1; }
