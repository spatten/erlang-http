%%%-------------------------------------------------------------------
%%% @author Ruslan Babayev <ruslan@babayev.com>
%%% @copyright 2009, Ruslan Babayev
%%% @doc HTTP Client.
%%% @end
%%% Created : 26 Jul 2009 by Ruslan Babayev <ruslan@babayev.com>
%%%-------------------------------------------------------------------
-module(http_client).
-author('ruslan@babayev.com').

-behaviour(gen_server).

%% API
-export([start_link/0, request/1, request/2, send/1, send/2, worker/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-include("http.hrl").

-define(SERVER, ?MODULE). 

-record(state, {}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Starts the server.
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @spec request(URI::string()) -> ok | {error, Error}
%% @equiv request(URI, infinity)
%% @end
%%--------------------------------------------------------------------
request(URI) ->
    request(URI, infinity).

%%--------------------------------------------------------------------
%% @doc Parses the URI and sends the request to the server.
%% @spec request(URI::string(), Timeout::integer()) -> ok | {error, Error}
%% @end
%%--------------------------------------------------------------------
request(URI, Timeout) ->
    try http_lib:list_to_absoluteURI(URI) of
	AbsoluteURI ->
	    send(#http_request{uri = AbsoluteURI}, Timeout)
    catch
	error:Reason ->
	    {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @spec send(#http_request{}) -> ok | {error, Error}
%% @equiv send(Request, infinity)
%% @end
%%--------------------------------------------------------------------
send(Request) ->
    send(Request, infinity).

%%--------------------------------------------------------------------
%% @doc Sends the HTTP request to the server.
%% @spec send(#http_request{}, Timeout::integer()) -> ok | {error, Error}
%% @end
%%--------------------------------------------------------------------
send(Request, Timeout) ->
    gen_server:call(?SERVER, {send, Request}, Timeout).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Initializes the server.
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc Handles call messages.
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({send, Request}, From, State) ->
    proc_lib:spawn_link(?MODULE, worker, [From, Request]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc Handles cast messages.
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc Handles all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc Converts process state when code is changed.
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Worker process.
%% @end
%%--------------------------------------------------------------------
worker(From, #http_request{uri = URI} = Request)
  when URI#absoluteURI.scheme == http; URI#absoluteURI.scheme == https ->
    #absoluteURI{scheme = Scheme, host = Host, port = Port} = URI,
    Transport = transport(Scheme),
    Options = [binary, {active, false}, {reuseaddr, true}],
    Result =
	case Transport:connect(Host, Port, Options) of
	    {ok, Socket} ->
		ok = http_lib:send(Socket, http_lib:encode(Request)),
		http_lib:setopts(Socket, [{packet, http}]),
		case http_lib:recv(Socket, 0) of
		    {ok, {http_response, Version, StatusCode, _Phrase}} -> 
			case recv_headers(Socket) of
			    {ok, Headers} ->
				case recv_body(Socket, Headers) of
				    {ok, Body} ->
					#http_response{version = Version,
						       status = StatusCode,
						       headers = Headers,
						       body = Body};
				    {ok, Body, Trailers} ->
					Headers2 = Headers ++ Trailers,
					#http_response{version = Version,
						       status = StatusCode,
						       headers = Headers2,
						       body = Body};
				    Else ->
					Else
				end;
			    Else ->
				Else
			end;
		    Else ->
			Else
		end;
	    Else ->
		Else
	end,
    gen_server:reply(From, Result);
worker(From, _Request) ->
    gen_server:reply(From, {error, invalid_request}).

transport(http)  -> gen_tcp;
transport(https) -> ssl.

recv_headers(Socket) ->
    http_lib:setopts(Socket, [{packet, httph}]),
    recv_headers(Socket, []).

recv_headers(Socket, Acc) ->
    case http_lib:recv(Socket, 0) of
	{ok, {http_header, _, Name, _, Val}} ->
	    recv_headers(Socket, [{Name, Val} | Acc]);
	{ok, {http_error, "\r\n"}} ->
	    recv_headers(Socket, Acc);
	{ok, {http_error, "\n"}} ->
	    recv_headers(Socket, Acc);
	{ok, http_eoh} ->
	    {ok, lists:reverse(Acc)};
	Else ->
	    Else
    end.

recv_body(Socket, Headers) ->
    case proplists:get_value('Transfer-Encoding', Headers) of
	undefined ->
	    Length = case proplists:get_value('Content-Length', Headers) of
			 undefined ->
			     0;
			 ContentLength ->
			     list_to_integer(ContentLength)
		     end,
	    http_lib:setopts(Socket, [{packet, raw}]),
	    http_lib:recv(Socket, Length);
	"chunked" ->
	    recv_chunked(Socket);
	TransferEncoding ->
	    {error, {unknown_transfer_encoding, TransferEncoding}}
    end.

recv_chunked(Socket) ->
    case recv_chunk_size(Socket, []) of
	{ok, Body} ->
	    case recv_trailers(Socket, []) of
		{ok, Trailers} ->
		    {ok, Body, Trailers};
		Else ->
		    Else
	    end;
	Else ->
	    Else
    end.

recv_chunk_size(Socket, Acc) ->
    http_lib:setopts(Socket, [{packet, line}]),
    case http_lib:recv(Socket, 0) of
	{ok, Data} ->
	    F = fun(C) -> not lists:member(C, ";\r\n ") end,
	    Str = lists:takewhile(F, binary_to_list(Data)),
	    try erlang:list_to_integer(Str, 16) of
		ChunkSize -> recv_chunk(Socket, ChunkSize, Acc)
	    catch
		error:badarg -> {error, badchunksize}
	    end;
	Else ->
	    Else
    end.

recv_chunk(_Socket, 0, Acc) ->
    {ok, Acc};
recv_chunk(Socket, ChunkSize, Acc) ->
    http_lib:setopts(Socket, [{packet, raw}]),
    case http_lib:recv(Socket, ChunkSize + 2) of
	{ok, <<Chunk:ChunkSize/binary, "\r\n">>} ->
	    recv_chunk_size(Socket, list_to_binary([Acc, Chunk]));
	{ok, _Data} ->
	    {error, badchunk};
	Else ->
	    Else
    end.

recv_trailers(Socket, Acc) ->
    http_lib:setopts(Socket, [{packet, line}]),
    case http_lib:recv(Socket, 0) of
	{ok, <<"\r\n">>} ->
	    {ok, lists:reverse(Acc)};
	{ok, Trailer} ->
	    case string:tokens(binary_to_list(Trailer), ": \r\n") of
		[Name, Value] ->
		    recv_trailers(Socket, [{Name, Value} | Acc]);
		_ ->
		    {error, badtrailer}
	    end;
	Else ->
	    Else
    end.
