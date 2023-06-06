drop schema if exists express cascade;
create schema express;

set search_path to express;
-- create domain express.request as omni_httpd.http_request;

create domain express.outcome as omni_httpd.http_outcome;
-- create domain express.response as omni_httpd.http_response;
create type path as (value text, is_regex boolean, params text[]);
create type route as (name text, method text, path express.path, handler text, priority integer);
create type express.request as (
    method omni_http.http_method,
    path text,
    query_string text,
    body bytea,
    headers omni_http.http_header[],
    parameters jsonb,
    query text[]
);


create or replace function http_request(
    route jsonb,
    request omni_httpd.http_request
)
returns express.request
language plpgsql
as $$
declare
    path_params jsonb := jsonb_build_object();
    query_params text[] := '{}';
    matches text[];
    params text[] := array(select jsonb_array_elements_text(route->'path'->'params'));
    i integer;
begin
    if (route->'path'->>'is_regex')::boolean and array_length(params, 1) > 0 then
        matches := array(select (regexp_matches(request.path, route->'path'->>'value', 'g')));
        for i in 1..array_length(params, 1)
        loop
            path_params := path_params || jsonb_build_object(params[i], matches[1][i]);
        end loop;
    end if;
    if request.query_string is not null then
        query_params := omni_web.parse_query_string(request.query_string);
    end if;

    return row(
        request.method,
        request.path,
        request.query_string,
        request.body,
        request.headers,
        path_params,
        query_params
    )::express.request;
end;
$$;


create or replace function parse_path(path text)
returns express.path
language plpgsql
as $$
declare
    is_regex boolean := false;
    path_regex text := path;
    params text[] := '{}';
begin
    -- check if the path contains express-style parameters
    if path like '%/:%' then
        -- replace :param with a regex capture group
        path_regex := regexp_replace(path, ':(\w+)', '([^/]+)', 'g');
        params := array(select unnest from (select unnest(regexp_matches(path, ':(\w+)', 'g')) from generate_series(1, 1)) s);
        is_regex := true;
    -- check if the path contains regular expression special characters
    elsif path ~ '[.*+?$^|()]' then
        is_regex := true;
    end if;
    -- return the path as a path_spec
    return row(path_regex, is_regex, params)::express.path;
end;
$$;


create or replace procedure add_route(name text, handler text, method text, path text, priority integer)
language sql
as $$
    select set_config(
        'express.http_routes',
        jsonb_insert(
            coalesce(current_setting('express.http_routes', true),'[]')::jsonb,
            '{0}',
            to_jsonb(row(name, method, express.parse_path(path), handler, priority)::express.route)
        )::text,
        false
    )
$$;

create or replace procedure get(path text, handler text, priority integer default 0, name text default null)
language sql
as $$
    call express.add_route(coalesce(name,path), handler, 'GET', path, priority)
$$;

create or replace procedure post(path text, handler text, priority integer default 0, name text default null)
language sql
as $$
    call express.add_route(coalesce(name,path), handler, 'POST', path, priority)
$$;


create or replace procedure express.load_http_routes()
language sql
as $$
    update omni_httpd.handlers
    set
        query = (
            select
                omni_httpd.cascading_query(name, query order by priority desc nulls last)
            from (
                select
                    name,
                    concat(
                        'select ', handler, '(express.http_request(''', row_to_json(t)::text,''', request.*)) ',
                        'from request ',
                        'where ',
                        case 
                            when method is not null then concat('request.method = ''', method, ''' ')
                            else 'true '
                        end,
                        'and ',
                        case 
                            when path is not null and not (path).is_regex then concat('request.path = ''', (path).value, ''' ')
                            when path is not null and (path).is_regex then concat('request.path ~ ''', (path).value, ''' ')
                            else 'true '
                        end
                    ) as query,
                    priority
                from
                    jsonb_to_recordset(coalesce(current_setting('express.http_routes', true),'[]')::jsonb)
                    as t(method text, path express.path, handler text, priority integer, name text)
            ) as routes(name, query, priority)
        )
$$;

create or replace procedure express.reset_http_routes()
language sql
as $$
    select set_config('express.http_routes', '[]', false)
$$;

