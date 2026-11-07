#include <string.h>

volatile char *stack_probe_sink;

int guarded_copy(const char *source)
{
    char buffer[64];
    strcpy(buffer, source);
    stack_probe_sink = buffer;
    return buffer[0];
}

int main(int argc, char **argv)
{
    return guarded_copy(argc > 1 ? argv[1] : "right");
}
