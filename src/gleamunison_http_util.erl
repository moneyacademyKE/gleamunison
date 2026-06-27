-module(gleamunison_http_util).
-export([index_html/0, url_decode/1, escape_json/1, send_json/3, send_response/3, send_file_response/4, status_text/1, mime_type/1, notify_sse_eval/2, notify_sse_def/1, notify_sse_module/2]).

index_html() ->
    <<"<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>Gleamunison Console</title>
  <link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">
  <link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin>
  <link href=\"https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&family=JetBrains+Mono:wght@400;700&display=swap\" rel=\"stylesheet\">
  <link rel=\"stylesheet\" href=\"/static/css/dashboard.css\">
</head>
<body>
  <div class=\"glow-1\"></div>
  <div class=\"glow-2\"></div>
  
  <header>
    <h1>Gleamunison Console</h1>
    <p class=\"subtitle\">Content-Addressed Distributed Node Dashboard</p>
  </header>

  <nav class=\"tab-bar\">
    <button class=\"tab-btn active\" data-tab=\"overview\">Overview</button>
    <button class=\"tab-btn\" data-tab=\"modules\">Modules</button>
    <button class=\"tab-btn\" data-tab=\"processes\">Processes</button>
    <button class=\"tab-btn\" data-tab=\"definitions\">Definitions</button>
    <button class=\"tab-btn\" data-tab=\"sync\">Sync</button>
    <button class=\"tab-btn\" data-tab=\"logs\">Logs</button>
  </nav>

  <div id=\"tab-overview\" class=\"tab-content active\">
    <div class=\"dashboard-layout\">
      <div class=\"metrics-grid span-full\">
        <div class=\"metric-card\">
          <div class=\"metric-title\">Node Name</div>
          <div class=\"metric-value\" id=\"stat-node\">loading...</div>
        </div>
        <div class=\"metric-card\">
          <div class=\"metric-title\">Memory Usage</div>
          <div class=\"metric-value\" id=\"stat-mem\">loading...</div>
        </div>
        <div class=\"metric-card\">
          <div class=\"metric-title\">Uptime</div>
          <div class=\"metric-value\" id=\"stat-uptime\">loading...</div>
        </div>
        <div class=\"metric-card\">
          <div class=\"metric-title\">Active Node OS</div>
          <div class=\"metric-value\" id=\"stat-os\">loading...</div>
        </div>
      </div>

      <div class=\"card\">
        <div class=\"card-title\">Expression Playground</div>
        <div class=\"repl-box\">
          <input id=\"expr\" type=\"text\" placeholder=\"(add 1 2)\" onkeydown=\"if(event.key==='Enter')evalExpr()\">
          <button class=\"btn\" onclick=\"evalExpr()\">Execute S-Expression</button>
          <div class=\"repl-result\" id=\"result\">Result will appear here</div>
        </div>
      </div>

      <div class=\"card\">
        <div class=\"card-title\">Loaded AST Modules</div>
        <div class=\"module-list\" id=\"module-list\">
          <div style=\"color:var(--text-muted);font-size:0.85rem;\">No compiled modules loaded</div>
        </div>
      </div>
    </div>
  </div>

  <div id=\"tab-modules\" class=\"tab-content\">
    <div class=\"dashboard-layout\">
      <div class=\"card span-full\">
        <div class=\"card-title\">Enhanced Module Listing</div>
        <div class=\"module-list\" id=\"enhanced-module-list\">
          <div style=\"color:var(--text-muted);font-size:0.85rem;\">Select the Modules tab to load</div>
        </div>
      </div>
    </div>
  </div>

  <div id=\"tab-processes\" class=\"tab-content\">
    <div class=\"dashboard-layout\">
      <div class=\"card span-full\">
        <div class=\"card-title\">Running Processes</div>
        <div class=\"module-list\" id=\"process-list\">
          <div style=\"color:var(--text-muted);font-size:0.85rem;\">Loading processes...</div>
        </div>
      </div>
    </div>
  </div>

  <div id=\"tab-definitions\" class=\"tab-content\">
    <div class=\"dashboard-layout\">
      <div class=\"card\">
        <div class=\"card-title\">Notebook Definitions</div>
        <div class=\"module-list\" id=\"definitions-list\">
          <div style=\"color:var(--text-muted);font-size:0.85rem;\">Loading definitions...</div>
        </div>
      </div>
      <div class=\"card\">
        <div class=\"card-title\">Define New</div>
        <div class=\"repl-box\">
          <input id=\"def-name\" type=\"text\" placeholder=\"my_var\">
          <textarea id=\"def-expr\" placeholder=\"(lam x (add x 1))\"></textarea>
          <button class=\"btn\" onclick=\"defineExpr()\">Define</button>
          <div style=\"margin-top:8px;font-size:0.85rem;\" id=\"def-feedback\"></div>
        </div>
      </div>
    </div>
  </div>

  <div id=\"tab-sync\" class=\"tab-content\">
    <div class=\"dashboard-layout\">
      <div class=\"metrics-grid span-full\">
        <div class=\"metric-card\">
          <div class=\"metric-title\">Genesis Modules</div>
          <div class=\"metric-value\" id=\"sync-genesis\">-</div>
        </div>
        <div class=\"metric-card\">
          <div class=\"metric-title\">Notebook Defs</div>
          <div class=\"metric-value\" id=\"sync-notebook\">-</div>
        </div>
        <div class=\"metric-card\">
          <div class=\"metric-title\">Loaded Modules</div>
          <div class=\"metric-value\" id=\"sync-loaded\">-</div>
        </div>
        <div class=\"metric-card\">
          <div class=\"metric-title\">BEAM Files</div>
          <div class=\"metric-value\" id=\"sync-beams\">-</div>
        </div>
      </div>
      <div class=\"card span-full\">
        <div class=\"card-title\">Redefinitions</div>
        <div class=\"timeline\" id=\"redef-list\">
          <div style=\"color:var(--text-muted);font-size:0.85rem;\">No redefinitions yet</div>
        </div>
      </div>
    </div>
  </div>

  <div id=\"tab-logs\" class=\"tab-content\">
    <div class=\"dashboard-layout\">
      <div class=\"card span-full\">
        <div class=\"card-title\">Live Activity Feed</div>
        <div class=\"timeline\" id=\"timeline\">
          <div style=\"color:var(--text-muted);font-size:0.85rem;\">Waiting for events...</div>
        </div>
      </div>
    </div>
  </div>

  <script src=\"/static/js/dashboard.js\"></script>
</body>
</html>">>.

url_decode(Bin) when is_binary(Bin) ->
    NoPlus = binary:replace(Bin, <<"+">>, <<" ">>, [global]),
    url_decode_hex(NoPlus, <<>>).

url_decode_hex(<<$%, Hi, Lo, Rest/binary>>, Acc) ->
    Hex = binary_to_integer(<<Hi, Lo>>, 16),
    url_decode_hex(Rest, <<Acc/binary, Hex>>);
url_decode_hex(<<C, Rest/binary>>, Acc) ->
    url_decode_hex(Rest, <<Acc/binary, C>>);
url_decode_hex(<<>>, Acc) -> Acc.

escape_json(Bin) when is_binary(Bin) ->
    B1 = binary:replace(Bin, <<"\\">>, <<"\\\\">>, [global]),
    B2 = binary:replace(B1, <<"\"">>, <<"\\\"">>, [global]),
    B3 = binary:replace(B2, <<"\n">>, <<"\\n">>, [global]),
    <<"\"", B3/binary, "\"">>.

send_json(Socket, StatusCode, Body) ->
    Response = iolist_to_binary(io_lib:format(
        "HTTP/1.1 ~p ~s\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: ~p\r\nConnection: close\r\n\r\n~s",
        [StatusCode, status_text(StatusCode), byte_size(Body), Body]
    )),
    gen_tcp:send(Socket, Response),
    gen_tcp:close(Socket).

send_response(Socket, StatusCode, Body) ->
    Response = iolist_to_binary(io_lib:format(
        "HTTP/1.1 ~p ~s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ~p\r\nConnection: close\r\n\r\n~s",
        [StatusCode, status_text(StatusCode), byte_size(Body), Body]
    )),
    gen_tcp:send(Socket, Response),
    gen_tcp:close(Socket).

status_text(200) -> <<"OK">>;
status_text(404) -> <<"Not Found">>;
status_text(403) -> <<"Forbidden">>;
status_text(501) -> <<"Not Implemented">>;
status_text(_) -> <<"Internal Server Error">>.

mime_type(Path) when is_binary(Path) ->
    case filename:extension(Path) of
        <<".css">> -> <<"text/css">>;
        <<".js">> -> <<"application/javascript">>;
        <<".html">> -> <<"text/html">>;
        <<".svg">> -> <<"image/svg+xml">>;
        <<".png">> -> <<"image/png">>;
        <<".jpg">> -> <<"image/jpeg">>;
        <<".woff2">> -> <<"font/woff2">>;
        _ -> <<"application/octet-stream">>
    end.

send_file_response(Socket, StatusCode, Mime, Body) ->
    Response = iolist_to_binary(io_lib:format(
        "HTTP/1.1 ~p ~s\r\nContent-Type: ~s; charset=utf-8\r\nContent-Length: ~p\r\nConnection: close\r\n\r\n~s",
        [StatusCode, status_text(StatusCode), Mime, byte_size(Body), Body]
    )),
    gen_tcp:send(Socket, Response),
    gen_tcp:close(Socket).

notify_sse_eval(Expr, Result) ->
    Data = iolist_to_binary(io_lib:format(
        "{\"expr\":~ts,\"result\":~ts}",
        [escape_json(Expr), escape_json(Result)])),
    broadcast_sse(<<"eval_completed">>, Data).

notify_sse_def(Name) ->
    Data = iolist_to_binary(io_lib:format("{\"name\":~ts}", [escape_json(Name)])),
    broadcast_sse(<<"definition_added">>, Data).

notify_sse_module(ModName, Hash) ->
    Data = iolist_to_binary(io_lib:format(
        "{\"name\":\"~s\",\"hash\":\"~s\"}", [ModName, Hash])),
    broadcast_sse(<<"module_loaded">>, Data).

broadcast_sse(EventType, Data) ->
    case ets:whereis(gleamunison_sse_clients) of
        undefined -> ok;
        _ ->
            Clients = ets:tab2list(gleamunison_sse_clients),
            [Pid ! {sse_event, EventType, Data} || {Pid, _} <- Clients],
            ok
    end.
