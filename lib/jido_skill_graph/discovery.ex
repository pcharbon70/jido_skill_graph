defmodule JidoSkillGraph.Discovery do
  @moduledoc """
  Skill file discovery for default scans and manifest-driven subsets.
  """

  alias JidoSkillGraph.Manifest

  @type result :: %{
          root: Path.t(),
          files: [Path.t()],
          manifest: Manifest.t() | nil
        }

  @spec discover(keyword()) :: {:ok, result()} | {:error, term()}
  def discover(opts) when is_list(opts) do
    root = opts |> Keyword.get(:root, ".") |> Path.expand()
    manifest_path = manifest_path(root, Keyword.get(opts, :manifest_path))

    with {:ok, manifest} <- load_manifest(manifest_path),
         {:ok, files} <- discover_files(root, manifest) do
      {:ok, %{root: root, files: files, manifest: manifest}}
    end
  end

  defp manifest_path(root, nil) do
    path = Path.join(root, "graph.yml")
    if File.exists?(path), do: path, else: nil
  end

  defp manifest_path(_root, path), do: Path.expand(path)

  defp load_manifest(nil), do: {:ok, nil}
  defp load_manifest(path), do: Manifest.load(path)

  defp discover_files(root, nil) do
    root
    |> discover_default()
    |> then(&{:ok, &1})
  end

  defp discover_files(root, %Manifest{} = manifest) do
    include_root = manifest.root || root

    files =
      if manifest.includes == [] do
        discover_default(include_root)
      else
        discover_from_includes(include_root, manifest.includes)
      end

    {:ok, files}
  end

  defp discover_default(root) do
    ["**/SKILL.md", "**/skill.md"]
    |> Enum.flat_map(&Path.wildcard(Path.join(root, &1), match_dot: false))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp discover_from_includes(root, includes) do
    includes
    |> Enum.flat_map(&expand_include(root, &1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp expand_include(root, include) do
    absolute =
      if Path.type(include) == :absolute do
        include
      else
        Path.join(root, include)
      end

    cond do
      wildcard?(include) ->
        expand_wildcard(absolute)

      File.dir?(absolute) ->
        discover_default(absolute)

      File.regular?(absolute) and skill_file?(absolute) ->
        [Path.expand(absolute)]

      true ->
        []
    end
  end

  defp expand_wildcard(path) do
    matched = Path.wildcard(path, match_dot: false)

    if Enum.all?(matched, &File.dir?/1) do
      matched |> Enum.flat_map(&discover_default/1)
    else
      matched |> Enum.filter(&skill_file?/1)
    end
  end

  defp wildcard?(value), do: String.contains?(value, ["*", "?", "["])

  defp skill_file?(path) do
    file = Path.basename(path)
    file == "SKILL.md" or file == "skill.md"
  end
end
