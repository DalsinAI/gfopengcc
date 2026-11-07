/* -fstack-protector-explicit must link the same target runtime. */
volatile char *explicit_sink;

__attribute__((noinline, stack_protect))
static void
explicit_guard (void)
{
  char buffer[16];
  buffer[0] = 1;
  explicit_sink = buffer;
}

int
main (void)
{
  explicit_guard ();
  return 0;
}
