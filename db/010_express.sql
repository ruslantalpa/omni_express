drop schema if exists express cascade;
create schema express;

set search_path to express;
create domain express.request as omni_httpd.http_request;
create domain express.outcome as omni_httpd.http_outcome;
-- create domain express.response as omni_httpd.http_response;
create type route as (name text, method text, path text, handler text, priority integer);

create or replace procedure add_route(name text, handler text, method text, path text, priority integer)
language sql
as $$
    select set_config(
        'express.http_routes',
        jsonb_insert(
            coalesce(current_setting('express.http_routes', true),'[]')::jsonb,
            '{0}',
            to_jsonb(row(name, method, path, handler, priority)::express.route)
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
                        'select ', handler, '(request.*) ',
                        'from request ',
                        'where ',
                        case 
                            when method is not null then concat('request.method = ''', method, ''' ')
                            else 'true '
                        end,
                        'and ',
                        case 
                            when path is not null then concat('request.path = ''', path, ''' ')
                            else 'true '
                        end
                    ) as query,
                    priority
                from
                    jsonb_to_recordset(coalesce(current_setting('express.http_routes', true),'[]')::jsonb)
                    as t(method text, path text, handler text, priority integer, name text)
            ) as routes(name, query, priority)
        )
$$;

create or replace procedure express.reset_http_routes()
language sql
as $$
    select set_config('express.http_routes', '[]', false)
$$;

