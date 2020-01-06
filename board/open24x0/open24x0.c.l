01 /*
02  * (C) Copyright 2002
03  * Sysgo Real-Time Solutions, GmbH <www.elinos.com>
04  * Marius Groeger <mgroeger@sysgo.de>
05  *
06  * (C) Copyright 2002
07  * David Mueller, ELSOFT AG, <d.mueller@elsoft.ch>
08  *
09  * See file CREDITS for list of people who contributed to this
10  * project.
11  *
12  * This program is free software; you can redistribute it and/or
13  * modify it under the terms of the GNU General Public License as
14  * published by the Free Software Foundation; either version 2 of
15  * the License, or (at your option) any later version.
16  *
17  * This program is distributed in the hope that it will be useful,
18  * but WITHOUT ANY WARRANTY; without even the implied warranty of
19  * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
20  * GNU General Public License for more details.
21  *
22  * You should have received a copy of the GNU General Public License
23  * along with this program; if not, write to the Free Software
24  * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
25  * MA 02111-1307 USA
26  */
27 
28 #include <common.h>
29 #include <s3c2410.h>
30 
31 DECLARE_GLOBAL_DATA_PTR;
32 
33 /* S3C2440: Mpll,Upll = (2*m * Fin) / (p * 2^s) 
34  * m = M (the value for divider M)+ 8, p = P (the value for divider P) + 2
35  */
36 #define S3C2440_MPLL_400MHZ     ((0x7f<<12)|(0x02<<4)|(0x01))
37 #define S3C2440_UPLL_48MHZ      ((0x38<<12)|(0x02<<4)|(0x03))
38 #define S3C2440_CLKDIV          0x05    /* FCLK:HCLK:PCLK = 1:4:8 */
39 
40 /* S3C2410: Mpll,Upll = (m * Fin) / (p * 2^s)
41  * m = M (the value for divider M)+ 8, p = P (the value for divider P) + 2
42  */
43 #define S3C2410_MPLL_200MHZ     ((0x5c<<12)|(0x04<<4)|(0x00))
44 #define S3C2410_UPLL_48MHZ      ((0x28<<12)|(0x01<<4)|(0x02))
45 #define S3C2410_CLKDIV          0x03    /* FCLK:HCLK:PCLK = 1:2:4 */
46 
47 static inline void delay (unsigned long loops)
48 {
49     __asm__ volatile ("1:\n"
50       "subs %0, %1, #1\n"
51       "bne 1b":"=r" (loops):"0" (loops));
52 }
53 
54 /*
55  * Miscellaneous platform dependent initialisations
56  */
57 
58 int board_init (void)
59 {
60     S3C24X0_CLOCK_POWER * const clk_power = S3C24X0_GetBase_CLOCK_POWER();
61     S3C24X0_GPIO * const gpio = S3C24X0_GetBase_GPIO();
62 
63     /* set up the I/O ports */
64     gpio->GPACON = 0x007FFFFF;
65     gpio->GPBCON = 0x00044555;
66     gpio->GPBUP = 0x000007FF;
67     gpio->GPCCON = 0xAAAAAAAA;
68     gpio->GPCUP = 0x0000FFFF;
69     gpio->GPDCON = 0xAAAAAAAA;
70     gpio->GPDUP = 0x0000FFFF;
71     gpio->GPECON = 0xAAAAAAAA;
72     gpio->GPEUP = 0x0000FFFF;
73     gpio->GPFCON = 0x000055AA;
74     gpio->GPFUP = 0x000000FF;
75     gpio->GPGCON = 0xFF95FFBA;
76     gpio->GPGUP = 0x0000FFFF;
77     gpio->GPHCON = 0x002AFAAA;
78     gpio->GPHUP = 0x000007FF;
79 
80     /* support both of S3C2410 and S3C2440, by www.arm9.net */
81     if ((gpio->GSTATUS1 == 0x32410000) || (gpio->GSTATUS1 == 0x32410002))
82     {
83         /* FCLK:HCLK:PCLK = 1:2:4 */
84         clk_power->CLKDIVN = S3C2410_CLKDIV;
85 
86         /* change to asynchronous bus mod */
87         __asm__(    "mrc    p15, 0, r1, c1, c0, 0\n"    /* read ctrl register   */  
88                     "orr    r1, r1, #0xc0000000\n"      /* Asynchronous         */  
89                     "mcr    p15, 0, r1, c1, c0, 0\n"    /* write ctrl register  */  
90                     :::"r1"
91                     );
92         
93         /* to reduce PLL lock time, adjust the LOCKTIME register */
94         clk_power->LOCKTIME = 0xFFFFFF;
95 
96         /* configure MPLL */
97         clk_power->MPLLCON = S3C2410_MPLL_200MHZ;
98 
99         /* some delay between MPLL and UPLL */
100         delay (4000);
101 
102         /* configure UPLL */
103         clk_power->UPLLCON = S3C2410_UPLL_48MHZ;
104 
105         /* some delay between MPLL and UPLL */
106         delay (8000);
107         
108         /* arch number of SMDK2410-Board */
109         gd->bd->bi_arch_number = MACH_TYPE_SMDK2410;
110     }
111     else
112     {
113         /* FCLK:HCLK:PCLK = 1:4:8 */
114         clk_power->CLKDIVN = S3C2440_CLKDIV;
115 
116         /* change to asynchronous bus mod */
117         __asm__(    "mrc    p15, 0, r1, c1, c0, 0\n"    /* read ctrl register   */  
118                     "orr    r1, r1, #0xc0000000\n"      /* Asynchronous         */  
119                     "mcr    p15, 0, r1, c1, c0, 0\n"    /* write ctrl register  */  
120                     :::"r1"
121                     );
122 
123         /* to reduce PLL lock time, adjust the LOCKTIME register */
124         clk_power->LOCKTIME = 0xFFFFFF;
125 
126         /* configure MPLL */
127         clk_power->MPLLCON = S3C2440_MPLL_400MHZ;
128 
129         /* some delay between MPLL and UPLL */
130         delay (4000);
131 
132         /* configure UPLL */
133         clk_power->UPLLCON = S3C2440_UPLL_48MHZ;
134 
135         /* some delay between MPLL and UPLL */
136         delay (8000);
137         
138         /* arch number of SMDK2440-Board */
139         gd->bd->bi_arch_number = 782; //MACH_TYPE_S3C2440;
140     }
141 
142     /* adress of boot parameters */
143     gd->bd->bi_boot_params = 0x30000100;
144 
145     icache_enable();
146     dcache_enable();
147 
148     return 0;
149 }
150 
151 int dram_init (void)
152 {
153     gd->bd->bi_dram[0].start = PHYS_SDRAM_1;
154     gd->bd->bi_dram[0].size = PHYS_SDRAM_1_SIZE;
155 
156     return 0;
157 }
