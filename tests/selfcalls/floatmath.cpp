// Calls every float function libstdc++'s math stubs can define
// (math_stubs_float.cc), so a link with g++ takes each stub that is built.
// tests/selfcalls/check.sh then fails if one of them calls itself at its
// start (floorf, ceilf and sqrtf did, open9). Built with -fno-builtin so
// the calls stay calls. MIT. Copyright (c) 2026 AmiCradle Team.
extern "C" {
float fabsf(float); float acosf(float); float asinf(float); float atanf(float);
float atan2f(float, float); float ceilf(float); float cosf(float); float coshf(float);
float expf(float); float floorf(float); float fmodf(float, float); float frexpf(float, int *);
float sqrtf(float); float hypotf(float, float); float ldexpf(float, int); float logf(float);
float log10f(float); float modff(float, float *); float powf(float, float); float sinf(float);
float sinhf(float); float tanf(float); float tanhf(float);
}
volatile float in = 0.25f;
volatile float out;
int main()
{
  float x = in, y; int e;
  out = fabsf(x) + acosf(x) + asinf(x) + atanf(x) + atan2f(x, x) + ceilf(x) + cosf(x)
      + coshf(x) + expf(x) + floorf(x) + fmodf(x, x) + frexpf(x, &e) + sqrtf(x)
      + hypotf(x, x) + ldexpf(x, 1) + logf(x) + log10f(x) + modff(x, &y) + powf(x, x)
      + sinf(x) + sinhf(x) + tanf(x) + tanhf(x);
  return 0;
}
