defmodule EHealth.Contracts do
  @moduledoc false

  @ops_api Application.get_env(:ehealth, :api_resolvers)[:ops]

  def get_by_id(id, %{"contractor_legal_entity_id" => contractor_legal_entity_id} = params) do
    with {:ok, %{"data" => contract}} <- @ops_api.get_contract(id, []),
         true <- contract[""] == contractor_legal_entity_id do
      # check validation
      # preload relations
      {:ok, contract}
    end
  end
end
