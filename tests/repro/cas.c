/* -mcas reproducer (patches/gcc/0015): with -mcas a 68020 to 68040 build
   does its 1-, 2- and 4-byte atomics with CAS inline instead of calling
   libatomic (whose AmigaOS build takes Forbid()/Permit() for each one).
   Run here, the operations give the right values; prove.sh also checks the
   code holds cas and no __atomic_ call for these sizes. */
extern void puts_(const char *); extern void puti(long);
unsigned int w = 5; unsigned short h = 7; unsigned char b = 1;
__attribute__((noinline)) unsigned int add4(unsigned int *p, unsigned int v) { return __atomic_fetch_add(p, v, __ATOMIC_SEQ_CST); }
__attribute__((noinline)) unsigned int sub4(unsigned int *p, unsigned int v) { return __atomic_sub_fetch(p, v, __ATOMIC_SEQ_CST); }
__attribute__((noinline)) unsigned int or4(unsigned int *p, unsigned int v) { return __atomic_fetch_or(p, v, __ATOMIC_SEQ_CST); }
__attribute__((noinline)) unsigned int and4(unsigned int *p, unsigned int v) { return __atomic_and_fetch(p, v, __ATOMIC_SEQ_CST); }
__attribute__((noinline)) unsigned int xchg4(unsigned int *p, unsigned int v) { return __atomic_exchange_n(p, v, __ATOMIC_SEQ_CST); }
__attribute__((noinline)) int cx4(unsigned int *p, unsigned int e, unsigned int d) { return __atomic_compare_exchange_n(p, &e, d, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); }
__attribute__((noinline)) int cx2(unsigned short *p, unsigned short e, unsigned short d) { return __atomic_compare_exchange_n(p, &e, d, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); }
__attribute__((noinline)) unsigned short add2(unsigned short *p, unsigned short v) { return __atomic_add_fetch(p, v, __ATOMIC_SEQ_CST); }
__attribute__((noinline)) int cx1(unsigned char *p, unsigned char e, unsigned char d) { return __atomic_compare_exchange_n(p, &e, d, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); }
__attribute__((noinline)) unsigned char xor1(unsigned char *p, unsigned char v) { return __atomic_fetch_xor(p, v, __ATOMIC_SEQ_CST); }
int main(void) {
  int bad = 0;
  if (add4(&w, 3) != 5 || w != 8) bad++;
  if (sub4(&w, 10) != 0xfffffffeu || w != 0xfffffffeu) bad++;
  if (or4(&w, 1) != 0xfffffffeu || w != 0xffffffffu) bad++;
  if (and4(&w, 0x00ff00ffu) != 0x00ff00ffu) bad++;
  if (xchg4(&w, 42) != 0x00ff00ffu || w != 42) bad++;
  if (!cx4(&w, 42, 43) || w != 43 || cx4(&w, 42, 44) || w != 43) bad++;
  if (!cx2(&h, 7, 9) || h != 9 || cx2(&h, 7, 1) || h != 9) bad++;
  if (add2(&h, 0xfff8) != 1 || h != 1) bad++;
  if (!cx1(&b, 1, 0) || b != 0 || cx1(&b, 1, 2) || b != 0) bad++;
  if (xor1(&b, 0x81) != 0 || b != 0x81) bad++;
  puts_(bad ? "cas: WRONG (" : "cas: right (");
  puti(bad); puts_(" bad)\n");
  return bad != 0;
}
