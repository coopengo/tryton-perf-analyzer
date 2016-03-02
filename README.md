## Presentation

This is a Lua script that could be executed in Redis to query performance
analyzer data.

The perf analyzer is not (for now) a part of Tryton. To install it, you can
apply this patch [patch](https://github.com/coopengo)

tryton-perf-analyzer is useful to analyze and understand unjustified slowness on
Trytond application. This could be done this way:

- log all server calls (with server time, db time)
- generate statistics about called method and queried tables
- for specific methods:

    - log all db accesses
    - profile all calls
    - log io (request / response)

- specific db queries (right now longer than x sec)

    - log sql
    - log backtrace

## Example

*coming soon*

## Usage

To execute script
`redis-cli --raw -h <host> -p <port> -n <db> --eval <script> , <arguments>`

- to prettify: `| column -t`
- to paginate: `| less`

## Known issues

- In some cases, we loose tm on calls (means that the thread based storage
  is not 100% efficient)
