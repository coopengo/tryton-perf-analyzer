## Presentation

This is a Lua script that could be executed in Redis to query performance
analyzer data.

The perf analyzer is not (for now) a part of Tryton. To install it, you can
grab the code from:

- maintained [branch](https://github.com/coopengo/trytond/tree/perf-analyzer)
- main [commit](https://github.com/coopengo/trytond/commit/ce6d272f22197d690eb3e66ed3941c72e2429b56)

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
