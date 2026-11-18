// tests/userland/hello.cpp: a C++ program over the glibc 2.35 sysroot:
// iostream, std::string, std::thread, std::map, exceptions and std::stoll
// (linked with -static-libstdc++ so it starts on Ubuntu 22.04).
// Prints "<arch> c++ ok". GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <thread>

int main()
{
    std::map<std::string, long long> m;
    std::thread t([&] { m["x"] = std::stoll("1234567890123"); });
    t.join();
    try {
        throw std::runtime_error("caught");
    } catch (const std::exception &e) {
        if (std::string(e.what()) != "caught")
            return 2;
    }
    if (m["x"] != 1234567890123LL)
        return 3;
    std::cout << ARCH << " c++ ok" << std::endl;
    return 0;
}
