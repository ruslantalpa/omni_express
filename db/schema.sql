set search_path = public;

create or replace function full_info(request express.request) returns express.outcome
language plpgsql
as $$
begin
    return omni_httpd.http_response(
        body => jsonb_build_object(
            'method', request.method::text,
            'path', request.path,
            'query_string', request.query_string,
            'body', convert_from(request.body, 'UTF8'),
            'headers', array_to_json(request.headers),
            'parameters', request.parameters,
            'query', request.query
        )::text
    );
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
call express.get('/info', 'full_info', 1); -- exact match
call express.get('^/(route)?information$', 'full_info', 1); -- regex match
call express.get('/article/:id/:page', 'full_info', 1); -- regex match with params
call express.load_http_routes();
-- select current_setting('express.http_routes', true);
-- select * from omni_httpd.handlers;


