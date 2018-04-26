defmodule EHealth.Web.ContractController do
  @moduledoc false

  use EHealth.Web, :controller

  alias EHealth.Contracts

  action_fallback(EHealth.Web.FallbackController)

  def show(conn, %{"id" => id} = params) do
    with {:ok, contract} <- Contracts.get_by_id(id, params) do
      render(conn, "show.json", contract: contract)
    end
  end
end
