set search_path = public;

create or replace function headers(request express.request) returns express.outcome
language plpgsql
as $$
begin
    return omni_httpd.http_response(body => request.headers::text);
end;
$$;

create or replace function default_handler(request express.request) returns express.outcome
language plpgsql
as $$
begin
    return omni_httpd.http_response(status => 404, body => 'Not found');
end;
$$;

call express.reset_http_routes();
call express.add_route('not_found', 'default_handler', null, null, 0 );
call express.get('/headers', 'headers', 1);
call express.load_http_routes();
