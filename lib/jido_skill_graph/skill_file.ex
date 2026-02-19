defmodule JidoSkillGraph.SkillFile do
  @moduledoc """
  Parser for skill markdown files with optional YAML frontmatter.
  """

  @enforce_keys [:path, :body]
  defstruct [:path, :body, :checksum, frontmatter: %{}]

  @type t :: %__MODULE__{
          path: Path.t(),
          body: String.t(),
          checksum: String.t(),
          frontmatter: map()
        }

  @frontmatter_pattern ~r/\A---[ \t]*\r?\n(?<yaml>.*?)\r?\n---[ \t]*\r?\n(?<body>.*)\z/s

  @spec parse(Path.t()) :: {:ok, t()} | {:error, term()}
  def parse(path) when is_binary(path) do
    with {:ok, content} <- File.read(path),
         {:ok, frontmatter, body} <- split_frontmatter(content, path) do
      {:ok,
       %__MODULE__{
         path: path,
         body: body,
         checksum: checksum(content),
         frontmatter: frontmatter
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec split_frontmatter(String.t(), Path.t()) :: {:ok, map(), String.t()} | {:error, term()}
  def split_frontmatter(content, path) when is_binary(content) and is_binary(path) do
    if String.starts_with?(content, "---\n") or String.starts_with?(content, "---\r\n") do
      parse_frontmatter(content, path)
    else
      {:ok, %{}, content}
    end
  end

  defp parse_frontmatter(content, path) do
    case Regex.named_captures(@frontmatter_pattern, content) do
      %{"yaml" => yaml, "body" => body} ->
        case YamlElixir.read_from_string(yaml) do
          {:ok, map} when is_map(map) -> {:ok, map, body}
          {:ok, nil} -> {:ok, %{}, body}
          {:ok, _other} -> {:error, {:invalid_frontmatter, path, :non_map_frontmatter}}
          {:error, reason} -> {:error, {:invalid_frontmatter, path, reason}}
        end

      _ ->
        {:error, {:invalid_frontmatter, path, :missing_closing_delimiter}}
    end
  end

  defp checksum(content) do
    :sha256
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end
end
