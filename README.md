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

 - /custdemo/table/{table} => List of all the records in the specified table                   |
 - /custdemo/table/{table}/count => Number of records in the specified table                         |
 - /custdemo/table/{table}/schema => List of columns and data type in the specified table             |
 - /custdemo/table/{table}/limit/{limit} => List of first x (limit) records in the specified table           |
 - /custdemo/table/{table}/limit/{limit}/offset/{offset} => List of first x (limit) records in the specified table, using\
                                                            the offset are the starting point
 - /custdemo/table/{table}/query?column={column}&value={value} => List of all the records in the specified table where\
                                                                  column = value.
 - /custdemo/table/{table}/query?columns={col1,col2,col3}&values={val1,val2,val3}&operators={op1, op2, op3} => List of all the records in the specified groups

