defmodule ExCoveralls.Local do
  @moduledoc """
  Locally displays the result to screen.
  """

  defmodule Count do
    @moduledoc """
    Stores count information for calculating coverage values.
    """

    defstruct lines: 0, relevant: 0, covered: 0
  end

  @doc """
  Provides an entry point for the module.
  """
  def execute(stats, options \\ []) do
    print_summary(stats, options)

    if options[:detail] == true do
      source(stats, options[:filter]) |> IO.puts
    end

    ExCoveralls.Stats.ensure_minimum_coverage(stats)
  end

  @doc """
  Format the source code with color for the files that matches with
  the specified patterns.
  """
  def source(stats, _patterns = nil), do: source(stats)
  def source(stats, _patterns = []),  do: source(stats)
  def source(stats, patterns) do
    Enum.filter(stats, fn(stat) -> String.contains?(stat[:name], patterns) end) |> source
  end

  def source(stats) do
    stats |> Enum.map(&format_source/1)
          |> Enum.join("\n")
  end

  @doc """
  Prints summary statistics for given coverage.
  """
  def print_summary(stats, options \\ []) do
    enabled = ExCoveralls.Settings.get_print_summary
    if enabled and not ExCoveralls.ConfServer.summary_printed?() do
      coverage(stats, options) |> IO.puts()
      warnings(stats) |> IO.write()
      ExCoveralls.ConfServer.summary_printed()
    end
  end

  defp format_source(stat) do
    "\n\e[33m--------#{stat[:name]}--------\e[m\n" <> colorize(stat)
  end

  defp colorize(%{name: _name, source: source, coverage: coverage}) do
    lines = String.split(source, "\n")
    Enum.zip(lines, coverage)
    |> Enum.map(&do_colorize/1)
    |> Enum.join("\n")
  end

  defp do_colorize({line, coverage}) do
    case coverage do
      nil -> line
      0   -> "\e[31m#{line}\e[m"
      _   -> "\e[32m#{line}\e[m"
    end
  end

  @doc """
  Format the source coverage stats into string.
  """
  def coverage(stats, options \\ []) do
    file_width = ExCoveralls.Settings.get_file_col_width
    print_files? = ExCoveralls.Settings.get_print_files

    count_info = Enum.map(stats, fn(stat) -> [stat, calculate_count(stat[:coverage])] end)
    count_info = sort(count_info, options)

    if print_files? do
      """
      ----------------
      #{print_string("~-6s ~-#{file_width}s ~8s ~8s ~8s", ["COV", "FILE", "LINES", "RELEVANT", "MISSED"])}
      #{Enum.join(format_body(count_info), "\n")}
      #{format_total(count_info)}
      ----------------\
      #{format_uncovered(count_info)}\
      """
    else
      "Test Coverage #{format_total(count_info)}\n"
    end
  end

  def warnings(stats) do
    for stat <- stats, {line_num, message} <- stat[:warnings], into: "" do
      print_string("\e[33mwarning:\e[m ~s\n  ~s:~b\n", [message, stat[:name], line_num + 1])
    end
  end

  defp sort(count_info, options) do
    if options[:sort] do
      sort_order = parse_sort_options(options)

      flattened =
        Enum.map(count_info, fn original ->
          [stat, count] = original
          %{
            "cov" => ExCoveralls.Stats.get_coverage(count.relevant, count.covered),
            "file" => stat[:name],
            "lines" => count.lines,
            "relevant" => count.relevant,
            "missed" => count.relevant - count.covered,
            :_original => original
          }
        end)

      sorted =
        Enum.reduce(sort_order, flattened, fn {key, comparator}, acc ->
          Enum.sort(acc, fn(x, y) ->
            args = [x[key], y[key]]
            apply(Kernel, comparator, args)
          end)
        end)

      Enum.map(sorted, fn flattened -> flattened[:_original] end)
    else
      Enum.sort(count_info, fn([x, _], [y, _]) -> x[:name] <= y[:name] end)
    end
  end

  defp parse_sort_options(options) do
    sort_order =
      options[:sort]
      |> String.split(",")
      |> Enum.reverse()

    Enum.map(sort_order, fn sort_chunk ->
      case String.split(sort_chunk, ":") do
        [key, "asc"] -> {key, :<=}
        [key, "desc"] -> {key, :>=}
        [key] -> {key, :>=}
      end
    end)
  end

  defp format_body(info) do
    Enum.map(info, &format_info/1)
  end

  defp format_info([stat, count]) do
    coverage = ExCoveralls.Stats.get_coverage(count.relevant, count.covered)
    file_width = ExCoveralls.Settings.get_file_col_width
    print_string("~5w% ~-#{file_width}s ~8w ~8w ~8w",
      [coverage, stat[:name], count.lines, count.relevant, count.relevant - count.covered])
  end

  defp format_total(info) do
    totals   = Enum.reduce(info, %Count{}, fn([_, count], acc) -> append(count, acc) end)
    coverage = ExCoveralls.Stats.get_coverage(totals.relevant, totals.covered)
    print_string("[TOTAL] ~5w%", [coverage])
  end

  defp format_uncovered(info) do
    coverage_options = ExCoveralls.Settings.get_coverage_options
    report_uncovered = coverage_options["report_uncovered"]

    if report_uncovered do
      info
      |> filter_uncovered()
      |> format_uncovered_body()
      |> case do
        [] -> ""
        list ->
          "\n#{IO.ANSI.yellow}UNCOVERED FILES\n#{Enum.join(list, "\n")}#{IO.ANSI.reset}\n"
      end
    end
  end

  defp format_uncovered_body(info) do
    Enum.map(info, &format_uncovered_info/1)
  end

  defp format_uncovered_info([stat, count]) do
    coverage = ExCoveralls.Stats.get_coverage(count.relevant, count.covered)
    file_width = ExCoveralls.Settings.get_file_col_width
    uncovered_line_numbers = format_uncovered_line_numbers(stat)

    print_string("~5.1f% ~-#{file_width}s ~s",
      [coverage, stat[:name], uncovered_line_numbers])
  end

  defp format_uncovered_line_numbers(%{source: source, coverage: coverage}) do
    lines = source |> String.split("\n") |> Enum.with_index(1)

    Enum.zip(lines, coverage)
    |> Enum.filter(&filter_uncovered_lines/1)
    |> Enum.map(&format_uncovered_line/1)
    |> Enum.join(", ")
  end

  defp filter_uncovered_lines({_line, coverage}), do: coverage == 0

  defp format_uncovered_line({{_line, index}, _coverage}), do: "L#{index}"

  defp filter_uncovered(info) do
    Enum.filter(info, fn [_stat, count] ->
      ExCoveralls.Stats.get_coverage(count.relevant, count.covered) < 100
    end)
  end

  defp append(a, b) do
    %Count{
      lines: a.lines + b.lines,
      relevant: a.relevant + b.relevant,
      covered: a.covered  + b.covered
    }
  end

  @doc """
  Calculate count information from the coverage stats.
  """
  def calculate_count(coverage) do
    do_calculate_count(coverage, 0, 0, 0)
  end

  defp do_calculate_count([], lines, relevant, covered) do
    %Count{lines: lines, relevant: relevant, covered: covered}
  end

  defp do_calculate_count([h|t], lines, relevant, covered) do
    case h do
      nil -> do_calculate_count(t, lines + 1, relevant, covered)
      0   -> do_calculate_count(t, lines + 1, relevant + 1, covered)
      n when is_number(n)
          -> do_calculate_count(t, lines + 1, relevant + 1, covered + 1)
      _   -> raise "Invalid data - #{h}"
    end
  end

  defp print_string(format, params) do
    char_list = :io_lib.format(format, params)
    List.to_string(char_list)
  end
end
