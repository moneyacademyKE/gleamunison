-module(gleamunison_http_util).
-export([index_html/0, url_decode/1, escape_json/1, send_json/3, send_response/3, status_text/1]).

index_html() ->
    <<"<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>Gleamunison Cloud Dashboard</title>
  <link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">
  <link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin>
  <link href=\"https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&display=swap\" rel=\"stylesheet\">
  <style>
    :root {
      --bg: #0b0f19;
      --card-bg: rgba(255, 255, 255, 0.03);
      --card-border: rgba(255, 255, 255, 0.08);
      --primary: #8b5cf6;
      --secondary: #ec4899;
      --text: #f3f4f6;
      --text-muted: #9ca3af;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: var(--bg);
      color: var(--text);
      font-family: 'Outfit', sans-serif;
      min-height: 100vh;
      display: flex;
      justify-content: center;
      align-items: center;
      overflow-x: hidden;
      position: relative;
    }
    .glow-1 {
      position: absolute; top: -10%; left: -10%; width: 50vw; height: 50vw;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(139,92,246,0.15) 0%, rgba(0,0,0,0) 70%);
      filter: blur(80px); z-index: 1;
    }
    .glow-2 {
      position: absolute; bottom: -10%; right: -10%; width: 50vw; height: 50vw;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(236,72,153,0.15) 0%, rgba(0,0,0,0) 70%);
      filter: blur(80px); z-index: 1;
    }
    .container {
      position: relative; z-index: 2; width: 90%; max-width: 520px;
      padding: 40px; border-radius: 24px;
      background: var(--card-bg); border: 1px solid var(--card-border);
      backdrop-filter: blur(20px); box-shadow: 0 20px 50px rgba(0,0,0,0.3);
      text-align: center; transition: transform 0.3s ease;
    }
    .container:hover { transform: translateY(-5px); }
    h1 {
      font-size: 2.5rem; font-weight: 800; margin-bottom: 12px;
      background: linear-gradient(135deg, var(--primary), var(--secondary));
      -webkit-background-clip: text; -webkit-text-fill-color: transparent;
    }
    p.subtitle { color: var(--text-muted); font-size: 0.9rem; margin-bottom: 24px; line-height: 1.5; }
    .badge {
      display: inline-block; padding: 6px 14px; font-size: 0.75rem; font-weight: 600;
      text-transform: uppercase; border-radius: 9999px;
      background: rgba(139,92,246,0.15); border: 1px solid rgba(139,92,246,0.3);
      color: #a78bfa; margin-bottom: 16px; letter-spacing: 0.05em;
    }
    .repl-box {
      margin: 16px 0; text-align: left;
    }
    .repl-box input {
      width: 100%; padding: 14px 16px; font-size: 0.95rem; font-family: 'Courier New', monospace;
      border-radius: 10px; border: 1px solid var(--card-border);
      background: var(--bg); color: var(--text); outline: none;
      transition: border-color 0.2s ease;
    }
    .repl-box input:focus { border-color: var(--primary); }
    .repl-result {
      margin-top: 10px; padding: 12px 16px; font-size: 0.85rem; font-family: 'Courier New', monospace;
      border-radius: 10px; background: rgba(255,255,255,0.02); border: 1px solid var(--card-border);
      min-height: 40px; white-space: pre-wrap; word-break: break-all; color: var(--text-muted);
    }
    .repl-result.success { color: #4ade80; border-color: rgba(74,222,128,0.3); }
    .repl-result.error { color: #f87171; border-color: rgba(248,113,113,0.3); }
    .counter-display {
      font-size: 2.5rem; font-weight: 800; margin: 12px 0; font-feature-settings: \"tnum\";
      background: linear-gradient(135deg, #ffffff, #9ca3af);
      -webkit-background-clip: text; -webkit-text-fill-color: transparent;
    }
    .btn {
      cursor: pointer; display: inline-block; width: 100%; padding: 14px;
      font-size: 0.95rem; font-weight: 600; border-radius: 12px; border: none;
      background: linear-gradient(135deg, var(--primary), #7c3aed);
      color: white; box-shadow: 0 10px 20px rgba(139,92,246,0.3);
      transition: all 0.2s ease; font-family: inherit;
    }
    .btn:hover { transform: scale(1.02); box-shadow: 0 15px 25px rgba(139,92,246,0.4); }
    .btn:active { transform: scale(0.98); }
    .btn-sm {
      width: auto; padding: 8px 20px; font-size: 0.85rem; margin-top: 8px;
      box-shadow: 0 5px 15px rgba(139,92,246,0.2);
    }
    .footer { margin-top: 24px; font-size: 0.7rem; color: var(--text-muted); letter-spacing: 0.02em; }
    .section-divider {
      margin: 20px 0; border: none; height: 1px;
      background: linear-gradient(90deg, transparent, var(--card-border), transparent);
    }
  </style>
</head>
<body>
  <div class=\"glow-1\"></div>
  <div class=\"glow-2\"></div>
  <div class=\"container\">
    <div class=\"badge\">VM-Native Webserver</div>
    <h1>Gleamunison</h1>
    <p class=\"subtitle\">A content-addressed runtime with algebraic effects running natively on the Erlang BEAM.</p>

    <hr class=\"section-divider\">

    <div class=\"repl-box\">
      <input id=\"expr\" type=\"text\" placeholder=\"Enter gleamunison expression...\" onkeydown=\"if(event.key==='Enter')evalExpr()\">
      <button class=\"btn btn-sm\" onclick=\"evalExpr()\">Evaluate</button>
      <div class=\"repl-result\" id=\"result\">Result will appear here</div>
    </div>

    <hr class=\"section-divider\">

    <div class=\"badge\" style=\"margin-top:8px\">Server Counter</div>
    <div class=\"counter-display\" id=\"counter\">0</div>
    <button class=\"btn\" onclick=\"increment()\">Interact with App</button>

    <div class=\"footer\">Served dynamically by the BEAM runtime</div>
  </div>
  <script>
    function evalExpr() {
      var expr = document.getElementById('expr').value;
      if (!expr) return;
      var result = document.getElementById('result');
      result.className = 'repl-result';
      result.textContent = 'Evaluating...';
      fetch('/eval?expr=' + encodeURIComponent(expr))
        .then(function(r) { return r.json(); })
        .then(function(d) {
          if (d.result) {
            result.className = 'repl-result success';
            result.textContent = d.result;
          } else if (d.error) {
            result.className = 'repl-result error';
            result.textContent = d.error;
          }
        })
        .catch(function(err) {
          result.className = 'repl-result error';
          result.textContent = 'Network error: ' + err;
        });
    }
    function increment() {
      fetch('/counter')
        .then(function(r) { return r.json(); })
        .then(function(d) {
          document.getElementById('counter').innerText = d.count;
          var btn = document.querySelector('.btn');
          btn.style.transform = 'scale(0.95)';
          setTimeout(function() { btn.style.transform = ''; }, 100);
        });
    }
  </script>
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
status_text(501) -> <<"Not Implemented">>;
status_text(_) -> <<"Internal Server Error">>.
