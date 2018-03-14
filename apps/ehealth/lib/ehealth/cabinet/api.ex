defmodule EHealth.Cabinet.API do
  @moduledoc false
  import Ecto.{Query, Changeset}, warn: false

  alias EHealth.Guardian
  alias EHealth.Bamboo.Emails.Sender
  alias EHealth.Validators.JsonSchema
  alias EHealth.Cabinet.RegistrationRequest
  alias EHealth.Man.Templates.EmailVerification

  require Logger

  @mpi_api Application.get_env(:ehealth, :api_resolvers)[:mpi]
  @mithril_api Application.get_env(:ehealth, :api_resolvers)[:mithril]
  @signature_api Application.get_env(:ehealth, :api_resolvers)[:digital_signature]

  def create_patient(jwt, params, headers) do
    with {:ok, %{"email" => email}} <- Guardian.decode_and_verify(jwt),
         %Ecto.Changeset{valid?: true} <- validate_params(:patient, params),
         {:ok, %{"data" => %{"content" => content, "signer" => signer}}} <-
           @signature_api.decode_and_validate(params["signed_person_data"], params["signed_content_encoding"], headers),
         {:ok, tax_id} <- validate_tax_id(content, signer),
         :ok <- JsonSchema.validate(:person, content),
         :ok <- verify_otp(params["otp"]),
         {:ok, %{"data" => mpi_person}} <-
           @mpi_api.search(%{"tax_id" => tax_id, "birth_date" => content["birth_date"]}, headers),
         {:ok, %{"data" => person}} <- create_or_update_person(mpi_person, content, headers),
         {:ok, %{"data" => mithril_user}} <- @mithril_api.search_user(%{"email" => email}, headers),
         :ok <- check_user_by_tax_id(mithril_user),
         user_params <- prepare_user_params(tax_id, email, params),
         {:ok, %{"data" => user}} <- create_or_update_user(mithril_user, user_params, headers) do
      {:ok, %{user: user, patient: person}}
    end
  end

  defp validate_tax_id(%{"tax_id" => tax_id}, %{"edrpou" => edrpou}) when edrpou == tax_id, do: {:ok, tax_id}
  defp validate_tax_id(_, _), do: {:error, {:conflict, "Registration person and person that sign should be the same"}}

  defp verify_otp(otp) do
    # ToDo: write code
    :ok
  end

  defp create_or_update_person([], params, headers), do: @mpi_api.create_or_update_person(params, headers)
  defp create_or_update_person(persons, params, headers), do: @mpi_api.update_person(hd(persons)["id"], params, headers)

  defp prepare_user_params(tax_id, email, params) do
    %{
      "email" => email,
      "tax_id" => tax_id,
      "password" => params["password"]
    }
  end

  defp create_or_update_user([%{"id" => id}], params, headers), do: @mithril_api.change_user(id, params, headers)
  defp create_or_update_user([], params, headers), do: @mithril_api.create_user(params, headers)

  defp check_user_by_tax_id([%{"tax_id" => tax_id}]) when is_binary(tax_id) and byte_size(tax_id) > 0 do
    {:error, {:conflict, "User with this tax_id already exists"}}
  end

  defp check_user_by_tax_id(_), do: :ok

  def validate_email_jwt(jwt) do
    with {:ok, %{"email" => email}} <- Guardian.decode_and_verify(jwt),
         ttl <- Confex.fetch_env!(:ehealth, __MODULE__)[:jwt_ttl_registration],
         {:ok, jwt, _claims} <- generate_jwt(email, {ttl, :hours}) do
      {:ok, jwt}
    else
      _ -> {:error, {:access_denied, "invalid JWT"}}
    end
  end

  def send_email_verification(params) do
    with %Ecto.Changeset{valid?: true, changes: %{email: email}} <- validate_params(:email, params),
         true <- email_available_for_registration?(email),
         false <- email_sent?(email),
         ttl <- Confex.fetch_env!(:ehealth, __MODULE__)[:jwt_ttl_email],
         {:ok, jwt, _claims} <- generate_jwt(email, {ttl, :hours}),
         {:ok, template} <- EmailVerification.render(jwt) do
      email_config = Confex.fetch_env!(:ehealth, EmailVerification)
      send_email(email, template, email_config)
    end
  end

  defp validate_params(:email, params) do
    {%{}, %{email: :string}}
    |> cast(params, [:email])
    |> validate_format(:email, ~r/^[a-zA-Z0-9.!#$%&’*+\/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$/)
  end

  defp validate_params(:patient, params) do
    fields = RegistrationRequest.__schema__(:fields)

    %RegistrationRequest{}
    |> cast(params, fields)
    |> validate_required(fields)
    |> validate_inclusion(:signed_content_encoding, ["base64"])
  end

  def email_available_for_registration?(email) do
    case @mithril_api.search_user(%{email: email}) do
      {:ok, %{"data" => [%{"tax_id" => tax_id}]}} when is_binary(tax_id) and byte_size(tax_id) > 0 ->
        {:error, {:conflict, "User with this email already exists"}}

      {:ok, _} ->
        true

      _ ->
        {:error, {:service_unavailable, "Cannot fetch user"}}
    end
  end

  defp email_sent?(_email) do
    # ToDo: check sent email?
    false
  end

  defp generate_jwt(email, ttl) do
    Guardian.encode_and_sign(:email, %{email: email}, token_type: "access", ttl: ttl)
  end

  def send_email(email, body, email_config) do
    Sender.send_email(email, body, email_config[:from], email_config[:subject])
    :ok
  rescue
    e ->
      Logger.error(fn ->
        Poison.encode!(%{
          "log_type" => "error",
          "message" => e.message,
          "request_id" => Logger.metadata()[:request_id]
        })
      end)

      {:error, {:service_unavailable, "Cannot send email. Try later"}}
  end
end