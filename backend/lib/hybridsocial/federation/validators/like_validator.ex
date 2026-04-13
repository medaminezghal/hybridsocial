defmodule Hybridsocial.Federation.Validators.LikeValidator do
  @moduledoc "Validates Like and EmojiReact activities (both share the Like shape)."

  alias Hybridsocial.Federation.Validators.CommonValidator

  def validate(%{"type" => type, "object" => object} = activity)
      when type in ["Like", "EmojiReact"] and is_binary(object) do
    with :ok <- CommonValidator.validate(activity) do
      {:ok, activity}
    end
  end

  def validate(%{"type" => type}) when type in ["Like", "EmojiReact"],
    do: {:error, "#{type} must have an object URI"}

  def validate(_), do: {:error, "Not a Like or EmojiReact activity"}
end
