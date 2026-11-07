// cxx_eh_threads.cpp: C++ exceptions (unwinding through frames with
// destructors, class types, library exceptions, exception_ptr across
// threads) and std::thread/mutex/condition_variable/thread_local on libpthread.
// Prints "cxx_eh_threads OK" (rc 0) or "cxx_eh_threads FAILED" (rc 10).
// MIT licence, Copyright (c) 2026 AmiCradle Team.
#include <atomic>
#include <condition_variable>
#include <cstdio>
#include <exception>
#include <functional>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

static int destroyed;
struct Guard { ~Guard() { ++destroyed; } };
struct Custom { int value; };

static void dive(int depth)
{
  Guard guard;
  if (depth == 0)
    throw std::runtime_error("deep");
  dive(depth - 1);
}

static thread_local int local_count;

int main()
{
  bool ok = true;

  try { dive(10); ok = false; }
  catch (const std::exception &error) { ok &= std::string(error.what()) == "deep"; }
  ok &= destroyed == 11;

  std::function<int(int)> twice = [](int v) { return v * 2; };
  ok &= twice(21) == 42;

  try { throw Custom{7}; }
  catch (const Custom &custom) { ok &= custom.value == 7; }

  try { std::vector<int> v(3); (void) v.at(5); ok = false; }
  catch (const std::out_of_range &) {}

  std::mutex lock;
  std::condition_variable ready;
  long total = 0;
  int finished = 0;
  std::atomic<int> caught{0};
  std::vector<std::thread> threads;
  for (int t = 1; t <= 4; t++)
    threads.emplace_back([&, t] {
      for (int i = 0; i < 1000; i++)
        {
          ++local_count;
          std::lock_guard<std::mutex> hold(lock);
          total += t;
        }
      try { throw std::runtime_error("in a thread"); }
      catch (const std::runtime_error &) { ++caught; }
      std::lock_guard<std::mutex> hold(lock);
      if (local_count == 1000)
        ++finished;
      ready.notify_one();
    });
  {
    std::unique_lock<std::mutex> wait(lock);
    ready.wait(wait, [&] { return finished == 4; });
  }
  for (auto &thread : threads)
    thread.join();
  ok &= total == 10000 && caught == 4 && finished == 4 && local_count == 0;

  std::exception_ptr carried;
  std::thread thrower([&] {
    try { throw std::logic_error("carried"); }
    catch (...) { carried = std::current_exception(); }
  });
  thrower.join();
  try { if (carried) std::rethrow_exception(carried); ok = false; }
  catch (const std::logic_error &error) { ok &= std::string(error.what()) == "carried"; }

  std::printf("cxx_eh_threads %s (destructors %d, total %ld, thread catches %d)\n",
              ok ? "OK" : "FAILED", destroyed, total, caught.load());
  return ok ? 0 : 10;
}
