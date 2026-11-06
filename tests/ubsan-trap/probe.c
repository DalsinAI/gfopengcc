/* Deliberate UB is confined to separately built negative test cases.
   GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team. */
#ifndef TEST_CASE
#define TEST_CASE 0
#endif

volatile int trap_sink;
volatile int overflow_operand = 0x7fffffff;
volatile unsigned int shift_count = 32;
volatile int divisor = 0;
volatile unsigned int array_index = 4;
volatile int *null_pointer;

int main(void)
{
    int values[4] = { 10, 20, 30, 40 };
#if TEST_CASE == 1
    trap_sink = overflow_operand + 1;
#elif TEST_CASE == 2
    trap_sink = 1U << shift_count;
#elif TEST_CASE == 3
    trap_sink = 42 / divisor;
#elif TEST_CASE == 4
    trap_sink = values[array_index];
#elif TEST_CASE == 5
    trap_sink = *null_pointer;
#else
    /* Use the same constructs with defined inputs. */
    int x = overflow_operand - 1;
    unsigned int count = shift_count - 31;
    int denominator = divisor + 2;
    unsigned int index = array_index - 1;
    trap_sink = (x & 1) + (int)(1U << count) + 42 / denominator
                + values[index];
    return trap_sink != 63;
#endif
    /* Reaching this return in a negative case means instrumentation failed. */
    return 0;
}
