#!/data/data/com.termux/files/usr/bin/sh
# Termux:Boot script - sets up the S20 "swiss knife" USB gadget
# (ADB + HID keyboard + ACM serial console) automatically at boot.
# Termux:Boot itself runs after credential-encrypted Termux storage is
# available. Keep logs outside ~/.termux/boot: Termux:Boot treats every file
# in that directory as an executable boot script.

LOG_DIR=/data/data/com.termux/files/home/.termux/boot-logs
mkdir -p "$LOG_DIR"

su -c '
G=/config/usb_gadget/g1

if [ ! -d $G/functions/hid.usb0 ]; then
	mkdir -p $G/functions/hid.usb0
	echo 1 > $G/functions/hid.usb0/protocol
	echo 1 > $G/functions/hid.usb0/subclass
	echo 8 > $G/functions/hid.usb0/report_length
	printf "\005\001\011\006\241\001\005\007\031\340\051\347\025\000\045\001\165\001\225\010\201\002\225\001\165\010\201\003\225\005\165\001\005\010\031\001\051\005\221\002\225\001\165\003\221\003\225\006\165\010\025\000\045\145\005\007\031\000\051\145\201\000\300" > $G/functions/hid.usb0/report_desc
fi

echo "" > $G/UDC

[ -e $G/configs/b.1/hid.usb0 ] || ln -s $G/functions/hid.usb0 $G/configs/b.1/hid.usb0
[ -e $G/configs/b.1/acm.gs6 ] || ln -s $G/functions/acm.gs6 $G/configs/b.1/acm.gs6

echo 0x18d1 > $G/idVendor
echo 0x4ee7 > $G/idProduct

echo 10e00000.dwc3 > $G/UDC
' > "$LOG_DIR/swiss-gadget.log" 2>&1
