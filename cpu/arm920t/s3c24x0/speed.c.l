01 /*
02  * (C) Copyright 2001-2004
03  * Wolfgang Denk, DENX Software Engineering, wd@denx.de.
04  *
05  * (C) Copyright 2002
06  * David Mueller, ELSOFT AG, d.mueller@elsoft.ch
07  *
08  * See file CREDITS for list of people who contributed to this
09  * project.
10  *
11  * This program is free software; you can redistribute it and/or
12  * modify it under the terms of the GNU General Public License as
13  * published by the Free Software Foundation; either version 2 of
14  * the License, or (at your option) any later version.
15  *
16  * This program is distributed in the hope that it will be useful,
17  * but WITHOUT ANY WARRANTY; without even the implied warranty of
18  * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
19  * GNU General Public License for more details.
20  *
21  * You should have received a copy of the GNU General Public License
22  * along with this program; if not, write to the Free Software
23  * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
24  * MA 02111-1307 USA
25  */
26 
27 /* This code should work for both the S3C2400 and the S3C2410
28  * as they seem to have the same PLL and clock machinery inside.
29  * The different address mapping is handled by the s3c24xx.h files below.
30  */
31 
32 #include <common.h>
33 #if defined(CONFIG_S3C2400) || defined (CONFIG_S3C2410) || defined (CONFIG_TRAB)
34 
35 #if defined(CONFIG_S3C2400)
36 #include <s3c2400.h>
37 #elif defined(CONFIG_S3C2410)
38 #include <s3c2410.h>
39 #endif
40 
41 DECLARE_GLOBAL_DATA_PTR;
42 
43 #define MPLL 0
44 #define UPLL 1
45 
46 /* ------------------------------------------------------------------------- */
47 /* NOTE: This describes the proper use of this file.
48  *
49  * CONFIG_SYS_CLK_FREQ should be defined as the input frequency of the PLL.
50  *
51  * get_FCLK(), get_HCLK(), get_PCLK() and get_UCLK() return the clock of
52  * the specified bus in HZ.
53  */
54 /* ------------------------------------------------------------------------- */
55 
56 static ulong get_PLLCLK(int pllreg)
57 {
58     S3C24X0_CLOCK_POWER * const clk_power = S3C24X0_GetBase_CLOCK_POWER();
59     ulong r, m, p, s;
60 
61     if (pllreg == MPLL)
62     r = clk_power->MPLLCON;
63     else if (pllreg == UPLL)
64     r = clk_power->UPLLCON;
65     else
66     hang();
67 
68     m = ((r & 0xFF000) >> 12) + 8;
69     p = ((r & 0x003F0) >> 4) + 2;
70     s = r & 0x3;
71 
72     /* support both of S3C2410 and S3C2440, by www.arm9.net */
73     if (gd->bd->bi_arch_number == MACH_TYPE_SMDK2410)
74         return((CONFIG_SYS_CLK_FREQ * m) / (p << s));
75     else
76         return((CONFIG_SYS_CLK_FREQ * m * 2) / (p << s));   /* S3C2440 */
77 }
78 
79 /* return FCLK frequency */
80 ulong get_FCLK(void)
81 {
82     return(get_PLLCLK(MPLL));
83 }
84 
85 /* for s3c2440 */
86 #define S3C2440_CLKDIVN_PDIVN        (1<<0)
87 #define S3C2440_CLKDIVN_HDIVN_MASK   (3<<1)
88 #define S3C2440_CLKDIVN_HDIVN_1      (0<<1)
89 #define S3C2440_CLKDIVN_HDIVN_2      (1<<1)
90 #define S3C2440_CLKDIVN_HDIVN_4_8    (2<<1)
91 #define S3C2440_CLKDIVN_HDIVN_3_6    (3<<1)
92 #define S3C2440_CLKDIVN_UCLK         (1<<3)
93 
94 #define S3C2440_CAMDIVN_CAMCLK_MASK  (0xf<<0)
95 #define S3C2440_CAMDIVN_CAMCLK_SEL   (1<<4)
96 #define S3C2440_CAMDIVN_HCLK3_HALF   (1<<8)
97 #define S3C2440_CAMDIVN_HCLK4_HALF   (1<<9)
98 #define S3C2440_CAMDIVN_DVSEN        (1<<12)
99 
100 /* return HCLK frequency */
101 ulong get_HCLK(void)
102 {
103     S3C24X0_CLOCK_POWER * const clk_power = S3C24X0_GetBase_CLOCK_POWER();
104     unsigned long clkdiv;
105     unsigned long camdiv;
106     int hdiv = 1;
107 
108     /* support both of S3C2410 and S3C2440, by www.arm9.net */
109     if (gd->bd->bi_arch_number == MACH_TYPE_SMDK2410)
110         return((clk_power->CLKDIVN & 0x2) ? get_FCLK()/2 : get_FCLK());
111     else
112     {
113         clkdiv = clk_power->CLKDIVN;
114         camdiv = clk_power->CAMDIVN;
115 
116         /* work out clock scalings */
117 
118         switch (clkdiv & S3C2440_CLKDIVN_HDIVN_MASK) {
119         case S3C2440_CLKDIVN_HDIVN_1:
120             hdiv = 1;
121             break;
122 
123         case S3C2440_CLKDIVN_HDIVN_2:
124             hdiv = 2;
125             break;
126 
127         case S3C2440_CLKDIVN_HDIVN_4_8:
128             hdiv = (camdiv & S3C2440_CAMDIVN_HCLK4_HALF) ? 8 : 4;
129             break;
130 
131         case S3C2440_CLKDIVN_HDIVN_3_6:
132             hdiv = (camdiv & S3C2440_CAMDIVN_HCLK3_HALF) ? 6 : 3;
133             break;
134         }
135 
136         return get_FCLK() / hdiv;
137     }
138 }
139 
140 /* return PCLK frequency */
141 ulong get_PCLK(void)
142 {
143     S3C24X0_CLOCK_POWER * const clk_power = S3C24X0_GetBase_CLOCK_POWER();
144     unsigned long clkdiv;
145     unsigned long camdiv;
146     int hdiv = 1;
147 
148     /* support both of S3C2410 and S3C2440, by www.arm9.net */
149     if (gd->bd->bi_arch_number == MACH_TYPE_SMDK2410)
150         return((clk_power->CLKDIVN & 0x1) ? get_HCLK()/2 : get_HCLK());
151     else
152     {   
153         clkdiv = clk_power->CLKDIVN;
154         camdiv = clk_power->CAMDIVN;
155 
156         /* work out clock scalings */
157 
158         switch (clkdiv & S3C2440_CLKDIVN_HDIVN_MASK) {
159         case S3C2440_CLKDIVN_HDIVN_1:
160             hdiv = 1;
161             break;
162 
163         case S3C2440_CLKDIVN_HDIVN_2:
164             hdiv = 2;
165             break;
166 
167         case S3C2440_CLKDIVN_HDIVN_4_8:
168             hdiv = (camdiv & S3C2440_CAMDIVN_HCLK4_HALF) ? 8 : 4;
169             break;
170 
171         case S3C2440_CLKDIVN_HDIVN_3_6:
172             hdiv = (camdiv & S3C2440_CAMDIVN_HCLK3_HALF) ? 6 : 3;
173             break;
174         }
175 
176         return get_FCLK() / hdiv / ((clkdiv & S3C2440_CLKDIVN_PDIVN)? 2:1);
177     }        
178 }
179 
180 /* return UCLK frequency */
181 ulong get_UCLK(void)
182 {
183     return(get_PLLCLK(UPLL));
184 }
185 
186 #endif /* defined(CONFIG_S3C2400) || defined (CONFIG_S3C2410) || defined (CONFIG_TRAB) */
