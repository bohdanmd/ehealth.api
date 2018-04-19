defmodule EHealth.Web.ContractRequestController do
  @moduledoc false

  use EHealth.Web, :controller
  alias EHealth.ContractRequests
  alias EHealth.ContractRequests.ContractRequest

  action_fallback(EHealth.Web.FallbackController)

  def create(conn, params) do
    with {:ok, %ContractRequest{} = contract_request} <- ContractRequests.create(conn.req_headers, params) do
      render(conn, "show.json", contract_request: contract_request)
    end
  end
end
