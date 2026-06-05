##############################################################################################
# serverHelper.4gl provides functions to define URI endpoints for GET, POST, PUT, and DELETE
# without relying on the database schema.
##############################################################################################
PACKAGE com.fourjs.restdblib

IMPORT com
IMPORT util

IMPORT FGL com.fourjs.restdblib.SQLHelper
IMPORT FGL com.fourjs.restdblib.UserScopes
IMPORT FGL com.fourjs.restdblib.JsonParser
IMPORT FGL com.fourjs.restdblib.WriteDelegates

PUBLIC DEFINE internalError
    RECORD ATTRIBUTE(WSError = "Internal Server Error",
        json_name = "responseError")
    respCode INTEGER,
    respMessage STRING
END RECORD

PUBLIC DEFINE responseError
    RECORD ATTRIBUTE(WSError = "Response Error", json_name = "responseError")
    respCode INTEGER,
    respMessage STRING
END RECORD

PUBLIC DEFINE badRequestError
    RECORD ATTRIBUTE(WSError = "Bad Request", json_name = "responseError")
    respCode INTEGER,
    respMessage STRING
END RECORD

PUBLIC DEFINE unAuthError
    RECORD ATTRIBUTE(WSError = "User not authorized",
        json_name = "responseError")
    respCode INTEGER,
    respMessage STRING
END RECORD

PUBLIC DEFINE notFoundError
    RECORD ATTRIBUTE(WSError = "Not Found", json_name = "responseError")
    respCode INTEGER,
    respMessage STRING
END RECORD

PUBLIC DEFINE useScopes BOOLEAN = TRUE

PRIVATE DEFINE httpContext DICTIONARY ATTRIBUTE(WSContext) OF STRING

PRIVATE CONSTANT _SQL_OP_CONTAINS STRING = 'LIKE'
PRIVATE CONSTANT _ARG_DELIM STRING = '[|,]'
PRIVATE DEFINE md_sqlOperator DICTIONARY OF STRING =
    ('eq': '=',
        'ne': '<>',
        'gt': '>',
        'lt': '<',
        'ge': '>=',
        'le': '<=',
        'contains': _SQL_OP_CONTAINS)

PRIVATE CONSTANT _ERR_BAD_REQUEST STRING = '400'
PRIVATE CONSTANT _ERR_UNAUTHORIZED STRING = '403'
PRIVATE CONSTANT _ERR_NOT_FOUND STRING = '404'
PRIVATE CONSTANT _ERR_INTERNAL STRING = '500'
PRIVATE CONSTANT _ERR_TABLE_DNE STRING = '999'
PRIVATE CONSTANT _ERR_TABLE_EMPTY STRING = '998'
PRIVATE CONSTANT _ERR_ARG_CNT_MISMATCH STRING = '997'

PUBLIC FUNCTION registerService(serviceName STRING) RETURNS (BOOLEAN)
   VAR success = TRUE
   TRY
      CALL com.WebServiceEngine.RegisterRestService(
         "com.fourjs.restdblib.ServiceHelper",
         serviceName
      )
   CATCH
      LET success = FALSE
   END TRY
   RETURN success

END FUNCTION #registerService

##############################################################################################
#+
#+ startService Starts the web service process and returns a string when it is stopped
#+
##############################################################################################
PUBLIC FUNCTION startService() RETURNS STRING
    DEFINE serviceStatus INTEGER

    CALL com.WebServiceEngine.Start()
    LET int_flag = FALSE
    WHILE int_flag = FALSE

        LET serviceStatus = com.WebServiceEngine.ProcessServices(-1)
        CASE serviceStatus
            WHEN 0
                DISPLAY "Request processed."
            WHEN -1
                DISPLAY "Timeout reached."
            WHEN -2
                # GAS told the DVM to shut down: fatal, the application must exit.
                RETURN "Disconnected from application server."
            WHEN -4
                # Ctrl-C / interruption received: stop the loop gracefully.
                DISPLAY "Server interrupted with Ctrl-C."
                LET int_flag = TRUE
            WHEN -10
                # Unknown internal engine error: per docs the application must exit.
                CALL logServiceError("Internal server error", serviceStatus)
                RETURN "Internal server error."
            WHEN -15
                # The web service engine was not started: fatal, the application must exit.
                CALL logServiceError("Web service engine not started", serviceStatus)
                RETURN "Web service engine not started."
            OTHERWISE
                # Any other status is a per-request error (e.g. -3 connection lost,
                # -9 unsupported operation, -23 deserialization, -32 serialization,
                # -35/-36 bad REST operation/parameter). Log it and keep serving:
                # a single bad request must never bring the whole service down.
                CALL logServiceError("Request error", serviceStatus)
        END CASE

    END WHILE
    RETURN "Server stopped"

END FUNCTION

##############################################################################################
#+
#+ logServiceError Logs a recoverable or fatal web service engine status to the console and
#+ the program error log, including the SQL/engine error message when available.
#+
##############################################################################################
PRIVATE FUNCTION logServiceError(context STRING, statusCode INTEGER)
    DEFINE message STRING

    LET message = SFMT("%1 (status %2): %3", context, statusCode, sqlca.sqlerrm)
    DISPLAY message
    CALL errorlog(message)

END FUNCTION #logServiceError

##############################################################################################
#+
#+ getAllRecords Gets and returns all the records in a table
#+
##############################################################################################
PUBLIC FUNCTION getAllRecords(
    tableName STRING ATTRIBUTES(WSParam))
    ATTRIBUTES(WSGet,
        WSPath = "/table/{tableName}",
        WSDescription = 'Fetches all the data from the specified table')
    RETURNS util.JSONArray ATTRIBUTES(WSMedia = "application/json")

    DEFINE jsonArray util.JSONArray

    IF NOT authorizationCheck(tableName, cFetchOperation) THEN
        RETURN jsonArray
    END IF

    LET jsonArray = getTableRecords(tableName, -1, -1)

    IF jsonArray IS NULL THEN
        CALL setRestError(_ERR_TABLE_DNE, tableName)
    ELSE
        IF jsonArray.getLength() == 0 THEN
            CALL setRestError(_ERR_TABLE_EMPTY, tableName)
        END IF
    END IF

    RETURN jsonArray

END FUNCTION

##############################################################################################
#+
#+ getRecordCount Gets and returns all number of records in a table
#+
##############################################################################################
PUBLIC FUNCTION getRecordCount(
    tableName STRING ATTRIBUTES(WSParam))
    ATTRIBUTES(WSGet,
        WSPath = "/table/{tableName}/count",
        WSDescription = 'Fetches the record count from the specified table')
    RETURNS INTEGER

    DEFINE lCount INTEGER

    IF NOT authorizationCheck(tableName, cFetchOperation) THEN
        RETURN lCount
    END IF

    LET lCount = getTableRecordCount(tableName)

    IF lCount IS NULL THEN
        CALL setRestError(_ERR_INTERNAL, tableName)
    ELSE
        IF lCount == 0 THEN
            CALL setRestError(_ERR_NOT_FOUND, tableName)
        END IF
    END IF

    RETURN lCount

END FUNCTION

##############################################################################################
#+
#+ getSchema Gets and returns the schema for a table
#+
##############################################################################################
PUBLIC FUNCTION getSchema(
    tableName STRING ATTRIBUTES(WSParam))
    ATTRIBUTES(WSGet,
        WSPath = "/table/{tableName}/schema",
        WSDescription = 'Fetches the table schema for the specified table')
    RETURNS util.JSONObject

    DEFINE jsonObj util.JSONObject
    DEFINE schemaList DICTIONARY OF STRING

    IF NOT authorizationCheck(tableName, cFetchOperation) THEN
        RETURN jsonObj
    END IF

    LET schemaList = getTableSchema(tableName)

    IF schemaList.getLength() == 0 THEN
        CALL setRestError(_ERR_NOT_FOUND, tableName)
    ELSE
        LET jsonObj = util.JSONObject.fromFGL(schemaList)
    END IF

    RETURN jsonObj

END FUNCTION

##############################################################################################
#+
#+ getRecordsWithLimit Gets and returns all the records in a table up to the specified limit
#+
##############################################################################################
PUBLIC FUNCTION getRecordsWithLimit(
    tableName STRING ATTRIBUTES(WSParam), recLimit INTEGER ATTRIBUTES(WSParam))
    ATTRIBUTES(WSGet,
        WSPath = "/table/{tableName}/limit/{recLimit}",
        WSDescription
            = 'Fetches the reccords from the specified table up to the limit specified')
    RETURNS util.JSONArray ATTRIBUTES(WSMedia = "application/json")

    DEFINE jsonArray util.JSONArray

    IF NOT authorizationCheck(tableName, cFetchOperation) THEN
        RETURN jsonArray
    END IF

    LET jsonArray = getTableRecords(tableName, recLimit, -1)

    IF jsonArray IS NULL THEN
        CALL setRestError(_ERR_INTERNAL, tableName)
    ELSE
        IF jsonArray.getLength() == 0 THEN
            CALL setRestError(_ERR_NOT_FOUND, NULL)
        END IF
    END IF

    RETURN jsonArray

END FUNCTION

##############################################################################################
#+
#+ getRecordsWithLimitOffset Gets and returns all the records in a table starting at the
#+ specified offset and until the specified limit
#+
#+ This method allows the client to implement paging within the application
#+
##############################################################################################
PUBLIC FUNCTION getRecordsWithLimitOffset(
    tableName STRING ATTRIBUTES(WSParam),
    recLimit INTEGER ATTRIBUTES(WSParam),
    recOffset INTEGER ATTRIBUTES(WSParam))
    ATTRIBUTES(WSGet,
        WSPath = "/table/{tableName}/limit/{recLimit}/offset/{recOffset}",
        WSDescription
            = 'Fetches the reccords from the specified table up to the limit specified')
    RETURNS util.JSONArray ATTRIBUTES(WSMedia = "application/json")

    DEFINE jsonArray util.JSONArray

    IF NOT authorizationCheck(tableName, cFetchOperation) THEN
        RETURN jsonArray
    END IF

    LET jsonArray = getTableRecords(tableName, recLimit, recOffset)

    IF jsonArray IS NULL THEN
        CALL setRestError(_ERR_INTERNAL, NULL)
    ELSE
        IF jsonArray.getLength() == 0 THEN
            CALL setRestError(_ERR_NOT_FOUND, NULL)
        END IF
    END IF

    RETURN jsonArray

END FUNCTION

##############################################################################################
#+
#+ getRecordsQuery Gets and returns all the records in a table that match the query criteria.
#+ colName is the name of the column to query
#+ colValue is the column value (for equality)
#+ contains is the column value (for contains)
#+
##############################################################################################
PUBLIC FUNCTION getRecordsQuery(
    tableName STRING ATTRIBUTES(WSParam),
    colName STRING ATTRIBUTES(WSQuery, WSOptional, WSName = "column"),
    colValue STRING ATTRIBUTES(WSQuery, WSOptional, WSName = "value"),
    operator STRING ATTRIBUTES(WSQuery, WSOptional, WSName = "operator"))
    ATTRIBUTES(WSGet,
        WSPath = "/table/{tableName}/query",
        WSDescription = 'Fetches all the data from the specified table')
    RETURNS util.JSONArray ATTRIBUTES(WSMedia = "application/json")

    DEFINE jsonArray util.JSONArray
    DEFINE colList, valList, opListREST, opListSQL DYNAMIC ARRAY OF STRING
    DEFINE i, argCnt INTEGER

    IF NOT authorizationCheck(tableName, cFetchOperation) THEN
        RETURN jsonArray
    END IF

    # Initialize argument lists
    LET colList = colName.split(_ARG_DELIM)
    LET valList = colValue.split(_ARG_DELIM)
    LET opListREST = operator.split(_ARG_DELIM)
    IF colList.getLength() == valList.getLength()
        AND valList.getLength() == opListREST.getLength() THEN
        LET argCnt = colList.getLength()
    ELSE
        CALL setRestError(_ERR_ARG_CNT_MISMATCH, tableName)
        RETURN jsonArray
    END IF
    # If no arguments, return all for table; otherwise loop through args
    IF argCnt < 1 THEN
        LET jsonArray = getTableRecords(tableName, -1, -1)
    END IF
    FOR i = 1 TO argCnt
        LET colList[i] = colList[i].trimWhiteSpace()
        LET valList[i] = valList[i].trimWhiteSpace()
        LET opListSQL[i] = getSqlOperator(opListREST[i])
        IF opListSQL[i] == _SQL_OP_CONTAINS THEN
            LET valList[i] = "%", valList[i], "%"
        END IF
    END FOR
    IF colList.getLength() > 0 THEN
        LET jsonArray = getTableQuery(tableName, colList, valList, opListSQL)
    END IF

    IF jsonArray IS NULL THEN
        CALL setRestError(_ERR_INTERNAL, tableName)
    ELSE
        IF jsonArray.getLength() == 0 THEN
            CALL setRestError(_ERR_NOT_FOUND, tableName)
        END IF
    END IF

    RETURN jsonArray

END FUNCTION #getRecordsQuery
##############################################################################################
#+
#+ getQueryResults receives POST JSON body returns all the records in a table that match the query criteria from the body.
#+
##############################################################################################
PUBLIC FUNCTION getQueryResults(
    jsonObj util.JSONObject)
    ATTRIBUTES(WSPost,
        WSPath = "/sql",
        WSDescription = 'Executes a specified query')
    RETURNS util.JSONArray ATTRIBUTES(WSMedia = "application/json")
    DEFINE jsonArray util.JSONArray
    DEFINE sqlString STRING
    DEFINE temp_rec TJsonBody
    CALL jsonObj.toFGL(temp_rec)
    LET sqlString = temp_rec.toSQLString()
    LET jsonArray = runSQL(sqlString)

    # TODO: parse query to get table names and check authorization?
    IF NOT authorizationCheck("sql", cFetchOperation) THEN
        RETURN jsonArray
    END IF
    RETURN jsonArray

END FUNCTION #getQueryResults

##############################################################################################
#+
#+ insertRecord Inserts a record into the specified table. The actual write is
#+ delegated to a callback registered with WriteDelegates.registerInsert; the
#+ JSON body carries the row values.
#+
##############################################################################################
PUBLIC FUNCTION insertRecord(
    tableName STRING ATTRIBUTES(WSParam),
    body util.JSONObject)
    ATTRIBUTES(WSPost,
        WSPath = "/table/{tableName}",
        WSDescription = 'Inserts a record into the specified table (delegated)')
    RETURNS util.JSONObject ATTRIBUTES(WSMedia = "application/json")

    DEFINE request WriteDelegates.T_WriteRequest

    IF NOT authorizationCheck(tableName, cInsertOperation) THEN
        RETURN NULL
    END IF

    LET request.tableName = tableName
    LET request.operation = cInsertOperation
    LET request.body = body
    LET request.scopes = httpContext["scopes"]

    RETURN dispatchWrite(request)

END FUNCTION #insertRecord

##############################################################################################
#+
#+ updateRecord Updates the record(s) identified by the {keyValue} path segment
#+ (single or composite key). The write is delegated to a callback registered
#+ with WriteDelegates.registerUpdate; the JSON body carries the new values.
#+
##############################################################################################
PUBLIC FUNCTION updateRecord(
    tableName STRING ATTRIBUTES(WSParam),
    keyValue STRING ATTRIBUTES(WSParam),
    body util.JSONObject)
    ATTRIBUTES(WSPut,
        WSPath = "/table/{tableName}/{keyValue}",
        WSDescription = 'Updates the keyed record in the specified table (delegated)')
    RETURNS util.JSONObject ATTRIBUTES(WSMedia = "application/json")

    DEFINE request WriteDelegates.T_WriteRequest

    IF NOT authorizationCheck(tableName, cUpdateOperation) THEN
        RETURN NULL
    END IF

    LET request.tableName = tableName
    LET request.operation = cUpdateOperation
    LET request.keyValue = keyValue
    LET request.keyParts = WriteDelegates.parseKeyParts(keyValue)
    LET request.body = body
    LET request.scopes = httpContext["scopes"]

    RETURN dispatchWrite(request)

END FUNCTION #updateRecord

##############################################################################################
#+
#+ deleteRecord Deletes the record(s) identified by the {keyValue} path segment
#+ (single or composite key). The write is delegated to a callback registered
#+ with WriteDelegates.registerDelete.
#+
##############################################################################################
PUBLIC FUNCTION deleteRecord(
    tableName STRING ATTRIBUTES(WSParam),
    keyValue STRING ATTRIBUTES(WSParam))
    ATTRIBUTES(WSDelete,
        WSPath = "/table/{tableName}/{keyValue}",
        WSDescription = 'Deletes the keyed record in the specified table (delegated)')
    RETURNS util.JSONObject ATTRIBUTES(WSMedia = "application/json")

    DEFINE request WriteDelegates.T_WriteRequest

    IF NOT authorizationCheck(tableName, cDeleteOperation) THEN
        RETURN NULL
    END IF

    LET request.tableName = tableName
    LET request.operation = cDeleteOperation
    LET request.keyValue = keyValue
    LET request.keyParts = WriteDelegates.parseKeyParts(keyValue)
    LET request.scopes = httpContext["scopes"]

    RETURN dispatchWrite(request)

END FUNCTION #deleteRecord

##############################################################################################
#+
#+ dispatchWrite Runs a write request through WriteDelegates and translates the
#+ result to an HTTP response: a success body on success, or a REST error.
#+
##############################################################################################
PRIVATE FUNCTION dispatchWrite(request WriteDelegates.T_WriteRequest)
    RETURNS util.JSONObject
    DEFINE result WriteDelegates.T_WriteResult
    DEFINE response util.JSONObject

    LET result = WriteDelegates.dispatch(request.operation, request)

    IF NOT result.ok THEN
        CALL setWriteError(result.errorStatus, result.errorMessage)
        RETURN NULL
    END IF

    IF result.body IS NOT NULL THEN
        LET response = result.body
    ELSE
        LET response = util.JSONObject.create()
        CALL response.put("rowsAffected", result.rowsAffected)
    END IF

    RETURN response

END FUNCTION #dispatchWrite

PRIVATE FUNCTION getQueryOperation(query STRING)
    DEFINE qTrim STRING
    DEFINE opStr STRING

    LET qTrim = query.toLowerCase().trimLeftWhiteSpace()
    LET qTrim = qTrim.split('[ \t\n\r]')[1]
    CASE qTrim
        WHEN 'select'
            LET opStr = cFetchOperation
        OTHERWISE
            LET opStr = 'UNKNOWN'
    END CASE

    RETURN opStr

END FUNCTION

PRIVATE FUNCTION getSqlOperator(restOperator STRING)

    RETURN NVL(md_sqlOperator[restOperator], md_sqlOperator['eq'])

END FUNCTION #getSqlOperator

PRIVATE FUNCTION authorizationCheck(
    tabname STRING, operation STRING)
    RETURNS BOOLEAN
    DEFINE userScopes TUserScopes

    IF NOT useScopes THEN
        RETURN TRUE
    END IF

    CALL userScopes.init(httpContext["scopes"])
    IF userScopes.hasTableOperation(tabname, operation) THEN
        RETURN TRUE
    END IF

    CALL setRestError(_ERR_UNAUTHORIZED, NULL)
    RETURN FALSE

END FUNCTION #authorizationCheck

FUNCTION setRestError(respCode STRING, tableName STRING)
    DEFINE httpStatus STRING

    INITIALIZE responseError,
        internalError,
        badRequestError,
        notFoundError,
        unAuthError TO NULL
    LET responseError.respCode = respCode
    CASE respCode
        WHEN _ERR_BAD_REQUEST
            LET httpStatus = _ERR_BAD_REQUEST
            CALL com.WebServiceEngine.SetRestError(httpStatus, badRequestError)
        WHEN _ERR_UNAUTHORIZED
            LET httpStatus = _ERR_UNAUTHORIZED
            CALL com.WebServiceEngine.SetRestError(httpStatus, unAuthError)
        WHEN _ERR_NOT_FOUND
            LET httpStatus = _ERR_NOT_FOUND
            CALL com.WebServiceEngine.SetRestError(httpStatus, notFoundError)
        WHEN _ERR_TABLE_DNE
            LET httpStatus = _ERR_NOT_FOUND
            LET notFoundError.respMessage =
                SFMT("Table %1 does not exist", tableName)
            CALL com.WebServiceEngine.SetRestError(httpStatus, notFoundError)
        WHEN _ERR_TABLE_EMPTY
            LET httpStatus = _ERR_INTERNAL
            LET internalError.respMessage =
                SFMT("Table %1 does not have any records", tableName)
            CALL com.WebServiceEngine.SetRestError(httpStatus, internalError)
        WHEN _ERR_ARG_CNT_MISMATCH
            LET httpStatus = _ERR_BAD_REQUEST
            LET badRequestError.respMessage =
                SFMT("Argument count mismatch", tableName)
            CALL com.WebServiceEngine.SetRestError(httpStatus, badRequestError)
        OTHERWISE # Unknown, assume internal server error since we missed a case
            LET httpStatus = _ERR_INTERNAL
            CALL com.WebServiceEngine.SetRestError(httpStatus, internalError)
    END CASE
END FUNCTION #setRestError

##############################################################################################
#+
#+ setWriteError Sets a REST error for a delegated write using the HTTP status
#+ and message returned by the delegate, without coupling to the fixed _ERR_*
#+ codes used by the read endpoints.
#+
##############################################################################################
PRIVATE FUNCTION setWriteError(httpStatus INTEGER, message STRING)

    INITIALIZE responseError TO NULL
    LET responseError.respCode = httpStatus
    LET responseError.respMessage = message
    CALL com.WebServiceEngine.SetRestError(httpStatus, responseError)

END FUNCTION #setWriteError
