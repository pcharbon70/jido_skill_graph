Mix.Task.run("app.start")

defmodule SearchBenchmark do
  @moduledoc false

  @default_queries ["alpha", "core", "references", "beta", "a"]

  def run(args) do
    opts = parse_args(args)
    backend = backend_module(opts.backend)

    {:ok, _pid} =
      JidoSkillGraph.start_link(
        name: opts.graph_name,
        store: [name: opts.store_name],
        loader: [
          name: opts.loader_name,
          load_on_start: false,
          builder_opts: [root: opts.root, graph_id: opts.graph_id]
        ]
      )

    :ok = JidoSkillGraph.reload(opts.loader_name)

    IO.puts("Benchmarking backend=#{inspect(backend)} graph_id=#{opts.graph_id}")
    IO.puts("queries=#{Enum.join(opts.queries, ", ")} iterations=#{opts.iterations}")

    Enum.each(opts.queries, fn query ->
      micros =
        Enum.map(1..opts.iterations, fn _ ->
          {duration, {:ok, _results}} =
            :timer.tc(fn ->
              JidoSkillGraph.search(opts.graph_id, query,
                store: opts.store_name,
                search_backend: backend,
                limit: opts.limit
              )
            end)

          duration
        end)

      avg_ms = micros |> Enum.sum() |> Kernel./(length(micros)) |> Kernel./(1_000)
      p95_ms = percentile(micros, 95) / 1_000
      IO.puts("query=#{inspect(query)} avg_ms=#{Float.round(avg_ms, 3)} p95_ms=#{Float.round(p95_ms, 3)}")
    end)
  end

  defp parse_args(args) do
    {parsed, _, _invalid} =
      OptionParser.parse(args,
        strict: [
          root: :string,
          graph_id: :string,
          backend: :string,
          queries: :string,
          iterations: :integer,
          limit: :integer
        ]
      )

    root = parsed |> Keyword.get(:root, "test/fixtures/phase4/basic") |> Path.expand()
    graph_id = Keyword.get(parsed, :graph_id, "benchmark")
    backend = Keyword.get(parsed, :backend, "basic")
    iterations = max(1, Keyword.get(parsed, :iterations, 100))
    limit = max(1, Keyword.get(parsed, :limit, 20))

    queries =
      parsed
      |> Keyword.get(:queries, Enum.join(@default_queries, ","))
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    %{
      root: root,
      graph_id: graph_id,
      backend: backend,
      queries: queries,
      iterations: iterations,
      limit: limit,
      graph_name: :"SearchBenchmark.Graph.#{System.unique_integer([:positive])}",
      store_name: :"SearchBenchmark.Store.#{System.unique_integer([:positive])}",
      loader_name: :"SearchBenchmark.Loader.#{System.unique_integer([:positive])}"
    }
  end

  defp backend_module("indexed"), do: JidoSkillGraph.SearchBackend.Indexed
  defp backend_module(_other), do: JidoSkillGraph.SearchBackend.Basic

  defp percentile(samples, p) when is_list(samples) and samples != [] and is_integer(p) do
    sorted = Enum.sort(samples)
    rank = ceil(length(sorted) * (p / 100))
    Enum.at(sorted, max(rank - 1, 0))
  end
end

SearchBenchmark.run(System.argv())
