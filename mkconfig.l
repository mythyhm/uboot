01 #!/bin/sh -e
02 
03 # Script to create header files and links to configure
04 # U-Boot for a specific board.
05 #
06 # Parameters:  Target  Architecture  CPU  Board [VENDOR] [SOC]
07 #
08 # (C) 2002-2006 DENX Software Engineering, Wolfgang Denk <wd@denx.de>
09 #
10 
11 APPEND=no	# Default: Create new config file
12 BOARD_NAME=""	# Name to print in make output
13 
14 while [ $# -gt 0 ] ; do
15 	case "$1" in
16 	--) shift ; break ;;
17 	-a) shift ; APPEND=yes ;;
18 	-n) shift ; BOARD_NAME="${1%%_config}" ; shift ;;
19 	*)  break ;;
20 	esac
21 done
22 
23 [ "${BOARD_NAME}" ] || BOARD_NAME="$1"
24 
25 [ $# -lt 4 ] && exit 1
26 [ $# -gt 6 ] && exit 1
27 
28 echo "Configuring for ${BOARD_NAME} board..."
29 
30 #
31 # Create link to architecture specific headers
32 #
33 if [ "$SRCTREE" != "$OBJTREE" ] ; then
34 	mkdir -p ${OBJTREE}/include
35 	mkdir -p ${OBJTREE}/include2
36 	cd ${OBJTREE}/include2
37 	rm -f asm
38 	ln -s ${SRCTREE}/include/asm-$2 asm
39 	LNPREFIX="../../include2/asm/"
40 	cd ../include
41 	rm -rf asm-$2
42 	rm -f asm
43 	mkdir asm-$2
44 	ln -s asm-$2 asm
45 else
46 	cd ./include
47 	rm -f asm
48 	ln -s asm-$2 asm
49 fi
50 
51 rm -f asm-$2/arch
52 
53 if [ -z "$6" -o "$6" = "NULL" ] ; then
54 	ln -s ${LNPREFIX}arch-$3 asm-$2/arch
55 else
56 	ln -s ${LNPREFIX}arch-$6 asm-$2/arch
57 fi
58 
59 if [ "$2" = "arm" ] ; then
60 	rm -f asm-$2/proc
61 	ln -s ${LNPREFIX}proc-armv asm-$2/proc
62 fi
63 
64 #
65 # Create include file for Make
66 #
67 echo "ARCH   = $2" >  config.mk
68 echo "CPU    = $3" >> config.mk
69 echo "BOARD  = $4" >> config.mk
70 
71 [ "$5" ] && [ "$5" != "NULL" ] && echo "VENDOR = $5" >> config.mk
72 
73 [ "$6" ] && [ "$6" != "NULL" ] && echo "SOC    = $6" >> config.mk
74 
75 #
76 # Create board specific header file
77 #
78 if [ "$APPEND" = "yes" ]	# Append to existing config file
79 then
80 	echo >> config.h
81 else
82 	> config.h		# Create new config file
83 fi
84 echo "/* Automatically generated - do not edit */" >>config.h
85 echo "#include <configs/$1.h>" >>config.h
86 
87 exit 0
