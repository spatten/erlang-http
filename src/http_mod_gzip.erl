%%%-------------------------------------------------------------------
%%% @author Ruslan Babayev <ruslan@babayev.com>
%%% @copyright 2009, Ruslan Babayev
%%% @doc This module implements gzip compression for `GET' requests.
%%% Uses `path' flag.
%%% @end
%%%-------------------------------------------------------------------
-module(http_mod_gzip).
-author('ruslan@babayev.com').
-export([init/0, handle/4]).

-include("http.hrl").

init() ->
    ok.

handle(_Socket, Request, Response, Flags)
  when Request#http_request.method == 'GET' ->
    Headers = Request#http_request.headers,
    Path = proplists:get_value(path, Flags),
    case accepts_gzip(Headers) andalso http_lib:is_compressible(Path) of
	true ->
	    ResponseHeaders = Response#http_response.headers,
	    case proplists:is_defined('Content-Encoding', ResponseHeaders) of
		false ->
		    {proceed, vary(gzip(Response)), Flags};
		true ->
		    {proceed, vary(Response), Flags}
	    end;
	false ->
	    {proceed, vary(Response), Flags}
    end;
handle(_Socket, _Request, undefined, Flags) ->
    {proceed, undefined, Flags};
handle(_Socket, _Request, Response, Flags)
  when is_record(Response, http_response) ->
    {proceed, vary(Response), Flags}.

accepts_gzip(Headers) ->
    case proplists:get_value('Accept-Encoding', Headers) of
	undefined ->
	    false;
	AcceptEncoding ->
	    lists:member("gzip", string:tokens(AcceptEncoding, ","))
    end.

vary(Response) when is_record(Response, http_response) ->
    case proplists:get_value('Vary', Response#http_response.headers) of
	"Accept-Encoding" ->
	    Response;
	_Else ->
	    Vary = {'Vary', "Accept-Encoding"},
	    Headers = [Vary | Response#http_response.headers],
	    Response#http_response{headers = Headers}
    end.

gzip(#http_response{body = Body} = Response) ->
    Gzipped = zlib:gzip(Body),
    GzippedSize = size(Gzipped),
    case GzippedSize < iolist_size(Body) of
	true ->
	    H0 = Response#http_response.headers,
	    H1 = [{'Content-Encoding', "gzip"} | H0],
	    H2 = keyreplace('Content-Length', H1, GzippedSize),
	    H3 = lists:keydelete('Accept-Ranges', 1, H2),
	    Response#http_response{status = 200, headers = H3, body = Gzipped};
	false ->
	    Response
    end.

keyreplace(Key, TupleList, NewValue) ->
    lists:keyreplace(Key, 1, TupleList, {Key, NewValue}).
