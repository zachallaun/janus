defmodule Janus do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  require Ecto.Query

  @type action :: any()
  @type schema :: atom()
  @type actor :: any()

  @doc false
  def authorize(%schema{} = object, action, policy, _opts \\ []) do
    rule = Janus.Policy.rule_for(policy, action, schema)

    false
    |> allow_if_any?(rule.allow, policy, object)
    |> forbid_if_any?(rule.forbid, policy, object)
    |> case do
      true -> {:ok, object}
      false -> :error
    end
  end

  @doc false
  def any_authorized?(schema_or_query, action, policy) do
    {_query, schema} = Janus.Utils.resolve_query_and_schema!(schema_or_query)

    case Janus.Policy.rule_for(policy, action, schema) do
      %{allow: []} -> false
      _ -> true
    end
  end

  @doc false
  def filter_authorized(query_or_schema, action, policy, opts \\ []) do
    Janus.Filter.filter(query_or_schema, action, policy, opts)
  end

  defp allow_if_any?(true, _conditions, _policy, _object), do: true

  defp allow_if_any?(_, conditions, policy, object) do
    Enum.any?(conditions, &condition_match?(&1, policy, object))
  end

  defp forbid_if_any?(false, _conditions, _policy, _object), do: false

  defp forbid_if_any?(_, conditions, policy, object) do
    !Enum.any?(conditions, &condition_match?(&1, policy, object))
  end

  defp condition_match?([], _policy, _object), do: true

  defp condition_match?(condition, policy, object) when is_list(condition) do
    Enum.all?(condition, &condition_match?(&1, policy, object))
  end

  defp condition_match?({:where, clause}, policy, object) do
    clause_match?(clause, policy, object)
  end

  defp condition_match?({:where_not, clause}, policy, object) do
    !clause_match?(clause, policy, object)
  end

  defp clause_match?(list, policy, object) when is_list(list) do
    Enum.all?(list, &clause_match?(&1, policy, object))
  end

  defp clause_match?({:__janus_derived__, action}, policy, object) do
    case authorize(object, action, policy) do
      {:ok, _} -> true
      :error -> false
    end
  end

  defp clause_match?({field, value}, policy, %schema{} = object) do
    if field in schema.__schema__(:associations) do
      clause_match?(value, policy, fetch_associated!(object, field))
    else
      compare_field(object, field, value)
    end
  end

  defp compare_field(object, field, fun) when is_function(fun, 3) do
    fun.(:boolean, object, field)
  end

  defp compare_field(_object, _field, fun) when is_function(fun) do
    raise "permission functions must have arity 3 (#{inspect(fun)})"
  end

  defp compare_field(object, field, value) do
    Map.get(object, field) == value
  end

  defp fetch_associated!(object, field) do
    case Map.fetch!(object, field) do
      %Ecto.Association.NotLoaded{} ->
        raise "field #{inspect(field)} must be pre-loaded on #{inspect(object)}"

      value ->
        value
    end
  end
end
