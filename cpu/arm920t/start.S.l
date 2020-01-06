01 /*
02  *  armboot - Startup Code for ARM920 CPU-core
03  *
04  *  Copyright (c) 2001	Marius Gröger <mag@sysgo.de>
05  *  Copyright (c) 2002	Alex Züpke <azu@sysgo.de>
06  *  Copyright (c) 2002	Gary Jennejohn <gj@denx.de>
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
27 
28 #include <config.h>
29 #include <version.h>
30 
31 
32 /*
33  *************************************************************************
34  *
35  * Jump vector table as in table 3.1 in [1]
36  *
37  *************************************************************************
38  */
39 
40 
41 .globl _start
42 _start:	b       reset
43 	ldr	pc, _undefined_instruction
44 	ldr	pc, _software_interrupt
45 	ldr	pc, _prefetch_abort
46 	ldr	pc, _data_abort
47 	ldr	pc, _not_used
48 	ldr	pc, _irq
49 	ldr	pc, _fiq
50 
51 _undefined_instruction:	.word undefined_instruction
52 _software_interrupt:	.word software_interrupt
53 _prefetch_abort:	.word prefetch_abort
54 _data_abort:		.word data_abort
55 _not_used:		.word not_used
56 _irq:			.word irq
57 _fiq:			.word fiq
58 
59 	.balignl 16,0xdeadbeef
60 
61 
62 /*
63  *************************************************************************
64  *
65  * Startup Code (reset vector)
66  *
67  * do important init only if we don't start from memory!
68  * relocate armboot to ram
69  * setup stack
70  * jump to second stage
71  *
72  *************************************************************************
73  */
74 
75 _TEXT_BASE:
76 	.word	TEXT_BASE
77 
78 .globl _armboot_start
79 _armboot_start:
80 	.word _start
81 
82 /*
83  * These are defined in the board-specific linker script.
84  */
85 .globl _bss_start
86 _bss_start:
87 	.word __bss_start
88 
89 .globl _bss_end
90 _bss_end:
91 	.word _end
92 
93 #ifdef CONFIG_USE_IRQ
94 /* IRQ stack memory (calculated at run-time) */
95 .globl IRQ_STACK_START
96 IRQ_STACK_START:
97 	.word	0x0badc0de
98 
99 /* IRQ stack memory (calculated at run-time) */
100 .globl FIQ_STACK_START
101 FIQ_STACK_START:
102 	.word 0x0badc0de
103 #endif
104 
105 
106 /*
107  * the actual reset code
108  */
109 
110 reset:
111 	/*
112 	 * set the cpu to SVC32 mode
113 	 */
114 	mrs	r0,cpsr
115 	bic	r0,r0,#0x1f
116 	orr	r0,r0,#0xd3
117 	msr	cpsr,r0
118 
119 /* turn off the watchdog */
120 #if defined(CONFIG_S3C2400)
121 # define pWTCON		0x15300000
122 # define INTMSK		0x14400008	/* Interupt-Controller base addresses */
123 # define CLKDIVN	0x14800014	/* clock divisor register */
124 #elif defined(CONFIG_S3C2410)
125 # define pWTCON		0x53000000
126 # define INTMSK		0x4A000008	/* Interupt-Controller base addresses */
127 # define INTSUBMSK	0x4A00001C
128 # define CLKDIVN	0x4C000014	/* clock divisor register */
129 #endif
130 
131 #if defined(CONFIG_S3C2400) || defined(CONFIG_S3C2410)
132 	ldr     r0, =pWTCON
133 	mov     r1, #0x0
134 	str     r1, [r0]
135 
136 	/*
137 	 * mask all IRQs by setting all bits in the INTMR - default
138 	 */
139 	mov	r1, #0xffffffff
140 	ldr	r0, =INTMSK
141 	str	r1, [r0]
142 # if defined(CONFIG_S3C2410)
143 	ldr	r1, =0x3ff
144 	ldr	r0, =INTSUBMSK
145 	str	r1, [r0]
146 # endif
147 
148 	/* FCLK:HCLK:PCLK = 1:2:4 */
149 	/* default FCLK is 120 MHz ! */
150 	ldr	r0, =CLKDIVN
151 	mov	r1, #3
152 	str	r1, [r0]
153 #endif	/* CONFIG_S3C2400 || CONFIG_S3C2410 */
154 
155 	/*
156 	 * we do sys-critical inits only at reboot,
157 	 * not when booting from ram!
158 	 */
159 #ifndef CONFIG_SKIP_LOWLEVEL_INIT
160 	bl	cpu_init_crit
161 #endif
162 
163 #ifndef CONFIG_SKIP_RELOCATE_UBOOT
164 relocate:				/* relocate U-Boot to RAM	    */
165 	adr	r0, _start		/* r0 <- current position of code   */
166 	ldr	r1, _TEXT_BASE		/* test if we run from flash or RAM */
167 	cmp     r0, r1                  /* don't reloc during debug         */
168 	beq     stack_setup
169 
170 	ldr	r2, _armboot_start
171 	ldr	r3, _bss_start
172 	sub	r2, r3, r2		/* r2 <- size of armboot            */
173 	add	r2, r0, r2		/* r2 <- source end address         */
174 
175 copy_loop:
176 	ldmia	r0!, {r3-r10}		/* copy from source address [r0]    */
177 	stmia	r1!, {r3-r10}		/* copy to   target address [r1]    */
178 	cmp	r0, r2			/* until source end addreee [r2]    */
179 	ble	copy_loop
180 #endif	/* CONFIG_SKIP_RELOCATE_UBOOT */
181 
182 	/* Set up the stack						    */
183 stack_setup:
184 	ldr	r0, _TEXT_BASE		/* upper 128 KiB: relocated uboot   */
185 	sub	r0, r0, #CFG_MALLOC_LEN	/* malloc area                      */
186 	sub	r0, r0, #CFG_GBL_DATA_SIZE /* bdinfo                        */
187 #ifdef CONFIG_USE_IRQ
188 	sub	r0, r0, #(CONFIG_STACKSIZE_IRQ+CONFIG_STACKSIZE_FIQ)
189 #endif
190 	sub	sp, r0, #12		/* leave 3 words for abort-stack    */
191 
192 clear_bss:
193 	ldr	r0, _bss_start		/* find start of bss segment        */
194 	ldr	r1, _bss_end		/* stop here                        */
195 	mov 	r2, #0x00000000		/* clear                            */
196 
197 clbss_l:str	r2, [r0]		/* clear loop...                    */
198 	add	r0, r0, #4
199 	cmp	r0, r1
200 	ble	clbss_l
201 
202 #if 0
203 	/* try doing this stuff after the relocation */
204 	ldr     r0, =pWTCON
205 	mov     r1, #0x0
206 	str     r1, [r0]
207 
208 	/*
209 	 * mask all IRQs by setting all bits in the INTMR - default
210 	 */
211 	mov	r1, #0xffffffff
212 	ldr	r0, =INTMR
213 	str	r1, [r0]
214 
215 	/* FCLK:HCLK:PCLK = 1:2:4 */
216 	/* default FCLK is 120 MHz ! */
217 	ldr	r0, =CLKDIVN
218 	mov	r1, #3
219 	str	r1, [r0]
220 	/* END stuff after relocation */
221 #endif
222 
223 	ldr	pc, _start_armboot
224 
225 _start_armboot:	.word start_armboot
226 
227 
228 /*
229  *************************************************************************
230  *
231  * CPU_init_critical registers
232  *
233  * setup important registers
234  * setup memory timing
235  *
236  *************************************************************************
237  */
238 
239 
240 #ifndef CONFIG_SKIP_LOWLEVEL_INIT
241 cpu_init_crit:
242 	/*
243 	 * flush v4 I/D caches
244 	 */
245 	mov	r0, #0
246 	mcr	p15, 0, r0, c7, c7, 0	/* flush v3/v4 cache */
247 	mcr	p15, 0, r0, c8, c7, 0	/* flush v4 TLB */
248 
249 	/*
250 	 * disable MMU stuff and caches
251 	 */
252 	mrc	p15, 0, r0, c1, c0, 0
253 	bic	r0, r0, #0x00002300	@ clear bits 13, 9:8 (--V- --RS)
254 	bic	r0, r0, #0x00000087	@ clear bits 7, 2:0 (B--- -CAM)
255 	orr	r0, r0, #0x00000002	@ set bit 2 (A) Align
256 	orr	r0, r0, #0x00001000	@ set bit 12 (I) I-Cache
257 	mcr	p15, 0, r0, c1, c0, 0
258 
259 	/*
260 	 * before relocating, we have to setup RAM timing
261 	 * because memory timing is board-dependend, you will
262 	 * find a lowlevel_init.S in your board directory.
263 	 */
264 	mov	ip, lr
265 	bl	lowlevel_init
266 	mov	lr, ip
267 	mov	pc, lr
268 #endif /* CONFIG_SKIP_LOWLEVEL_INIT */
269 
270 /*
271  *************************************************************************
272  *
273  * Interrupt handling
274  *
275  *************************************************************************
276  */
277 
278 @
279 @ IRQ stack frame.
280 @
281 #define S_FRAME_SIZE	72
282 
283 #define S_OLD_R0	68
284 #define S_PSR		64
285 #define S_PC		60
286 #define S_LR		56
287 #define S_SP		52
288 
289 #define S_IP		48
290 #define S_FP		44
291 #define S_R10		40
292 #define S_R9		36
293 #define S_R8		32
294 #define S_R7		28
295 #define S_R6		24
296 #define S_R5		20
297 #define S_R4		16
298 #define S_R3		12
299 #define S_R2		8
300 #define S_R1		4
301 #define S_R0		0
302 
303 #define MODE_SVC 0x13
304 #define I_BIT	 0x80
305 
306 /*
307  * use bad_save_user_regs for abort/prefetch/undef/swi ...
308  * use irq_save_user_regs / irq_restore_user_regs for IRQ/FIQ handling
309  */
310 
311 	.macro	bad_save_user_regs
312 	sub	sp, sp, #S_FRAME_SIZE
313 	stmia	sp, {r0 - r12}			@ Calling r0-r12
314 	ldr	r2, _armboot_start
315 	sub	r2, r2, #(CONFIG_STACKSIZE+CFG_MALLOC_LEN)
316 	sub	r2, r2, #(CFG_GBL_DATA_SIZE+8)  @ set base 2 words into abort stack
317 	ldmia	r2, {r2 - r3}			@ get pc, cpsr
318 	add	r0, sp, #S_FRAME_SIZE		@ restore sp_SVC
319 
320 	add	r5, sp, #S_SP
321 	mov	r1, lr
322 	stmia	r5, {r0 - r3}			@ save sp_SVC, lr_SVC, pc, cpsr
323 	mov	r0, sp
324 	.endm
325 
326 	.macro	irq_save_user_regs
327 	sub	sp, sp, #S_FRAME_SIZE
328 	stmia	sp, {r0 - r12}			@ Calling r0-r12
329 	add     r8, sp, #S_PC
330 	stmdb   r8, {sp, lr}^                   @ Calling SP, LR
331 	str     lr, [r8, #0]                    @ Save calling PC
332 	mrs     r6, spsr
333 	str     r6, [r8, #4]                    @ Save CPSR
334 	str     r0, [r8, #8]                    @ Save OLD_R0
335 	mov	r0, sp
336 	.endm
337 
338 	.macro	irq_restore_user_regs
339 	ldmia	sp, {r0 - lr}^			@ Calling r0 - lr
340 	mov	r0, r0
341 	ldr	lr, [sp, #S_PC]			@ Get PC
342 	add	sp, sp, #S_FRAME_SIZE
343 	subs	pc, lr, #4			@ return & move spsr_svc into cpsr
344 	.endm
345 
346 	.macro get_bad_stack
347 	ldr	r13, _armboot_start		@ setup our mode stack
348 	sub	r13, r13, #(CONFIG_STACKSIZE+CFG_MALLOC_LEN)
349 	sub	r13, r13, #(CFG_GBL_DATA_SIZE+8) @ reserved a couple spots in abort stack
350 
351 	str	lr, [r13]			@ save caller lr / spsr
352 	mrs	lr, spsr
353 	str     lr, [r13, #4]
354 
355 	mov	r13, #MODE_SVC			@ prepare SVC-Mode
356 	@ msr	spsr_c, r13
357 	msr	spsr, r13
358 	mov	lr, pc
359 	movs	pc, lr
360 	.endm
361 
362 	.macro get_irq_stack			@ setup IRQ stack
363 	ldr	sp, IRQ_STACK_START
364 	.endm
365 
366 	.macro get_fiq_stack			@ setup FIQ stack
367 	ldr	sp, FIQ_STACK_START
368 	.endm
369 
370 /*
371  * exception handlers
372  */
373 	.align  5
374 undefined_instruction:
375 	get_bad_stack
376 	bad_save_user_regs
377 	bl 	do_undefined_instruction
378 
379 	.align	5
380 software_interrupt:
381 	get_bad_stack
382 	bad_save_user_regs
383 	bl 	do_software_interrupt
384 
385 	.align	5
386 prefetch_abort:
387 	get_bad_stack
388 	bad_save_user_regs
389 	bl 	do_prefetch_abort
390 
391 	.align	5
392 data_abort:
393 	get_bad_stack
394 	bad_save_user_regs
395 	bl 	do_data_abort
396 
397 	.align	5
398 not_used:
399 	get_bad_stack
400 	bad_save_user_regs
401 	bl 	do_not_used
402 
403 #ifdef CONFIG_USE_IRQ
404 
405 	.align	5
406 irq:
407 	get_irq_stack
408 	irq_save_user_regs
409 	bl 	do_irq
410 	irq_restore_user_regs
411 
412 	.align	5
413 fiq:
414 	get_fiq_stack
415 	/* someone ought to write a more effiction fiq_save_user_regs */
416 	irq_save_user_regs
417 	bl 	do_fiq
418 	irq_restore_user_regs
419 
420 #else
421 
422 	.align	5
423 irq:
424 	get_bad_stack
425 	bad_save_user_regs
426 	bl 	do_irq
427 
428 	.align	5
429 fiq:
430 	get_bad_stack
431 	bad_save_user_regs
432 	bl 	do_fiq
433 
434 #endif
