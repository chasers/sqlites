defmodule Smolsqls.SignupLimiterTest do
  use ExUnit.Case, async: false

  alias Smolsqls.SignupLimiter

  setup do
    SignupLimiter.reset()
    :ok
  end

  test "check only counts recorded signups, not peeks" do
    ip = "203.0.113.1"

    for _ <- 1..10, do: assert(SignupLimiter.check(ip) == :ok)
    assert SignupLimiter.check(ip) == :ok
  end

  test "denies after max recorded signups in the window" do
    ip = "203.0.113.2"

    for _ <- 1..5 do
      assert SignupLimiter.check(ip) == :ok
      SignupLimiter.record(ip)
    end

    assert SignupLimiter.check(ip) == {:error, :signup_rate_limited}
  end

  test "counts each ip independently" do
    for _ <- 1..5, do: SignupLimiter.record("203.0.113.3")

    assert SignupLimiter.check("203.0.113.3") == {:error, :signup_rate_limited}
    assert SignupLimiter.check("198.51.100.4") == :ok
  end

  test "reset clears counters" do
    for _ <- 1..5, do: SignupLimiter.record("203.0.113.5")
    assert SignupLimiter.check("203.0.113.5") == {:error, :signup_rate_limited}

    SignupLimiter.reset()
    assert SignupLimiter.check("203.0.113.5") == :ok
  end
end
