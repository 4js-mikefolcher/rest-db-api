##############################################################################################
# sqlHelper.4gl provides functions to perform generic SQL commands SELECT, INSERT, UPDATE,
#  and DELETE
##############################################################################################
PACKAGE com.fourjs.restdblib

IMPORT util

##############################################################################################
#+
#+ getTableRecords Returns a JSONArray of all the records in the specified table
#+ recLimit and recOffset provide the ability to limit the return record size and start at
#+ an offset
#+
##############################################################################################
PUBLIC FUNCTION getTableRecords(
    tableName STRING, recLimit INTEGER, recOffset INTEGER)
    RETURNS util.JSONArray

    DEFINE jsonArray util.JSONArray
    DEFINE jsonObj util.JSONObject
    DEFINE lSQLSelect STRING
    DEFINE sqlObj base.SqlHandle
    DEFINE lIndex INTEGER = 0
    DEFINE lCount INTEGER = 0
    DEFINE lMoreRecords BOOLEAN = TRUE
    DEFINE lFetchOffset BOOLEAN = FALSE

    WHENEVER ANY ERROR CALL errorHandler

    #Initialize the SQL Statement and JSON Array
    LET lSQLSelect = SFMT("SELECT * FROM %1", tableName)
    LET jsonArray = util.JSONArray.create()

    TRY
        #Construct the SQLHandler object
        LET sqlObj = base.SqlHandle.create()
        CALL sqlObj.prepare(lSQLSelect)
        IF recOffset < 1 THEN
            #No Offset defined
            CALL sqlObj.open()
        ELSE
            #Offset is defined
            CALL sqlObj.openScrollCursor()
            LET lFetchOffset = TRUE
        END IF

        WHILE lMoreRecords

            IF lFetchOffset THEN
                CALL sqlObj.fetchAbsolute(recOffset)
                LET recOffset = recOffset + 1
            ELSE
                CALL sqlObj.fetch()
            END IF

            IF sqlca.sqlcode == NOTFOUND THEN
                LET lMoreRecords = FALSE
            ELSE
                #Create a JSON Object for each record
                LET jsonObj = util.JSONObject.create()
                FOR lIndex = 1 TO sqlObj.getResultCount()
                    CALL jsonObj.put(
                        sqlObj.getResultName(lIndex),
                        sqlObj.getResultValue(lIndex))
                END FOR

                #Add the JSON Object to the JSON Array
                LET lCount = lCount + 1
                CALL jsonArray.put(lCount, jsonObj)
                IF recLimit > 0 AND lCount >= recLimit THEN
                    #If a limit is specified and we reach it stop looping
                    LET lMoreRecords = FALSE
                END IF
            END IF

        END WHILE
        CALL sqlObj.close()

    CATCH
        LET jsonArray = NULL
    END TRY

    RETURN jsonArray

END FUNCTION

##############################################################################################
#+
#+ getTableQuery Selects the rows from the specified table that match the query criteria
#+ colName is the column name for the where clause
#+ colValue is the column value for the where clause
#+ useLike will use LIKE instead of equality as the comparison operator
#+
##############################################################################################
PUBLIC FUNCTION getTableQuery(
    tableName STRING,
    colName DYNAMIC ARRAY OF STRING,
    colValue DYNAMIC ARRAY OF STRING,
    operator DYNAMIC ARRAY OF STRING)
    RETURNS util.JSONArray

    DEFINE jsonArray util.JSONArray
    DEFINE lSQLSelect STRING
    DEFINE colIdx INTEGER
    DEFINE schemaList DICTIONARY OF STRING
    DEFINE paramTypes DYNAMIC ARRAY OF STRING

    WHENEVER ANY ERROR CALL errorHandler

    # Look up the column types so numeric predicates can be bound with a numeric
    # type. Strict databases (e.g. PostgreSQL) reject comparisons such as
    # "real > varchar" when the value is bound as a string.
    LET schemaList = getTableSchema(tableName)

    #Initialize the SQL Statement and JSON Array
    LET lSQLSelect = SFMT("SELECT * FROM %1 WHERE", tableName)
    FOR colIdx = 1 TO colName.getLength()
        LET lSQLSelect =
            lSQLSelect,
            SFMT(" (%1 %2 ?) AND", colName[colIdx], operator[colIdx])
        # A LIKE/contains value is always a string (wrapped in %..%); only treat
        # the parameter as numeric for the comparison operators.
        IF operator[colIdx] != "LIKE" THEN
            LET paramTypes[colIdx] = schemaList[colName[colIdx]]
        ELSE
            LET paramTypes[colIdx] = ""
        END IF
    END FOR
    LET lSQLSelect = lSQLSelect.trimRight(), " 1=1"

    VAR colValueJSON util.JSONArray = util.JSONArray.create()
    FOR colIdx = 1 TO colValue.getLength()
        CALL colValueJSON.put(colIdx, colValue[colIdx])
    END FOR
    LET jsonArray = getQuery(lSQLSelect, colValueJSON, paramTypes)

    RETURN jsonArray

END FUNCTION

PUBLIC FUNCTION getQuery(
    lQuery STRING,
    paramList util.JSONArray,
    paramTypes DYNAMIC ARRAY OF STRING)
    RETURNS util.JSONArray

    DEFINE sqlObj base.SqlHandle
    DEFINE jsonArray util.JSONArray
    DEFINE jsonObj util.JSONObject
    DEFINE lIndex INTEGER = 0
    DEFINE lCount INTEGER = 0
    DEFINE lMoreRecords BOOLEAN = TRUE
    DEFINE paramIdx INTEGER = 0

    LET jsonArray = util.JSONArray.create()
    TRY
        # Build and open the SQLHandler
        LET sqlObj = base.SqlHandle.create()
        CALL sqlObj.prepare(lQuery)
        FOR paramIdx = 1 TO paramList.getLength()
            # The values arrive as strings, so the parameter type must be
            # declared explicitly (Genero docs: mandatory with string values to
            # avoid SQL type conversion issues). Using the column's own Genero
            # type keeps this database-agnostic - it works for numeric, date and
            # string columns on every supported driver. An empty type (e.g. a
            # LIKE value) falls back to default string binding.
            # Note: a LIKE value is passed with an empty type, and an empty
            # string is NULL in Genero, so the IS NOT NULL test covers both the
            # "no type known" and "keep string binding" cases.
            IF paramIdx <= paramTypes.getLength()
                AND paramTypes[paramIdx] IS NOT NULL THEN
                CALL sqlObj.setParameterType(paramIdx, paramTypes[paramIdx])
            END IF
            CALL sqlObj.setParameter(paramIdx, paramList.get(paramIdx))
        END FOR
        CALL sqlObj.open()
        WHILE lMoreRecords
            #Fetch each record
            CALL sqlObj.fetch()
            IF sqlca.sqlcode == NOTFOUND THEN
                LET lMoreRecords = FALSE
            ELSE
                #Build the JSON Object
                LET jsonObj = util.JSONObject.create()
                FOR lIndex = 1 TO sqlObj.getResultCount()
                    CALL jsonObj.put(
                        sqlObj.getResultName(lIndex),
                        sqlObj.getResultValue(lIndex))
                END FOR
                #Add the JSON Object to the JSON Array
                LET lCount = lCount + 1
                CALL jsonArray.put(lCount, jsonObj)
            END IF
        END WHILE
        CALL sqlObj.close()
    CATCH
        LET jsonArray = NULL
    END TRY
    RETURN jsonArray
END FUNCTION

##############################################################################################
#+
#+ getTableRecordCount Returns the number of rows in the specified table
#+
##############################################################################################
PUBLIC FUNCTION getTableRecordCount(tableName STRING) RETURNS INTEGER

    DEFINE lSQLSelect STRING
    DEFINE sqlObj base.SqlHandle
    DEFINE lCount INTEGER = 0
    DEFINE lIndex INTEGER
    DEFINE lColName STRING = "rec_count"

    WHENEVER ANY ERROR CALL errorHandler

    #Initialize the SQL Statement and SQL Handler
    LET lSQLSelect = SFMT("SELECT COUNT(*) AS %2 FROM %1", tableName, lColName)
    LET sqlObj = base.SqlHandle.create()

    TRY
        #Build the SQL Handler
        CALL sqlObj.prepare(lSQLSelect)
        CALL sqlObj.open()
        CALL sqlObj.fetch()
        FOR lIndex = 1 TO sqlObj.getResultCount()
            IF sqlObj.getResultName(lIndex) == lColName THEN
                #Get the count and exit the loop
                LET lCount = sqlObj.getResultValue(lIndex)
                EXIT FOR
            END IF
        END FOR
        CALL sqlObj.close()

    CATCH
        LET lCount = 0
    END TRY

    RETURN lCount

END FUNCTION

PUBLIC FUNCTION getTableSchema(tableName STRING) RETURNS DICTIONARY OF STRING
    DEFINE schemaList DICTIONARY OF STRING
    DEFINE idx INTEGER

    #Initialize the SQL Statement and JSON Array
    VAR sqlStmt = SFMT("SELECT * FROM %1", tableName)

    TRY
        VAR sqlObj = base.SqlHandle.create()
        CALL sqlObj.prepare(sqlStmt)
        CALL sqlObj.open()
        FOR idx = 1 TO sqlObj.getResultCount()
            VAR colName = sqlObj.getResultName(idx)
            VAR colType = sqlObj.getResultType(idx)
            LET schemaList[colName] = colType
        END FOR
        CALL sqlObj.close()
    CATCH
        CALL schemaList.clear()
    END TRY

    RETURN schemaList

END FUNCTION #getTableSchema

PRIVATE FUNCTION errorHandler()
    CALL errorlog(SFMT("Error Code: %1", status))
    CALL errorlog(base.Application.getStackTrace())
    EXIT PROGRAM -1
END FUNCTION
##############################################################################################
#+
#+ runSQL
#+ Executes the provided SQL statement
#+
##############################################################################################
PUBLIC FUNCTION runSQL(lSQL STRING) RETURNS util.JSONArray
    DEFINE sqlObj base.SqlHandle
    DEFINE jsonArray util.JSONArray
    DEFINE jsonObj util.JSONObject
    DEFINE lIndex INTEGER = 0
    DEFINE lCount INTEGER = 0
    DEFINE lMoreRecords BOOLEAN = TRUE

    LET jsonArray = util.JSONArray.create()
    TRY
        LET sqlObj = base.SqlHandle.create()
        CALL sqlObj.prepare(lSQL)
        CALL sqlObj.open()
        WHILE lMoreRecords
            #Fetch each record
            CALL sqlObj.fetch()
            IF sqlca.sqlcode == NOTFOUND THEN
                LET lMoreRecords = FALSE
            ELSE
                #Build the JSON Object
                LET jsonObj = util.JSONObject.create()
                FOR lIndex = 1 TO sqlObj.getResultCount()
                    CALL jsonObj.put(
                        sqlObj.getResultName(lIndex),
                        sqlObj.getResultValue(lIndex))
                END FOR
                #Add the JSON Object to the JSON Array
                LET lCount = lCount + 1
                CALL jsonArray.put(lCount, jsonObj)
            END IF
        END WHILE
        CALL sqlObj.close()
    CATCH
        LET jsonArray = NULL
    END TRY

    RETURN jsonArray
END FUNCTION