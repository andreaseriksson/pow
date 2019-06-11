defmodule Pow.Store.Backend.MnesiaCacheTest do
  use ExUnit.Case
  doctest Pow.Store.Backend.MnesiaCache

  alias Pow.{Config, Config.ConfigError, Store.Backend.MnesiaCache}

  @default_config [namespace: "pow:test", ttl: :timer.hours(1)]

  setup do
    pid    = self()
    events = [
      [:pow, MnesiaCache, :cache],
      [:pow, MnesiaCache, :delete],
      [:pow, MnesiaCache, :invalidate]
    ]

    :telemetry.attach_many("event-handler-#{inspect pid}", events, fn event, measurements, metadata, send_to: pid ->
      send(pid, {:event, event, measurements, metadata})
    end, send_to: pid)

    :mnesia.kill()

    File.rm_rf!("tmp/mnesia")
    File.mkdir_p!("tmp/mnesia")

    {:ok, pid} = MnesiaCache.start_link([])

    {:ok, pid: pid}
  end

  test "can put, get and delete records with persistent storage", %{pid: pid} do
    assert MnesiaCache.get(@default_config, "key") == :not_found

    MnesiaCache.put(@default_config, "key", "value")
    assert_receive {:event, [:pow, MnesiaCache, :cache], _measurements, %{key: "key", value: "value"}}
    assert MnesiaCache.get(@default_config, "key") == "value"

    restart(pid, @default_config)

    assert MnesiaCache.get(@default_config, "key") == "value"

    MnesiaCache.delete(@default_config, "key")
    assert_receive {:event, [:pow, MnesiaCache, :delete], _measurements, %{key: "key"}}
    assert MnesiaCache.get(@default_config, "key") == :not_found
  end

  test "with no `:ttl` opt" do
    assert_raise ConfigError, "`:ttl` configuration option is required for Pow.Store.Backend.MnesiaCache", fn ->
      MnesiaCache.put([namespace: "pow:test"], "key", "value")
    end
  end

  test "fetch keys" do
    MnesiaCache.put(@default_config, "key1", "value")
    MnesiaCache.put(@default_config, "key2", "value")
    :timer.sleep(100)

    assert MnesiaCache.keys(@default_config) == ["key1", "key2"]
  end

  test "records auto purge with persistent storage", %{pid: pid} do
    config = Config.put(@default_config, :ttl, 100)

    MnesiaCache.put(config, "key", "value")
    :timer.sleep(50)
    assert MnesiaCache.get(config, "key") == "value"
    assert_receive {:event, [:pow, MnesiaCache, :invalidate], _measurements, %{key: "key"}}
    assert MnesiaCache.get(config, "key") == :not_found

    MnesiaCache.put(config, "key", "value")
    restart(pid, config)
    assert MnesiaCache.get(config, "key") == "value"
    assert_receive {:event, [:pow, MnesiaCache, :invalidate], _measurements, %{key: "key"}}
    assert MnesiaCache.get(config, "key") == :not_found
  end

  defp restart(pid, config) do
    GenServer.stop(pid)
    :mnesia.stop()
    MnesiaCache.start_link(config)
  end
end
