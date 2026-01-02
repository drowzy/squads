socket "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [session: @session_options]],
  longpoll: [connect_info: [session: @session_options]]

socket "/socket", SquadsWeb.EventSocket,
  websocket: true,
  longpoll: false
