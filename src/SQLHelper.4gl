##############################################################################################
# sqlHelper.4gl provides functions to perform generic SQL commands SELECT, INSERT, UPDATE,
#  and DELETE
##############################################################################################
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

    WHENEVER ANY ERROR CALL errorHandler

    #Initialize the SQL Statement and JSON Array
    LET lSQLSelect = SFMT("SELECT * FROM %1 WHERE", tableName)
    FOR colIdx = 1 TO colName.getLength()
        LET lSQLSelect =
            lSQLSelect,
            SFMT(" (%1 %2 ?) AND", colName[colIdx], operator[colIdx])
    END FOR
    LET lSQLSelect = lSQLSelect.trimRight(), " 1=1"

    VAR colValueJSON util.JSONArray = util.JSONArray.create()
    FOR colIdx = 1 TO colValue.getLength()
        CALL colValueJSON.put(colIdx, colValue[colIdx])
    END FOR
    LET jsonArray = getQuery(lSQLSelect, colValueJSON)

    RETURN jsonArray

END FUNCTION

PUBLIC FUNCTION getQuery(
    lQuery STRING, paramList util.JSONArray)
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

##############################################################################################
#+
#+ insertFromJSON Inserts into the specified table using the JSONObject for the values
#+
##############################################################################################
PUBLIC FUNCTION insertFromJSON(tableName STRING, jsonObj util.JSONObject) RETURNS INTEGER
    DEFINE lErrorStatus INTEGER = 0
    DEFINE lInsertSQL STRING = "INSERT INTO %1 (%2) VALUES(%3)"
    DEFINE lColList STRING
    DEFINE lValueList STRING
    DEFINE lIndex INTEGER = 0
    DEFINE sqlObj base.SqlHandle
    DEFINE aColNames DYNAMIC ARRAY OF STRING

    WHENEVER ANY ERROR CALL errorHandler

    #Parse the list for the number and name of columns
    CALL aColNames.clear()
    FOR lIndex = 1 TO jsonObj.getLength()
        IF lIndex == 1 THEN
            LET lColList = jsonObj.name(lIndex)
            LET lValueList = "?"
        ELSE
            LET lColList = SFMT("%1,%2", lColList, jsonObj.name(lIndex))
            LET lValueList = SFMT("%1,?", lValueList)
        END IF
        CALL aColNames.appendElement()
        LET aColNames[lIndex] = jsonObj.name(lIndex)
    END FOR

    #Initialize the SQL Statement and SQL Handler
    LET lInsertSQL = SFMT(lInsertSQL, tableName, lColList, lValueList)
    LET sqlObj = base.SqlHandle.create()
    TRY
        #Build the SQL Handler
        BEGIN WORK
        CALL sqlObj.prepare(lInsertSQL)
        CALL sqlObj.open()
        FOR lIndex = 1 TO aColNames.getLength()
            CALL sqlObj.setParameter(lIndex, jsonObj.get(aColNames[lIndex]))
        END FOR
        CALL sqlObj.put()
        CALL sqlObj.flush()
        CALL sqlObj.close()
        COMMIT WORK
    CATCH
        LET lErrorStatus = 500
    END TRY

    RETURN lErrorStatus

END FUNCTION

##############################################################################################
#+
#+ updateFromJSON Updates the specified table using the JSONObject for the new values
#+ colName is the column name used in the where clause
#+ colValue is the column value used int he where clause
#+
##############################################################################################
PUBLIC FUNCTION updateFromJSON(
    tableName STRING, colName STRING, colValue STRING, jsonObj util.JSONObject)
    RETURNS INTEGER
    DEFINE lErrorStatus INTEGER = 0
    DEFINE lUpdateSQL STRING = "UPDATE %1 SET %2 WHERE %3 = ?"
    DEFINE lSetList STRING
    DEFINE lIndex INTEGER = 0
    DEFINE lintX INTEGER = 0
    DEFINE sqlObj base.SqlHandle
    DEFINE aColNames DYNAMIC ARRAY OF STRING
    DEFINE jsonColName STRING

    WHENEVER ANY ERROR CALL errorHandler

    #Parse the list for the number and name of column
    CALL aColNames.clear()
    FOR lIndex = 1 TO jsonObj.getLength()
        LET jsonColName = jsonObj.name(lIndex)
        IF jsonColName == colName THEN
            #Do not update the column/value pair used in the where clause
            CONTINUE FOR
        END IF
        IF lSetList.getLength() == 0 THEN
            LET lSetList = SFMT("%1 = ?", jsonColName)
        ELSE
            LET lSetList = SFMT("%1, %2 = ?", lSetList, jsonColName)
        END IF
        CALL aColNames.appendElement()
        LET lintX = aColNames.getLength()
        LET aColNames[lintX] = jsonColName
    END FOR

    #Initialize the SQL Statement and SQL Handler
    LET lUpdateSQL = SFMT(lUpdateSQL, tableName, lSetList, colName)
    LET sqlObj = base.SqlHandle.create()
    TRY
        #Build the SQL Handler
        BEGIN WORK
        CALL sqlObj.prepare(lUpdateSQL)
        FOR lIndex = 1 TO aColNames.getLength()
            CALL sqlObj.setParameter(lIndex, jsonObj.get(aColNames[lIndex]))
        END FOR
        #Set the where parameter last
        LET lIndex = aColNames.getLength() + 1
        CALL sqlObj.setParameter(lIndex, colValue)
        CALL sqlObj.execute()
        CALL sqlObj.close()
        COMMIT WORK
    CATCH
        LET lErrorStatus = 500
    END TRY

    RETURN lErrorStatus

END FUNCTION

##############################################################################################
#+
#+ deleteRecordWithColumnValue Deletes from the specified table
#+ colName is the column name used in the where clause
#+ colValue is the column value used int he where clause
#+
##############################################################################################
PUBLIC FUNCTION deleteRecordWithColumnValue(
    tableName STRING, colName STRING, colValue STRING)
    RETURNS INTEGER

    DEFINE lErrorStatus INTEGER = 0
    DEFINE lDeleteSQL STRING = "DELETE FROM %1 WHERE %2 = ?"
    DEFINE sqlObj base.SqlHandle

    WHENEVER ANY ERROR CALL errorHandler

    #Initialize the SQL Statement and SQL Handler
    LET lDeleteSQL = SFMT(lDeleteSQL, tableName, colName)
    LET sqlObj = base.SqlHandle.create()
    TRY
        #Build the SQL Handler for delete
        BEGIN WORK
        CALL sqlObj.prepare(lDeleteSQL)
        CALL sqlObj.setParameter(1, colValue)
        CALL sqlObj.execute()
        CALL sqlObj.close()
        COMMIT WORK
    CATCH
        LET lErrorStatus = 500
    END TRY

    RETURN lErrorStatus

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
