Mix.Task.run("app.start")

defmodule SearchBenchmark do
  @moduledoc false

  @default_queries ["alpha", "core", "references", "beta", "a"]
  @default_backend_mode :indexed
  @default_iterations 100
  @default_warmup_iterations 10
  @default_limit 20

  def run(args) do
    opts = parse_args(args)

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

    backend_plan = backend_plan(opts.backend_mode)

    IO.puts("Benchmarking graph_id=#{opts.graph_id} root=#{opts.root}")
    IO.puts("backends=#{backend_labels(backend_plan)}")

    IO.puts(
      "queries=#{Enum.join(opts.queries, ", ")} iterations=#{opts.iterations} warmup=#{opts.warmup_iterations}"
    )

    results =
      backend_plan
      |> Enum.map(fn {backend_key, backend_module} ->
        {backend_key, benchmark_backend(opts, backend_module)}
      end)
      |> Map.new()

    print_results(opts, results)
  end

  defp parse_args(args) do
    args = normalize_args(args)

    {parsed, _, _invalid} =
      OptionParser.parse(args,
        strict: [
          root: :string,
          graph_id: :string,
          backend: :string,
          queries: :string,
          iterations: :integer,
          warmup_iterations: :integer,
          limit: :integer
        ]
      )

    root = parsed |> Keyword.get(:root, "test/fixtures/phase4/basic") |> Path.expand()
    graph_id = Keyword.get(parsed, :graph_id, "benchmark")
    backend_mode = parsed |> Keyword.get(:backend, "indexed") |> normalize_backend_mode()
    iterations = max(1, Keyword.get(parsed, :iterations, @default_iterations))

    warmup_iterations =
      max(0, Keyword.get(parsed, :warmup_iterations, @default_warmup_iterations))

    limit = max(1, Keyword.get(parsed, :limit, @default_limit))

    queries =
      parsed
      |> Keyword.get(:queries, Enum.join(@default_queries, ","))
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    %{
      root: root,
      graph_id: graph_id,
      backend_mode: backend_mode,
      queries: queries,
      iterations: iterations,
      warmup_iterations: warmup_iterations,
      limit: limit,
      graph_name: :"SearchBenchmark.Graph.#{System.unique_integer([:positive])}",
      store_name: :"SearchBenchmark.Store.#{System.unique_integer([:positive])}",
      loader_name: :"SearchBenchmark.Loader.#{System.unique_integer([:positive])}"
    }
  end

  defp normalize_args(["--" | rest]), do: rest
  defp normalize_args(args), do: args

  defp normalize_backend_mode(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "indexed" -> :indexed
      "basic" -> :basic
      "both" -> :both
      other -> unknown_backend_mode(other)
    end
  end

  defp normalize_backend_mode(_value), do: @default_backend_mode

  defp unknown_backend_mode(other) do
    IO.warn("unknown backend mode '#{other}', falling back to #{@default_backend_mode}")
    @default_backend_mode
  end

  defp backend_plan(:indexed), do: [indexed: backend_module(:indexed)]
  defp backend_plan(:basic), do: [basic: backend_module(:basic)]
  defp backend_plan(:both), do: [indexed: backend_module(:indexed), basic: backend_module(:basic)]

  defp backend_module(:indexed), do: JidoSkillGraph.SearchBackend.Indexed
  defp backend_module(:basic), do: JidoSkillGraph.SearchBackend.Basic

  defp backend_labels(plan) do
    plan
    |> Enum.map_join(",", fn {backend_key, _backend_module} -> Atom.to_string(backend_key) end)
  end

  defp benchmark_backend(opts, backend_module) do
    query_samples =
      Enum.into(opts.queries, %{}, fn query ->
        warmup_query(opts, query, backend_module)
        {query, run_samples(opts, query, backend_module)}
      end)

    query_stats =
      Enum.into(query_samples, %{}, fn {query, samples} ->
        {query, summarize_samples(samples)}
      end)

    overall_samples =
      query_samples
      |> Map.values()
      |> List.flatten()

    %{
      query_stats: query_stats,
      overall: summarize_samples(overall_samples)
    }
  end

  defp warmup_query(%{warmup_iterations: 0}, _query, _backend_module), do: :ok

  defp warmup_query(opts, query, backend_module) do
    Enum.each(1..opts.warmup_iterations, fn _ ->
      _ = run_query(opts, query, backend_module)
    end)
  end

  defp run_samples(opts, query, backend_module) do
    Enum.map(1..opts.iterations, fn _ ->
      run_query(opts, query, backend_module)
    end)
  end

  defp run_query(opts, query, backend_module) do
    {duration_micros, result} =
      :timer.tc(fn ->
        JidoSkillGraph.search(opts.graph_id, query,
          store: opts.store_name,
          search_backend: backend_module,
          limit: opts.limit
        )
      end)

    case result do
      {:ok, _results} -> duration_micros
      {:error, reason} -> raise "search benchmark query failed: #{inspect(reason)}"
      other -> raise "search benchmark query returned unexpected response: #{inspect(other)}"
    end
  end

  defp summarize_samples(samples) when is_list(samples) and samples != [] do
    avg_ms = samples |> Enum.sum() |> Kernel./(length(samples)) |> Kernel./(1_000)
    p50_ms = percentile(samples, 50) / 1_000
    p95_ms = percentile(samples, 95) / 1_000
    min_ms = Enum.min(samples) / 1_000
    max_ms = Enum.max(samples) / 1_000

    %{
      avg_ms: avg_ms,
      p50_ms: p50_ms,
      p95_ms: p95_ms,
      min_ms: min_ms,
      max_ms: max_ms
    }
  end

  defp print_results(opts, %{indexed: indexed_stats, basic: basic_stats}) do
    print_backend_stats("indexed", indexed_stats, opts.queries)
    print_backend_stats("basic", basic_stats, opts.queries)
    print_comparison(indexed_stats, basic_stats, opts.queries)
  end

  defp print_results(opts, %{indexed: indexed_stats}) do
    print_backend_stats("indexed", indexed_stats, opts.queries)
  end

  defp print_results(opts, %{basic: basic_stats}) do
    print_backend_stats("basic", basic_stats, opts.queries)
  end

  defp print_backend_stats(label, stats, queries) do
    IO.puts("\nbackend=#{label}")

    Enum.each(queries, fn query ->
      query_stats = Map.fetch!(stats.query_stats, query)
      IO.puts("query=#{inspect(query)} #{format_stats(query_stats)}")
    end)

    IO.puts("overall #{format_stats(stats.overall)}")
  end

  defp print_comparison(indexed_stats, basic_stats, queries) do
    IO.puts("\ncomparison=basic/indexed speedup")

    Enum.each(queries, fn query ->
      indexed_query_stats = Map.fetch!(indexed_stats.query_stats, query)
      basic_query_stats = Map.fetch!(basic_stats.query_stats, query)

      IO.puts(
        "query=#{inspect(query)} speedup_p50=#{speedup_ratio(basic_query_stats.p50_ms, indexed_query_stats.p50_ms)} speedup_p95=#{speedup_ratio(basic_query_stats.p95_ms, indexed_query_stats.p95_ms)}"
      )
    end)

    IO.puts(
      "overall speedup_p50=#{speedup_ratio(basic_stats.overall.p50_ms, indexed_stats.overall.p50_ms)} speedup_p95=#{speedup_ratio(basic_stats.overall.p95_ms, indexed_stats.overall.p95_ms)}"
    )
  end

  defp format_stats(stats) do
    "avg_ms=#{round_ms(stats.avg_ms)} p50_ms=#{round_ms(stats.p50_ms)} p95_ms=#{round_ms(stats.p95_ms)} min_ms=#{round_ms(stats.min_ms)} max_ms=#{round_ms(stats.max_ms)}"
  end

  defp speedup_ratio(numerator_ms, denominator_ms) when denominator_ms > 0.0 do
    "#{Float.round(numerator_ms / denominator_ms, 3)}x"
  end

  defp speedup_ratio(_numerator_ms, _denominator_ms), do: "n/a"

  defp round_ms(value), do: Float.round(value, 3)

  defp percentile(samples, p) when is_list(samples) and samples != [] and is_integer(p) do
    sorted = Enum.sort(samples)
    rank = ceil(length(sorted) * (p / 100))
    Enum.at(sorted, max(rank - 1, 0))
  end
end

SearchBenchmark.run(System.argv())
