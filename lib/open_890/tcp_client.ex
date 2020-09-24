defmodule Open890.TCPClient do
  use GenServer
  require Logger

  @socket_opts [:binary, active: true]
  @port 60000

  alias Open890.KNS.User

  def start_link() do
    GenServer.start_link(__MODULE__, name: __MODULE__)
  end

  def init(_args) do
    radio_ip_address = System.fetch_env!("RADIO_IP_ADDRESS") |> String.to_charlist()
    radio_username = System.fetch_env!("RADIO_USERNAME")
    radio_password = System.fetch_env!("RADIO_PASSWORD")
    radio_user_is_admin = System.fetch_env("RADIO_USER_IS_ADMIN") == "true"

    kns_user =
      User.build()
      |> User.username(radio_username)
      |> User.password(radio_password)
      |> User.is_admin(radio_user_is_admin)

    send(self(), :connect_socket)

    {:ok,
     %{
       radio_ip_address: radio_ip_address,
       kns_user: kns_user
     }}
  end

  # Client API
  def send_command(cmd) do
    GenServer.cast(__MODULE__, {:send_cmd, cmd})
  end

  # Server API
  def handle_cast({:send_cmd, cmd}, %{socket: socket} = state) do
    socket |> send_command(cmd)
    {:noreply, state}
  end

  # networking

  def handle_info({:tcp, socket, msg}, %{socket: socket} = state) do
    # Logger.info("<- #{inspect msg}")

    new_state =
      msg
      |> String.split(";")
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce(state, fn single_message, acc ->
        handle_msg(single_message, acc)
      end)

    {:noreply, new_state}
  end


  def handle_info({:tcp_closed, _socket}, state) do
    Logger.warn("TCP socket closed. State: #{inspect(state)}")

    {:noreply, state}
  end

  def handle_info(:connect_socket, state) do
    {:ok, socket} = :gen_tcp.connect(state.radio_ip_address, @port, @socket_opts)

    Logger.info("Established TCP socket with radio on port #{@port}")

    send(self(), :login_radio)

    {:noreply, state |> Map.put(:socket, socket)}
  end


  # radio commands
  def handle_info(:enable_audioscope, %{socket: socket} = state) do
    Logger.info("Enabling audio scope via LAN")
    socket |> send_command("DD11")

    {:noreply, state}
  end

  def handle_info(:enable_voip, %{socket: socket} = state) do
    Logger.info("Enabling VOIP")
    socket |> send_command("##VP2")

    {:noreply, state}
  end

  def handle_info(:login_radio, %{socket: socket} = state) do
    socket |> send_command("##CN")
    {:noreply, state}
  end

  def handle_info(:send_keepalive, %{socket: socket} = state) do
    schedule_ping()

    socket |> send_command("PS")

    {:noreply, state}
  end

  # radio responses
  def handle_msg("##CN1", %{socket: socket, kns_user: kns_user} = state) do
    login = KNS.User.to_login(kns_user)

    socket |> send_command("##ID" <> login)
    state
  end

  # Logged in
  def handle_msg("##ID1", state) do
    Logger.info("signed in, scheduling first ping")
    schedule_ping()
    state
  end

  # Sent at the very end of the login sequence,
  # Finally OK to enable VOIP
  def handle_msg("##TI1", %{socket: _socket} = state) do
    Logger.info("received TI1, enabling voip")
    send(self(), :enable_voip)

    send(self(), :enable_audioscope)

    state
  end

  def handle_msg("PS1", state), do: state
  def handle_msg("##UE1", state), do: state

  def handle_msg(msg, %{socket: _socket} = state) when is_binary(msg) do
    cond do
      msg |> String.starts_with?("##DD3") ->
        audio_scope_data = msg |> parse_audioscope_data()

        Open890Web.Endpoint.broadcast("radio:audio_scope", "scope_data", %{
          payload: audio_scope_data
        })

        # %{state | audio_scope_data: audio_scope_data}
        state

      true ->
        Logger.warn("Unhandled message: #{inspect(msg)}")
        state
    end
  end

  defp schedule_ping do
    Process.send_after(self(), :send_keepalive, 5000)
  end

  defp send_command(socket, msg) when is_binary(msg) do
    cmd = msg <> ";"

    Logger.info("-> #{inspect(cmd)}")

    socket |> :gen_tcp.send(cmd)

    socket
  end

  defp parse_audioscope_data(msg) do
    msg
    |> String.trim_leading("##DD3")
    |> String.codepoints()
    |> Enum.chunk_every(2)
    |> Enum.map(&Enum.join/1)
    |> Enum.map(fn value ->
      val = Integer.parse(value, 16) |> elem(0)
      -val + 50
    end)
  end
end