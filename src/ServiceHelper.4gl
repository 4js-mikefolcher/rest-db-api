##############################################################################################
# serverHelper.4gl provides functions to define URI endpoints for GET, POST, PUT, and DELETE
# without relying on the database schema.
##############################################################################################
IMPORT com
IMPORT util
IMPORT FGL SQLHelper
IMPORT FGL UserScopes
IMPORT FGL jsonParser

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
                RETURN "Disconnected from application server."
            WHEN -3
                DISPLAY "Client Connection lost."
            WHEN -4
                DISPLAY "Server interrupted with Ctrl-C."
            WHEN -9
                DISPLAY "Unsupported operation."
                DISPLAY sqlca.sqlerrm
            WHEN -10
                DISPLAY "Internal server error."
            WHEN -23
                DISPLAY "Deserialization error."
            WHEN -35
                DISPLAY "No such REST operation found."
            WHEN -36
                DISPLAY "Missing REST parameter."
            OTHERWISE
                RETURN SFMT("Unexpected server error %1.", serviceStatus)
                LET int_flag = TRUE
        END CASE

    END WHILE
    RETURN "Server stopped"

END FUNCTION

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

    IF NOT authorizationCheck(tableName, UserScopes.cFetchOperation) THEN
        RETURN jsonArray
    END IF

    LET jsonArray = SQLHelper.getTableRecords(tableName, -1, -1)

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

    IF NOT authorizationCheck(tableName, UserScopes.cFetchOperation) THEN
        RETURN lCount
    END IF

    LET lCount = SQLHelper.getTableRecordCount(tableName)

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
#+ getRecordCount Gets and returns all number of records in a table
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

    IF NOT authorizationCheck(tableName, UserScopes.cFetchOperation) THEN
        RETURN jsonObj
    END IF

    LET schemaList = SQLHelper.getTableSchema(tableName)

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

    IF NOT authorizationCheck(tableName, UserScopes.cFetchOperation) THEN
        RETURN jsonArray
    END IF

    LET jsonArray = SQLHelper.getTableRecords(tableName, recLimit, -1)

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

    IF NOT authorizationCheck(tableName, UserScopes.cFetchOperation) THEN
        RETURN jsonArray
    END IF

    LET jsonArray = SQLHelper.getTableRecords(tableName, recLimit, recOffset)

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

    IF NOT authorizationCheck(tableName, UserScopes.cFetchOperation) THEN
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
        LET jsonArray = SQLHelper.getTableRecords(tableName, -1, -1)
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
        LET jsonArray =
            SQLHelper.getTableQuery(tableName, colList, valList, opListSQL)
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
#+ getQueryResults Gets and returns all the records in a table that match the query criteria.
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
    DEFINE temp_rec jsonParser.t_jsonBody
    CALL jsonObj.toFGL(temp_rec)
    LET sqlString = temp_rec.toSQLString()
    LET jsonArray = SQLHelper.runSQL(sqlString)

    # TODO: parse query to get table names and check authorization?
    IF NOT authorizationCheck("sql", UserScopes.cFetchOperation) THEN
        RETURN jsonArray
    END IF
    RETURN jsonArray

END FUNCTION #getQueryResults

{
PRIVATE FUNCTION reportIfResultsEmpty(jsonArray util.JSONArray param)
    IF jsonArray IS NULL THEN
        CALL setRestError(_ERR_INTERNAL, NULL)
    ELSE
        IF jsonArray.getLength() == 0 THEN
            CALL setRestError(_ERR_NOT_FOUND, NULL)
        END IF
    END IF
END FUNCTION #reportIfResultsEmpty
}

PRIVATE FUNCTION getQueryOperation(query STRING)
    DEFINE qTrim STRING
    DEFINE opStr STRING

    LET qTrim = query.toLowerCase().trimLeftWhiteSpace()
    LET qTrim = qTrim.split('[ \t\n\r]')[1]
    CASE qTrim
        WHEN 'select'
            LET opStr = UserScopes.cFetchOperation
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
    DEFINE userScopes UserScopes.TUserScopes

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
