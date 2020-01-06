01 /*
02  * Nand flash interface of s3c2410/s3c2440, by www.arm9.net
03  * Changed from drivers/mtd/nand/s3c2410.c of kernel 2.6.13
04  */
05 
06 #include <common.h>
07 
08 #if (CONFIG_COMMANDS & CFG_CMD_NAND) && !defined(CFG_NAND_LEGACY)
09 #include <s3c2410.h>
10 #include <nand.h>
11 
12 DECLARE_GLOBAL_DATA_PTR;
13 
14 #define S3C2410_NFSTAT_READY    (1<<0)
15 #define S3C2410_NFCONF_nFCE     (1<<11)
16 
17 #define S3C2440_NFSTAT_READY    (1<<0)
18 #define S3C2440_NFCONT_nFCE     (1<<1)
19 
20 
21 /* select chip, for s3c2410 */
22 static void s3c2410_nand_select_chip(struct mtd_info *mtd, int chip)
23 {
24     S3C2410_NAND * const s3c2410nand = S3C2410_GetBase_NAND();
25 
26     if (chip == -1) {
27         s3c2410nand->NFCONF |= S3C2410_NFCONF_nFCE;
28     } else {
29         s3c2410nand->NFCONF &= ~S3C2410_NFCONF_nFCE;
30     }
31 }
32 
33 /* command and control functions, for s3c2410 
34  *
35  * Note, these all use tglx's method of changing the IO_ADDR_W field
36  * to make the code simpler, and use the nand layer's code to issue the
37  * command and address sequences via the proper IO ports.
38  *
39 */
40 static void s3c2410_nand_hwcontrol(struct mtd_info *mtd, int cmd)
41 {
42     S3C2410_NAND * const s3c2410nand = S3C2410_GetBase_NAND();
43     struct nand_chip *chip = mtd->priv;
44 
45     switch (cmd) {
46     case NAND_CTL_SETNCE:
47     case NAND_CTL_CLRNCE:
48         printf("%s: called for NCE\n", __FUNCTION__);
49         break;
50 
51     case NAND_CTL_SETCLE:
52         chip->IO_ADDR_W = (void *)&s3c2410nand->NFCMD;
53         break;
54 
55     case NAND_CTL_SETALE:
56         chip->IO_ADDR_W = (void *)&s3c2410nand->NFADDR;
57         break;
58 
59         /* NAND_CTL_CLRCLE: */
60         /* NAND_CTL_CLRALE: */
61     default:
62         chip->IO_ADDR_W = (void *)&s3c2410nand->NFDATA;
63         break;
64     }
65 }
66 
67 /* s3c2410_nand_devready()
68  *
69  * returns 0 if the nand is busy, 1 if it is ready
70  */
71 static int s3c2410_nand_devready(struct mtd_info *mtd)
72 {
73     S3C2410_NAND * const s3c2410nand = S3C2410_GetBase_NAND();
74 
75     return (s3c2410nand->NFSTAT & S3C2410_NFSTAT_READY);
76 }
77 
78 
79 /* select chip, for s3c2440 */
80 static void s3c2440_nand_select_chip(struct mtd_info *mtd, int chip)
81 {
82     S3C2440_NAND * const s3c2440nand = S3C2440_GetBase_NAND();
83 
84     if (chip == -1) {
85         s3c2440nand->NFCONT |= S3C2440_NFCONT_nFCE;
86     } else {
87         s3c2440nand->NFCONT &= ~S3C2440_NFCONT_nFCE;
88     }
89 }
90 
91 /* command and control functions */
92 static void s3c2440_nand_hwcontrol(struct mtd_info *mtd, int cmd)
93 {
94     S3C2440_NAND * const s3c2440nand = S3C2440_GetBase_NAND();
95     struct nand_chip *chip = mtd->priv;
96 
97     switch (cmd) {
98     case NAND_CTL_SETNCE:
99     case NAND_CTL_CLRNCE:
100         printf("%s: called for NCE\n", __FUNCTION__);
101         break;
102 
103     case NAND_CTL_SETCLE:
104         chip->IO_ADDR_W = (void *)&s3c2440nand->NFCMD;
105         break;
106 
107     case NAND_CTL_SETALE:
108         chip->IO_ADDR_W = (void *)&s3c2440nand->NFADDR;
109         break;
110 
111         /* NAND_CTL_CLRCLE: */
112         /* NAND_CTL_CLRALE: */
113     default:
114         chip->IO_ADDR_W = (void *)&s3c2440nand->NFDATA;
115         break;
116     }
117 }
118 
119 /* s3c2440_nand_devready()
120  *
121  * returns 0 if the nand is busy, 1 if it is ready
122  */
123 static int s3c2440_nand_devready(struct mtd_info *mtd)
124 {
125     S3C2440_NAND * const s3c2440nand = S3C2440_GetBase_NAND();
126 
127     return (s3c2440nand->NFSTAT & S3C2440_NFSTAT_READY);
128 }
129 
130 /*
131  * Nand flash hardware initialization:
132  * Set the timing, enable NAND flash controller
133  */
134 static void s3c24x0_nand_inithw(void)
135 {
136     S3C2410_NAND * const s3c2410nand = S3C2410_GetBase_NAND();
137     S3C2440_NAND * const s3c2440nand = S3C2440_GetBase_NAND();
138 
139 #define TACLS   0
140 #define TWRPH0  4
141 #define TWRPH1  2
142 
143     if (gd->bd->bi_arch_number == MACH_TYPE_SMDK2410)
144     {
145         /* Enable NAND flash controller, Initialize ECC, enable chip select, Set flash memory timing */
146         s3c2410nand->NFCONF = (1<<15)|(1<<12)|(1<<11)|(TACLS<<8)|(TWRPH0<<4)|(TWRPH1<<0);
147     }
148     else
149     {
150         /* Set flash memory timing */
151         s3c2440nand->NFCONF = (TACLS<<12)|(TWRPH0<<8)|(TWRPH1<<4);
152         /* Initialize ECC, enable chip select, NAND flash controller enable */
153         s3c2440nand->NFCONT = (1<<4)|(0<<1)|(1<<0);
154     }
155 }
156 
157 /*
158  * Called by drivers/nand/nand.c, initialize the interface of nand flash
159  */
160 void board_nand_init(struct nand_chip *chip)
161 {
162     S3C2410_NAND * const s3c2410nand = S3C2410_GetBase_NAND();
163     S3C2440_NAND * const s3c2440nand = S3C2440_GetBase_NAND();
164 
165     s3c24x0_nand_inithw();
166 
167     if (gd->bd->bi_arch_number == MACH_TYPE_SMDK2410) {
168         chip->IO_ADDR_R    = (void *)&s3c2410nand->NFDATA;
169         chip->IO_ADDR_W    = (void *)&s3c2410nand->NFDATA;
170         chip->hwcontrol    = s3c2410_nand_hwcontrol;
171         chip->dev_ready    = s3c2410_nand_devready;
172         chip->select_chip  = s3c2410_nand_select_chip;
173         chip->options      = 0;
174     } else {
175         chip->IO_ADDR_R    = (void *)&s3c2440nand->NFDATA;
176         chip->IO_ADDR_W    = (void *)&s3c2440nand->NFDATA;
177         chip->hwcontrol    = s3c2440_nand_hwcontrol;
178         chip->dev_ready    = s3c2440_nand_devready;
179         chip->select_chip  = s3c2440_nand_select_chip;
180         chip->options      = 0;
181     }
182 
183     chip->eccmode       = NAND_ECC_SOFT;
184 }
185 
186 #endif
