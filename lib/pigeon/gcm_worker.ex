defmodule Pigeon.GCMWorker do  
  use GenServer
  require Logger

  defp gcm_uri, do: 'https://gcm-http.googleapis.com/gcm/send'

  defp gcm_headers(key) do
    [{ "Authorization", "key=#{key}" },
     { "Content-Type", "application/json" },
     { "Accept", "application/json" }]
  end

  def start_link(name, gcm_key) do
    Logger.debug("Starting #{name}")
    GenServer.start_link(__MODULE__, %{gcm_key: gcm_key}, name: name)
  end

  def stop() do
    :gen_server.cast(self, :stop)
  end

  def init(args) do
    {:ok, args}
  end

  def handle_cast(:stop, state) do
    { :noreply, state }
  end

  def handle_cast({:push, :gcm, notification}, %{gcm_key: gcm_key} = state) do 
    request = encode_request(notification)
    HTTPoison.post(gcm_uri, request, gcm_headers(gcm_key))
    { :noreply, state }
  end

  def handle_cast({:push, :gcm, notification, on_response}, %{gcm_key: gcm_key} = state) do 
    request = encode_request(notification)
    {:ok, %HTTPoison.Response{status_code: status, body: body}} = HTTPoison.post(gcm_uri, request, gcm_headers(gcm_key))
    Logger.debug inspect(body)
    process_response(status, body, notification, on_response)

    { :noreply, state }
  end

  def encode_request(%Pigeon.GCM.Notification{registration_id: reg_ids, data: data} = notification) when is_list(reg_ids) do
    Poison.encode!(%{registration_ids: reg_ids, data: data, dry_run: true})
  end
  def encode_request(%Pigeon.GCM.Notification{registration_id: reg_id, data: data} = notification) do
    Poison.encode!(%{to: reg_id, data: data, dry_run: true})
  end

  def process_response(status, body, notification, on_response) do
    case status do
      200 -> 
        handle_200_status(body, notification, on_response)
      400 ->
        handle_error_status_code(:InvalidJSON, notification, on_response)
      401 ->
        handle_error_status_code(:AuthenticationError, notification, on_response)
      500 ->
        handle_error_status_code(:InternalServerError, notification, on_response)
      _ ->
        handle_error_status_code(:UnknownError, notification, on_response)
    end
  end

  def handle_error_status_code(reason, notification, on_response) do
    on_response.({:error, reason, notification})
  end

  def handle_200_status(body, %{registration_id: reg_ids} = notification, on_response) when is_list(reg_ids) do
    {:ok, json} = Poison.decode(body)
    results = Enum.zip(notification.registration_id, json["results"])
    for result <- results, do: process_callback(result, notification, on_response)
  end
  def handle_200_status(body, %{registration_id: reg_id} = notification, on_response) do
    {:ok, json} = Poison.decode(body)
    results = Enum.zip([notification.registration_id], json["results"])
    for result <- results, do: process_callback(result, notification, on_response)
  end

  def process_callback({reg_id, response} = result, notification, on_response) do
    thing = parse_result(response)
    case thing do
      {:ok, message_id} ->
        notification = %{ notification | registration_id: reg_id, message_id: message_id }
        on_response.({:ok, notification})
      {:ok, message_id, registration_id} ->
        notification = %{ notification | registration_id: reg_id, message_id: message_id, updated_registration_id: registration_id }
        on_response.({:ok, notification})
      {:error, reason} ->
        notification = %{ notification | registration_id: reg_id }
        on_response.({:error, reason, notification})
    end
  end

  def parse_result(result) do
    error = result["error"]
    if is_nil(error) do
      message_id = result["message_id"]
      registration_id = result["registration_id"]
      if is_nil(registration_id) do
        {:ok, message_id}
      else
        {:ok, message_id, registration_id}
      end
    else
      {:error, String.to_atom(error)}
    end
  end
end
