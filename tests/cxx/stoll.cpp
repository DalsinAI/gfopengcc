// std::stoll, std::stoull, std::stold and <cstdlib>'s C99 calls, which
// libstdc++ gives only with _GLIBCXX_USE_C99_STDLIB
// (scripts/libstdcxx-c99-stdlib.sh). Returns 0 when every value is right.
// MIT. Copyright (c) 2026 AmiCradle Team.
#include <cstdlib>
#include <stdexcept>
#include <string>

static int bad;
#define CHECK(c) do { if (!(c)) ++bad; } while (0)

int main()
{
    std::size_t n = 0;
    CHECK(std::stoll("  -9000000000x", &n) == -9000000000LL && n == 13);
    CHECK(std::stoll("7fffffffffffffff", nullptr, 16) == 0x7fffffffffffffffLL);
    CHECK(std::stoull("18446744073709551615") == 18446744073709551615ULL);
    CHECK(std::stoll(std::string("0x10"), nullptr, 0) == 16);
    long double ld = std::stold("2.5e3", &n);
    CHECK(ld == 2500.0L && n == 5);
    CHECK(std::stof("0.5") == 0.5f);
    CHECK(std::llabs(-5LL) == 5LL);
    std::lldiv_t q = std::lldiv(7LL, 2LL);
    CHECK(q.quot == 3 && q.rem == 1);
    CHECK(std::atoll("123") == 123LL);
    try { (void)std::stoll("x"); ++bad; } catch (const std::invalid_argument &) {}
    try { (void)std::stoll("99999999999999999999"); ++bad; } catch (const std::out_of_range &) {}
    return bad;
}
