# rest-db-api
Genero RESTful web service library

Generic set of code to supply database data through a REST API.  The project leverages the high-level REST framework in\
Genero along with SQL Handle library for writing generic SQL statements.  The Project has limitations and needs \
additional functionality.

## Current Project components
Almost all the logic is in the three library modules 
 - ServiceHelper.4gl
   - This module contains the startService function to start the service as well as the high level REST function endpoints.
 - SQLHelper.4gl
   - This module contains all the generic SQL functions to getting data from the database.  All data structures are returns\
     as JSONObject or JSONArray objects.
 - UserScopes.4gl
   - This module contains functions to parse and verify user scopes.  If authorization is being used, the user needs the
     scope Role.table.fetch, where table is the name of the database table.

## API Endpoints
Below is a list of the endpoints that are currently supported for fetching data.\
**URL Examples (using custdemo)**

 - /custdemo/table/{table} => List of all the records in the specified table
 - /custdemo/table/{table}/count => Number of records in the specified table
 - /custdemo/table/{table}/schema => List of columns and data type in the specified table
 - /custdemo/table/{table}/limit/{limit} => List of first x (limit) records in the specified table
 - /custdemo/table/{table}/limit/{limit}/offset/{offset} => 
List of first x (limit) records in the specified table, using
the offset are the starting point
 - /custdemo/table/{table}/query?column={column}&value={value} =>
List of all the records in the specified table where
column = value.
 - /custdemo/table/{table}/query?columns={col1,col2,col3}&values={val1,val2,val3}&operators={op1, op2, op3} =>
List of all the records in the specified groups

## Write Endpoints (delegate-only)

Insert, update, and delete are **delegate-only**: the library defines the
endpoints but contains no generic write SQL. A service registers a callback
function per table (or a `"*"` fallback) for each operation, and the endpoint
dispatches to it. Unregistered table+operation returns **501 Not Implemented**.
When scopes are enabled, writes require `Role.{table}.insert|update|delete`.

 - `POST   /custdemo/table/{table}` => Insert; JSON body carries the row values.
 - `PUT    /custdemo/table/{table}/{key}` => Update the keyed row; JSON body carries the new values.
 - `DELETE /custdemo/table/{table}/{key}` => Delete the keyed row.

The `{key}` path segment is one or more key parts, supporting single **and**
composite keys:

 - single, unnamed: `/table/products/5`
 - single, named: `/table/products/productid=5`
 - composite: `/table/order_details/orderid=10248,productid=11`

### Registering write delegates

```4gl
IMPORT FGL com.fourjs.restdblib.WriteDelegates
IMPORT FGL MyHandlers

CALL WriteDelegates.registerInsert("orders", FUNCTION MyHandlers.insertOrder)
CALL WriteDelegates.registerUpdate("orders", FUNCTION MyHandlers.updateOrder)
CALL WriteDelegates.registerDelete("orders", FUNCTION MyHandlers.deleteOrder)
```

A handler must match `WriteDelegates.T_WriteHandler` exactly, including the
parameter name `request` (parameter names are part of a Genero function
signature), and must be a regular function:

```4gl
PUBLIC FUNCTION insertOrder(request WriteDelegates.T_WriteRequest)
    RETURNS WriteDelegates.T_WriteResult
    ...
    RETURN WriteDelegates.okResult(rowsAffected, responseBody)   -- or errorResult(status, msg)
END FUNCTION
```

`request` carries `tableName`, `operation`, the raw `keyValue` and parsed
`keyParts`, the JSON `body` (insert/update), and the caller's `scopes`. See
`src/NorthwindWrites.4gl` for working single-key and composite-key examples
(including transaction handling for PostgreSQL).

##Additional Notes:
See the Confluence page https://4js.atlassian.net/wiki/spaces/FPS/pages/723419137/Genero+Generic+REST+API for more details.

