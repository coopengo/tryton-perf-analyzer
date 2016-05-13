local _NAME = 'perf.lua'
local _VERSION = '0.1.0'
local _DESCRIPTION = 'A set of tools to query trytond perf analyzes data'
local _LICENSE = 'GNU GPL-3'
local _COPYRIGHT = '2016 Coopengo'
local _USAGE = [[
Usage: only ARGV are used (no KEYS). Possible commands are:

  - help    : print this text

Stored debug sessions:
  - session : list sessions - [user]

Statistics for the whole session:
  - method  : list called methods - <session> [order ~ tna]
  - table   : list queried tables - <session> [order ~ tna]

Server calls:
  - call    : list server calls in chrono. order - <session> [method]

Extra data per call:
  - profile : print profiling result for a call - <session> [call]
  - db      : print db accesses for a call - <session> [call]

Deep query analyzes:
  - query   : print query analyzes - <session> [rank]
]]

-- helpers

local function get_session(session)
    local keys = redis.call('KEYS', 's:' .. session .. '*')
    if #keys == 0 then
        return nil, 'invalid-session'
    elseif #keys > 1 then
        table.insert(keys, 1, 'many-candidates')
        return nil, keys
    else
        return keys[1]:match('s:(%x+)')
    end
end

local function generate_stats_api(name)
    return function(session, order)
        assert(session, 'Missing session argument')

        local sess_id, result = get_session(session)
        if not sess_id then
            return result
        end

        local template, pri_ns, sec_ns
        if order and order == 'n' then
            result = {string.format('%s\tnumber\ttime\tavg', name)}
            template = '%s\t%d\t%.3f\t%.3f'
            pri_ns = name:sub(1, 1) .. ':n:'
            sec_ns = name:sub(1, 1) .. ':t:'
        elseif order and order == 'a' then
            result = {string.format('%s\tavg\ttime\tnumber', name)}
            template = '%s\t%.3f\t%.3f\t%d'
            pri_ns = name:sub(1, 1) .. ':t:'
            sec_ns = name:sub(1, 1) .. ':n:'
        else
            order = 't'
            result = {string.format('%s\ttime\tnumber\tavg', name)}
            template = '%s\t%.3f\t%d\t%.3f'
            pri_ns = name:sub(1, 1) .. ':t:'
            sec_ns = name:sub(1, 1) .. ':n:'
        end

        local pri_key = pri_ns .. sess_id
        local sec_key = sec_ns .. sess_id
        local elements = redis.call('ZREVRANGE', pri_key, 0, -1)
        local list = {}
        for _, element in ipairs(elements) do
            local pri_score = assert(tonumber(redis.call('ZSCORE', pri_key, element)))
            local sec_score = assert(tonumber(redis.call('ZSCORE', sec_key, element)))
            local item
            if order == 't' then
                item = {element, pri_score, sec_score, pri_score / sec_score}
            elseif order == 'n' then
                item = {element, pri_score, sec_score, sec_score / pri_score}
            elseif order == 'a' then
                item = {element, pri_score / sec_score, pri_score, sec_score}
            end
            list[#list+1] = item
        end
        if order == 'a' then
            table.sort(list, function(a, b) return a[2] > b[2] end)
        end
        for _, item in ipairs(list) do
            result[#result+1] = template:format(unpack(item))
        end
        return result
    end
end

local extra_getter = {}

extra_getter.p = function(key)
    return redis.call('GET', key)
end

extra_getter.db = function(key)
    local result = {'action\ttable\ttime'}
    local template = '%s\t%s\t%.3f'
    local accesses = redis.call('LRANGE', key, 0, -1)
    for _, access in ipairs(accesses) do
        local a = cmsgpack.unpack(access)
        result[#result+1] = template:format(a.action, a.table, a.tm)
    end
    return result
end

local function generate_extra_api(name)
    return function(session, call)
        assert(session, 'Missing session argument')
        local sess_id, result = get_session(session)
        if not sess_id then
            return result
        end

        if call then
            local key = 'x:' .. name .. ':' .. sess_id .. ':' .. call
            local exists = redis.call('EXISTS', key)
            if exists > 0 then
                return extra_getter[name](key)
            else
                return {'inexisting-key', key}
            end
        else
            local result = {'method\tcall'}
            local template = '%s\t%s'

            local pattern = 'x:' .. name .. ':' .. sess_id .. ':'
            local keys = redis.call('KEYS', pattern .. '*')
            for _, item in ipairs(keys) do
                call = item:match(pattern .. '(%d+)')
                local c_key = 'c:' .. sess_id .. ':' .. call
                local method = redis.call('HGET', c_key, 'method')
                result[#result+1] = template:format(method, call)
            end
            return result
        end
    end
end

-- api

local api = {}

api.help = function()
    return string.format('%s: %s\n\n%s', _NAME, _DESCRIPTION, _USAGE)
end

api.session = function(user)
    local header = {'session', 'user', 'first', 'last', 'nb', 'tm'}
    local template = '%s\t%s\t%s\t%s\t%d\t%.3f'
    local result = {table.concat(header, '\t')}

    local function is_eligible(key)
        if user then
            local sess_user = redis.call('HGET', key, 'user')
            return sess_user == user
        else
            return true
        end
    end

    local function insert(key)
        local line = {key:match('s:(%x+)')}
        for i = 2, #header do
            local k = header[i]
            local v = redis.call('HGET', key, k)
            line[#line+1] = v
        end
        result[#result+1] = template:format(unpack(line))
    end

    local keys = redis.call('KEYS', 's:*')
    for _, key in ipairs(keys) do
        if is_eligible(key) then
            insert(key)
        end
    end
    return result
end

api.method = generate_stats_api('method')

api.table = generate_stats_api('table')

api.call = function(session, method)
    assert(session, 'Mission session argument')

    local sess_id, result = get_session(session)
    if not sess_id then
        return result
    end

    local header = {'#', 'method', 'dt', 'tm', 'db_nb', 'db_tm'}
    local template = '%d\t%s\t%s\t%.3f\t%d\t%.3f\t%d\t%d'
    local result = {table.concat(header, '\t')}

    local function is_eligible(key)
        if method then
            local m = redis.call('HGET', key, 'method')
            return m == method
        else
            return true
        end
    end

    local function insert(key, call)
        local line = {call}
        for i = 2, #header do
            local k = header[i]
            local v = redis.call('HGET', key, k)
            line[#line+1] = v or 0
        end
        result[#result+1] = template:format(unpack(line))
    end

    local exists
    local inc = 1
    repeat
        local key = 'c:' .. sess_id .. ':' .. inc
        exists = redis.call('EXISTS', key)
        if exists > 0 then
            if is_eligible(key) then
                insert(key, inc)
            end
            inc = inc + 1
        end
    until exists == 0
    return result
end

api.profile = generate_extra_api('p')

api.db = generate_extra_api('db')

local query_template = [[
context: %s - %s

db context: %s - %s - %d rows in %.3f secs

sql:
%s

backtrace:
%s
]]

api.query = function(session, rank)
    assert(session, 'Mission session argument')

    local sess_id, result = get_session(session)
    if not sess_id then
        return result
    end

    local key = 'q:' .. sess_id
    if rank then
        local query = redis.call('LINDEX', key, rank-1)
        query = cmsgpack.unpack(query)
        return query_template:format(query.method, query.call, query.action,
            query.table, query.count, query.tm, query.sql, query.bt)
    else
        local queries = redis.call('LRANGE', key, 0, -1)
        local result = {'#\tmethod\tcall\taction\ttable'}
        local template = '%d\t%s\t%d\t%s\t%s'
        for i, query in ipairs(queries) do
            local q = cmsgpack.unpack(query)
            result[#result+1] = template:format(i, q.method, q.call, q.action,
                q.table)
        end
        return result
    end
end

-- main

local command = table.remove(ARGV, 1)
if not command then
    command = 'help'
end
command = assert(api[command], 'Unknown command: ' .. command)
return command(unpack(ARGV))
