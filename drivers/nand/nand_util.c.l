01 /*
02  * drivers/nand/nand_util.c
03  *
04  * Copyright (C) 2006 by Weiss-Electronic GmbH.
05  * All rights reserved.
06  *
07  * @author: Guido Classen <clagix@gmail.com>
08  * @descr:  NAND Flash support
09  * @references: borrowed heavily from Linux mtd-utils code:
10  *      flash_eraseall.c by Arcom Control System Ltd
11  *      nandwrite.c by Steven J. Hill (sjhill@realitydiluted.com)
12  *                 and Thomas Gleixner (tglx@linutronix.de)
13  *
14  * See file CREDITS for list of people who contributed to this
15  * project.
16  *
17  * This program is free software; you can redistribute it and/or
18  * modify it under the terms of the GNU General Public License version
19  * 2 as published by the Free Software Foundation.
20  *
21  * This program is distributed in the hope that it will be useful,
22  * but WITHOUT ANY WARRANTY; without even the implied warranty of
23  * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
24  * GNU General Public License for more details.
25  *
26  * You should have received a copy of the GNU General Public License
27  * along with this program; if not, write to the Free Software
28  * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
29  * MA 02111-1307 USA
30  *
31  */
32 
33 #include <common.h>
34 
35 #if (CONFIG_COMMANDS & CFG_CMD_NAND) && !defined(CFG_NAND_LEGACY)
36 
37 #include <command.h>
38 #include <watchdog.h>
39 #include <malloc.h>
40 
41 #include <nand.h>
42 #include <jffs2/jffs2.h>
43 
44 typedef struct erase_info erase_info_t;
45 typedef struct mtd_info   mtd_info_t;
46 
47 /* support only for native endian JFFS2 */
48 #define cpu_to_je16(x) (x)
49 #define cpu_to_je32(x) (x)
50 
51 /*****************************************************************************/
52 static int nand_block_bad_scrub(struct mtd_info *mtd, loff_t ofs, int getchip)
53 {
54     return 0;
55 }
56 
57 /**
58  * nand_erase_opts: - erase NAND flash with support for various options
59  *            (jffs2 formating)
60  *
61  * @param meminfo   NAND device to erase
62  * @param opts      options,  @see struct nand_erase_options
63  * @return      0 in case of success
64  *
65  * This code is ported from flash_eraseall.c from Linux mtd utils by
66  * Arcom Control System Ltd.
67  */
68 int nand_erase_opts(nand_info_t *meminfo, const nand_erase_options_t *opts)
69 {
70     struct jffs2_unknown_node cleanmarker;
71     int clmpos = 0;
72     int clmlen = 8;
73     erase_info_t erase;
74     ulong erase_length;
75     int isNAND;
76     int bbtest = 1;
77     int result;
78     int percent_complete = -1;
79     int (*nand_block_bad_old)(struct mtd_info *, loff_t, int) = NULL;
80     const char *mtd_device = meminfo->name;
81 
82     memset(&erase, 0, sizeof(erase));
83 
84     erase.mtd = meminfo;
85     erase.len  = meminfo->erasesize;
86     erase.addr = opts->offset;
87     erase_length = opts->length;
88 
89     isNAND = meminfo->type == MTD_NANDFLASH ? 1 : 0;
90 
91     if (opts->jffs2) {
92         cleanmarker.magic = cpu_to_je16 (JFFS2_MAGIC_BITMASK);
93         cleanmarker.nodetype = cpu_to_je16 (JFFS2_NODETYPE_CLEANMARKER);
94         if (isNAND) {
95             struct nand_oobinfo *oobinfo = &meminfo->oobinfo;
96 
97             /* check for autoplacement */
98             if (oobinfo->useecc == MTD_NANDECC_AUTOPLACE) {
99                 /* get the position of the free bytes */
100                 if (!oobinfo->oobfree[0][1]) {
101                     printf(" Eeep. Autoplacement selected "
102                            "and no empty space in oob\n");
103                     return -1;
104                 }
105                 clmpos = oobinfo->oobfree[0][0];
106                 clmlen = oobinfo->oobfree[0][1];
107                 if (clmlen > 8)
108                     clmlen = 8;
109             } else {
110                 /* legacy mode */
111                 switch (meminfo->oobsize) {
112                 case 8:
113                     clmpos = 6;
114                     clmlen = 2;
115                     break;
116                 case 16:
117                     clmpos = 8;
118                     clmlen = 8;
119                     break;
120                 case 64:
121                     clmpos = 16;
122                     clmlen = 8;
123                     break;
124                 }
125             }
126 
127             cleanmarker.totlen = cpu_to_je32(8);
128         } else {
129             cleanmarker.totlen =
130                 cpu_to_je32(sizeof(struct jffs2_unknown_node));
131         }
132         cleanmarker.hdr_crc =  cpu_to_je32(
133             crc32_no_comp(0, (unsigned char *) &cleanmarker,
134                       sizeof(struct jffs2_unknown_node) - 4));
135     }
136 
137     /* scrub option allows to erase badblock. To prevent internal
138      * check from erase() method, set block check method to dummy
139      * and disable bad block table while erasing.
140      */
141     if (opts->scrub) {
142         struct nand_chip *priv_nand = meminfo->priv;
143 
144         nand_block_bad_old = priv_nand->block_bad;
145         priv_nand->block_bad = nand_block_bad_scrub;
146         /* we don't need the bad block table anymore...
147          * after scrub, there are no bad blocks left!
148          */
149         if (priv_nand->bbt) {
150             kfree(priv_nand->bbt);
151         }
152         priv_nand->bbt = NULL;
153     }
154 
155     for (;
156          erase.addr < opts->offset + erase_length;
157          erase.addr += meminfo->erasesize) {
158 
159         WATCHDOG_RESET ();
160 
161         if (!opts->scrub && bbtest) {
162             int ret = meminfo->block_isbad(meminfo, erase.addr);
163             if (ret > 0) {
164                 if (!opts->quiet)
165                     printf("\rSkipping bad block at  "
166                            "0x%08x                   "
167                            "                         \n",
168                            erase.addr);
169                 continue;
170 
171             } else if (ret < 0) {
172                 printf("\n%s: MTD get bad block failed: %d\n",
173                        mtd_device,
174                        ret);
175                 return -1;
176             }
177         }
178 
179         result = meminfo->erase(meminfo, &erase);
180         if (result != 0) {
181             printf("\n%s: MTD Erase failure: %d\n",
182                    mtd_device, result);
183             continue;
184         }
185 
186         /* format for JFFS2 ? */
187         if (opts->jffs2) {
188 
189             /* write cleanmarker */
190             if (isNAND) {
191                 size_t written;
192                 result = meminfo->write_oob(meminfo,
193                                 erase.addr + clmpos,
194                                 clmlen,
195                                 &written,
196                                 (unsigned char *)
197                                 &cleanmarker);
198                 if (result != 0) {
199                     printf("\n%s: MTD writeoob failure: %d\n",
200                            mtd_device, result);
201                     continue;
202                 }
203             } else {
204                 printf("\n%s: this erase routine only supports"
205                        " NAND devices!\n",
206                        mtd_device);
207             }
208         }
209 
210         if (!opts->quiet) {
211             int percent = (int)
212                 ((unsigned long long)
213                  (erase.addr+meminfo->erasesize-opts->offset)
214                  * 100 / erase_length);
215 
216             /* output progress message only at whole percent
217              * steps to reduce the number of messages printed
218              * on (slow) serial consoles
219              */
220             if (percent != percent_complete) {
221                 percent_complete = percent;
222 
223                 printf("\rErasing at 0x%x -- %3d%% complete.",
224                        erase.addr, percent);
225 
226                 if (opts->jffs2 && result == 0)
227                     printf(" Cleanmarker written at 0x%x.",
228                            erase.addr);
229             }
230         }
231     }
232     if (!opts->quiet)
233         printf("\n");
234 
235     if (nand_block_bad_old) {
236         struct nand_chip *priv_nand = meminfo->priv;
237 
238         priv_nand->block_bad = nand_block_bad_old;
239         priv_nand->scan_bbt(meminfo);
240     }
241 
242     return 0;
243 }
244 
245 #define MAX_PAGE_SIZE   2048
246 #define MAX_OOB_SIZE    64
247 
248 /*
249  * buffer array used for writing data
250  */
251 static unsigned char data_buf[MAX_PAGE_SIZE];
252 static unsigned char oob_buf[MAX_OOB_SIZE];
253 
254 /* OOB layouts to pass into the kernel as default */
255 static struct nand_oobinfo none_oobinfo = {
256     .useecc = MTD_NANDECC_OFF,
257 };
258 
259 static struct nand_oobinfo jffs2_oobinfo = {
260     .useecc = MTD_NANDECC_PLACE,
261     .eccbytes = 6,
262     .eccpos = { 0, 1, 2, 3, 6, 7 }
263 };
264 
265 static struct nand_oobinfo yaffs_oobinfo = {
266     .useecc = MTD_NANDECC_PLACE,
267     .eccbytes = 6,
268     .eccpos = { 8, 9, 10, 13, 14, 15}
269 };
270 
271 static struct nand_oobinfo autoplace_oobinfo = {
272     .useecc = MTD_NANDECC_AUTOPLACE
273 };
274 
275 /**
276  * nand_write_opts: - write image to NAND flash with support for various options
277  *
278  * @param meminfo   NAND device to erase
279  * @param opts      write options (@see nand_write_options)
280  * @return      0 in case of success
281  *
282  * This code is ported from nandwrite.c from Linux mtd utils by
283  * Steven J. Hill and Thomas Gleixner.
284  */
285 int nand_write_opts(nand_info_t *meminfo, const nand_write_options_t *opts)
286 {
287     int imglen = 0;
288     int pagelen;
289     int baderaseblock;
290     int blockstart = -1;
291     loff_t offs;
292     int readlen;
293     int oobinfochanged = 0;
294     int percent_complete = -1;
295     struct nand_oobinfo old_oobinfo;
296     ulong mtdoffset = opts->offset;
297     ulong erasesize_blockalign;
298     u_char *buffer = opts->buffer;
299     size_t written;
300     int result;
301     int skipfirstblk = opts->skipfirstblk;
302 
303     if (opts->pad && opts->writeoob) {
304         printf("Can't pad when oob data is present.\n");
305         return -1;
306     }
307 
308     /* set erasesize to specified number of blocks - to match
309      * jffs2 (virtual) block size */
310     if (opts->blockalign == 0) {
311         erasesize_blockalign = meminfo->erasesize;
312     } else {
313         erasesize_blockalign = meminfo->erasesize * opts->blockalign;
314     }
315 
316     /* make sure device page sizes are valid */
317     if (!(meminfo->oobsize == 16 && meminfo->oobblock == 512)
318         && !(meminfo->oobsize == 8 && meminfo->oobblock == 256)
319         && !(meminfo->oobsize == 64 && meminfo->oobblock == 2048)) {
320         printf("Unknown flash (not normal NAND)\n");
321         return -1;
322     }
323 
324     /* read the current oob info */
325     memcpy(&old_oobinfo, &meminfo->oobinfo, sizeof(old_oobinfo));
326 
327     /* write without ecc? */
328     if (opts->noecc) {
329         memcpy(&meminfo->oobinfo, &none_oobinfo,
330                sizeof(meminfo->oobinfo));
331         oobinfochanged = 1;
332     }
333 
334     /* autoplace ECC? */
335     if (opts->autoplace && (old_oobinfo.useecc != MTD_NANDECC_AUTOPLACE)) {
336 
337         memcpy(&meminfo->oobinfo, &autoplace_oobinfo,
338                sizeof(meminfo->oobinfo));
339         oobinfochanged = 1;
340     }
341 
342     /* force OOB layout for jffs2 or yaffs? */
343     if (opts->forcejffs2 || opts->forceyaffs) {
344         struct nand_oobinfo *oobsel =
345             opts->forcejffs2 ? &jffs2_oobinfo : &yaffs_oobinfo;
346 
347         if (meminfo->oobsize == 8) {
348             if (opts->forceyaffs) {
349                 printf("YAFSS cannot operate on "
350                        "256 Byte page size\n");
351                 goto restoreoob;
352             }
353             /* Adjust number of ecc bytes */
354             jffs2_oobinfo.eccbytes = 3;
355         }
356 
357         memcpy(&meminfo->oobinfo, oobsel, sizeof(meminfo->oobinfo));
358     }
359 
360     /* get image length */
361     imglen = opts->length;
362     pagelen = meminfo->oobblock
363         + ((opts->writeoob != 0) ? meminfo->oobsize : 0);
364 
365     /* check, if file is pagealigned */
366     if ((!opts->pad) && ((imglen % pagelen) != 0)) {
367         printf("Input block length is not page aligned\n");
368         goto restoreoob;
369     }
370 
371     /* check, if length fits into device */
372     if (((imglen / pagelen) * meminfo->oobblock)
373          > (meminfo->size - opts->offset)) {
374         printf("Image %d bytes, NAND page %d bytes, "
375                "OOB area %u bytes, device size %u bytes\n",
376                imglen, pagelen, meminfo->oobblock, meminfo->size);
377         printf("Input block does not fit into device\n");
378         goto restoreoob;
379     }
380 
381     if (!opts->quiet)
382         printf("\n");
383 
384     /* get data from input and write to the device */
385     while (imglen && (mtdoffset < meminfo->size)) {
386 
387         WATCHDOG_RESET ();
388 
389         /*
390          * new eraseblock, check for bad block(s). Stay in the
391          * loop to be sure if the offset changes because of
392          * a bad block, that the next block that will be
393          * written to is also checked. Thus avoiding errors if
394          * the block(s) after the skipped block(s) is also bad
395          * (number of blocks depending on the blockalign
396          */
397         while (blockstart != (mtdoffset & (~erasesize_blockalign+1))) {
398             blockstart = mtdoffset & (~erasesize_blockalign+1);
399             offs = blockstart;
400             baderaseblock = 0;
401 
402             /* check all the blocks in an erase block for
403              * bad blocks */
404             do {
405                 int ret = meminfo->block_isbad(meminfo, offs);
406 
407                 if (ret < 0) {
408                     printf("Bad block check failed\n");
409                     goto restoreoob;
410                 }
411                 if (ret == 1) {
412                     baderaseblock = 1;
413                     if (!opts->quiet)
414                         printf("\rBad block at 0x%lx "
415                                "in erase block from "
416                                "0x%x will be skipped\n",
417                                (long) offs,
418                                blockstart);
419                 }
420 
421                 if (baderaseblock) {
422                     mtdoffset = blockstart
423                         + erasesize_blockalign;
424                 }
425                 offs +=  erasesize_blockalign
426                     / opts->blockalign;
427             } while (offs < blockstart + erasesize_blockalign);
428         }
429 
430         /* skip the first good block when wirte yaffs image, by www.arm9.net */
431         if (skipfirstblk) {
432             mtdoffset += erasesize_blockalign;
433             skipfirstblk = 0;
434             continue;
435         }
436 
437         readlen = meminfo->oobblock;
438         if (opts->pad && (imglen < readlen)) {
439             readlen = imglen;
440             memset(data_buf + readlen, 0xff,
441                    meminfo->oobblock - readlen);
442         }
443 
444         /* read page data from input memory buffer */
445         memcpy(data_buf, buffer, readlen);
446         buffer += readlen;
447 
448         if (opts->writeoob) {
449             /* read OOB data from input memory block, exit
450              * on failure */
451             memcpy(oob_buf, buffer, meminfo->oobsize);
452             buffer += meminfo->oobsize;
453 
454             /* write OOB data first, as ecc will be placed
455              * in there*/
456             result = meminfo->write_oob(meminfo,
457                             mtdoffset,
458                             meminfo->oobsize,
459                             &written,
460                             (unsigned char *)
461                             &oob_buf);
462 
463             if (result != 0) {
464                 printf("\nMTD writeoob failure: %d\n",
465                        result);
466                 goto restoreoob;
467             }
468             imglen -= meminfo->oobsize;
469         }
470 
471         /* write out the page data */
472         result = meminfo->write(meminfo,
473                     mtdoffset,
474                     meminfo->oobblock,
475                     &written,
476                     (unsigned char *) &data_buf);
477 
478         if (result != 0) {
479             printf("writing NAND page at offset 0x%lx failed\n",
480                    mtdoffset);
481             goto restoreoob;
482         }
483         imglen -= readlen;
484 
485         if (!opts->quiet) {
486             int percent = (int)
487                 ((unsigned long long)
488                  (opts->length-imglen) * 100
489                  / opts->length);
490             /* output progress message only at whole percent
491              * steps to reduce the number of messages printed
492              * on (slow) serial consoles
493              */
494             if (percent != percent_complete) {
495                 printf("\rWriting data at 0x%x "
496                        "-- %3d%% complete.",
497                        mtdoffset, percent);
498                 percent_complete = percent;
499             }
500         }
501 
502         mtdoffset += meminfo->oobblock;
503     }
504 
505     if (!opts->quiet)
506         printf("\n");
507 
508 restoreoob:
509     if (oobinfochanged) {
510         memcpy(&meminfo->oobinfo, &old_oobinfo,
511                sizeof(meminfo->oobinfo));
512     }
513 
514     if (imglen > 0) {
515         printf("Data did not fit into device, due to bad blocks\n");
516         return -1;
517     }
518 
519     /* return happy */
520     return 0;
521 }
522 
523 /**
524  * nand_read_opts: - read image from NAND flash with support for various options
525  *
526  * @param meminfo   NAND device to erase
527  * @param opts      read options (@see struct nand_read_options)
528  * @return      0 in case of success
529  *
530  */
531 int nand_read_opts(nand_info_t *meminfo, const nand_read_options_t *opts)
532 {
533     int imglen = opts->length;
534     int pagelen;
535     int baderaseblock;
536     int blockstart = -1;
537     int percent_complete = -1;
538     loff_t offs;
539     size_t readlen;
540     ulong mtdoffset = opts->offset;
541     u_char *buffer = opts->buffer;
542     int result;
543 
544     /* make sure device page sizes are valid */
545     if (!(meminfo->oobsize == 16 && meminfo->oobblock == 512)
546         && !(meminfo->oobsize == 8 && meminfo->oobblock == 256)
547         && !(meminfo->oobsize == 64 && meminfo->oobblock == 2048)) {
548         printf("Unknown flash (not normal NAND)\n");
549         return -1;
550     }
551 
552     pagelen = meminfo->oobblock
553         + ((opts->readoob != 0) ? meminfo->oobsize : 0);
554 
555     /* check, if length is not larger than device */
556     if (((imglen / pagelen) * meminfo->oobblock)
557          > (meminfo->size - opts->offset)) {
558         printf("Image %d bytes, NAND page %d bytes, "
559                "OOB area %u bytes, device size %u bytes\n",
560                imglen, pagelen, meminfo->oobblock, meminfo->size);
561         printf("Input block is larger than device\n");
562         return -1;
563     }
564 
565     if (!opts->quiet)
566         printf("\n");
567 
568     /* get data from input and write to the device */
569     while (imglen && (mtdoffset < meminfo->size)) {
570 
571         WATCHDOG_RESET ();
572 
573         /*
574          * new eraseblock, check for bad block(s). Stay in the
575          * loop to be sure if the offset changes because of
576          * a bad block, that the next block that will be
577          * written to is also checked. Thus avoiding errors if
578          * the block(s) after the skipped block(s) is also bad
579          * (number of blocks depending on the blockalign
580          */
581         while (blockstart != (mtdoffset & (~meminfo->erasesize+1))) {
582             blockstart = mtdoffset & (~meminfo->erasesize+1);
583             offs = blockstart;
584             baderaseblock = 0;
585 
586             /* check all the blocks in an erase block for
587              * bad blocks */
588             do {
589                 int ret = meminfo->block_isbad(meminfo, offs);
590 
591                 if (ret < 0) {
592                     printf("Bad block check failed\n");
593                     return -1;
594                 }
595                 if (ret == 1) {
596                     baderaseblock = 1;
597                     if (!opts->quiet)
598                         printf("\rBad block at 0x%lx "
599                                "in erase block from "
600                                "0x%x will be skipped\n",
601                                (long) offs,
602                                blockstart);
603                 }
604 
605                 if (baderaseblock) {
606                     mtdoffset = blockstart
607                         + meminfo->erasesize;
608                 }
609                 offs +=  meminfo->erasesize;
610 
611             } while (offs < blockstart + meminfo->erasesize);
612         }
613 
614 
615         /* read page data to memory buffer */
616         result = meminfo->read(meminfo,
617                        mtdoffset,
618                        meminfo->oobblock,
619                        &readlen,
620                        (unsigned char *) &data_buf);
621 
622         if (result != 0) {
623             printf("reading NAND page at offset 0x%lx failed\n",
624                    mtdoffset);
625             return -1;
626         }
627 
628         if (imglen < readlen) {
629             readlen = imglen;
630         }
631 
632         memcpy(buffer, data_buf, readlen);
633         buffer += readlen;
634         imglen -= readlen;
635 
636         if (opts->readoob) {
637             result = meminfo->read_oob(meminfo,
638                            mtdoffset,
639                            meminfo->oobsize,
640                            &readlen,
641                            (unsigned char *)
642                            &oob_buf);
643 
644             if (result != 0) {
645                 printf("\nMTD readoob failure: %d\n",
646                        result);
647                 return -1;
648             }
649 
650 
651             if (imglen < readlen) {
652                 readlen = imglen;
653             }
654 
655             memcpy(buffer, oob_buf, readlen);
656 
657             buffer += readlen;
658             imglen -= readlen;
659         }
660 
661         if (!opts->quiet) {
662             int percent = (int)
663                 ((unsigned long long)
664                  (opts->length-imglen) * 100
665                  / opts->length);
666             /* output progress message only at whole percent
667              * steps to reduce the number of messages printed
668              * on (slow) serial consoles
669              */
670             if (percent != percent_complete) {
671             if (!opts->quiet)
672                 printf("\rReading data from 0x%x "
673                        "-- %3d%% complete.",
674                        mtdoffset, percent);
675                 percent_complete = percent;
676             }
677         }
678 
679         mtdoffset += meminfo->oobblock;
680     }
681 
682     if (!opts->quiet)
683         printf("\n");
684 
685     if (imglen > 0) {
686         printf("Could not read entire image due to bad blocks\n");
687         return -1;
688     }
689 
690     /* return happy */
691     return 0;
692 }
693 
694 /******************************************************************************
695  * Support for locking / unlocking operations of some NAND devices
696  *****************************************************************************/
697 
698 #define NAND_CMD_LOCK       0x2a
699 #define NAND_CMD_LOCK_TIGHT 0x2c
700 #define NAND_CMD_UNLOCK1    0x23
701 #define NAND_CMD_UNLOCK2    0x24
702 #define NAND_CMD_LOCK_STATUS    0x7a
703 
704 /**
705  * nand_lock: Set all pages of NAND flash chip to the LOCK or LOCK-TIGHT
706  *        state
707  *
708  * @param meminfo   nand mtd instance
709  * @param tight     bring device in lock tight mode
710  *
711  * @return      0 on success, -1 in case of error
712  *
713  * The lock / lock-tight command only applies to the whole chip. To get some
714  * parts of the chip lock and others unlocked use the following sequence:
715  *
716  * - Lock all pages of the chip using nand_lock(mtd, 0) (or the lockpre pin)
717  * - Call nand_unlock() once for each consecutive area to be unlocked
718  * - If desired: Bring the chip to the lock-tight state using nand_lock(mtd, 1)
719  *
720  *   If the device is in lock-tight state software can't change the
721  *   current active lock/unlock state of all pages. nand_lock() / nand_unlock()
722  *   calls will fail. It is only posible to leave lock-tight state by
723  *   an hardware signal (low pulse on _WP pin) or by power down.
724  */
725 int nand_lock(nand_info_t *meminfo, int tight)
726 {
727     int ret = 0;
728     int status;
729     struct nand_chip *this = meminfo->priv;
730 
731     /* select the NAND device */
732     this->select_chip(meminfo, 0);
733 
734     this->cmdfunc(meminfo,
735               (tight ? NAND_CMD_LOCK_TIGHT : NAND_CMD_LOCK),
736               -1, -1);
737 
738     /* call wait ready function */
739     status = this->waitfunc(meminfo, this, FL_WRITING);
740 
741     /* see if device thinks it succeeded */
742     if (status & 0x01) {
743         ret = -1;
744     }
745 
746     /* de-select the NAND device */
747     this->select_chip(meminfo, -1);
748     return ret;
749 }
750 
751 /**
752  * nand_get_lock_status: - query current lock state from one page of NAND
753  *             flash
754  *
755  * @param meminfo   nand mtd instance
756  * @param offset    page address to query (muss be page aligned!)
757  *
758  * @return      -1 in case of error
759  *          >0 lock status:
760  *            bitfield with the following combinations:
761  *            NAND_LOCK_STATUS_TIGHT: page in tight state
762  *            NAND_LOCK_STATUS_LOCK:  page locked
763  *            NAND_LOCK_STATUS_UNLOCK: page unlocked
764  *
765  */
766 int nand_get_lock_status(nand_info_t *meminfo, ulong offset)
767 {
768     int ret = 0;
769     int chipnr;
770     int page;
771     struct nand_chip *this = meminfo->priv;
772 
773     /* select the NAND device */
774     chipnr = (int)(offset >> this->chip_shift);
775     this->select_chip(meminfo, chipnr);
776 
777 
778     if ((offset & (meminfo->oobblock - 1)) != 0) {
779         printf ("nand_get_lock_status: "
780             "Start address must be beginning of "
781             "nand page!\n");
782         ret = -1;
783         goto out;
784     }
785 
786     /* check the Lock Status */
787     page = (int)(offset >> this->page_shift);
788     this->cmdfunc(meminfo, NAND_CMD_LOCK_STATUS, -1, page & this->pagemask);
789 
790     ret = this->read_byte(meminfo) & (NAND_LOCK_STATUS_TIGHT
791                       | NAND_LOCK_STATUS_LOCK
792                       | NAND_LOCK_STATUS_UNLOCK);
793 
794  out:
795     /* de-select the NAND device */
796     this->select_chip(meminfo, -1);
797     return ret;
798 }
799 
800 /**
801  * nand_unlock: - Unlock area of NAND pages
802  *        only one consecutive area can be unlocked at one time!
803  *
804  * @param meminfo   nand mtd instance
805  * @param start     start byte address
806  * @param length    number of bytes to unlock (must be a multiple of
807  *          page size nand->oobblock)
808  *
809  * @return      0 on success, -1 in case of error
810  */
811 int nand_unlock(nand_info_t *meminfo, ulong start, ulong length)
812 {
813     int ret = 0;
814     int chipnr;
815     int status;
816     int page;
817     struct nand_chip *this = meminfo->priv;
818     printf ("nand_unlock: start: %08x, length: %d!\n",
819         (int)start, (int)length);
820 
821     /* select the NAND device */
822     chipnr = (int)(start >> this->chip_shift);
823     this->select_chip(meminfo, chipnr);
824 
825     /* check the WP bit */
826     this->cmdfunc(meminfo, NAND_CMD_STATUS, -1, -1);
827     if ((this->read_byte(meminfo) & 0x80) == 0) {
828         printf ("nand_unlock: Device is write protected!\n");
829         ret = -1;
830         goto out;
831     }
832 
833     if ((start & (meminfo->oobblock - 1)) != 0) {
834         printf ("nand_unlock: Start address must be beginning of "
835             "nand page!\n");
836         ret = -1;
837         goto out;
838     }
839 
840     if (length == 0 || (length & (meminfo->oobblock - 1)) != 0) {
841         printf ("nand_unlock: Length must be a multiple of nand page "
842             "size!\n");
843         ret = -1;
844         goto out;
845     }
846 
847     /* submit address of first page to unlock */
848     page = (int)(start >> this->page_shift);
849     this->cmdfunc(meminfo, NAND_CMD_UNLOCK1, -1, page & this->pagemask);
850 
851     /* submit ADDRESS of LAST page to unlock */
852     page += (int)(length >> this->page_shift) - 1;
853     this->cmdfunc(meminfo, NAND_CMD_UNLOCK2, -1, page & this->pagemask);
854 
855     /* call wait ready function */
856     status = this->waitfunc(meminfo, this, FL_WRITING);
857     /* see if device thinks it succeeded */
858     if (status & 0x01) {
859         /* there was an error */
860         ret = -1;
861         goto out;
862     }
863 
864  out:
865     /* de-select the NAND device */
866     this->select_chip(meminfo, -1);
867     return ret;
868 }
869 
870 #endif /* (CONFIG_COMMANDS & CFG_CMD_NAND) && !defined(CFG_NAND_LEGACY) */
