IMPORT util
PUBLIC TYPE t_jsonBody RECORD
    selectList DYNAMIC ARRAY ATTRIBUTES(json_name = "select") OF STRING,
    tableList DYNAMIC ARRAY ATTRIBUTES(json_name = "table") OF STRING,
    whereList DYNAMIC ARRAY ATTRIBUTES(json_name = "where") OF RECORD
        column STRING,
        value STRING,
        operator STRING
    END RECORD,
    limit FLOAT,
    orderbyList DYNAMIC ARRAY ATTRIBUTES(json_name = "orderby") OF RECORD
        column STRING,
        direction STRING
    END RECORD
END RECORD

PUBLIC FUNCTION (temp_rec t_jsonBody) toSQLString() RETURNS STRING
    DEFINE sqlString STRING
    DEFINE i INTEGER
    LET sqlString = "SELECT "
    FOR i = 1 TO temp_rec.selectList.getLength()
        LET sqlString ,= temp_rec.selectList[i]
        IF i < temp_rec.selectList.getLength() THEN
            LET sqlString ,= ", "
        END IF
    END FOR
    LET sqlString ,= " FROM "
    FOR i = 1 TO temp_rec.tableList.getLength()
        LET sqlString ,= temp_rec.tableList[i]
        IF i < temp_rec.tableList.getLength() THEN
            LET sqlString ,= ", "
        END IF
    END FOR
    IF temp_rec.whereList.getLength() > 0 THEN
        LET sqlString ,= " WHERE "
        FOR i = 1 TO temp_rec.whereList.getLength()
            #TODO Check for value type
            IF temp_rec.whereList[i].value LIKE "%%" THEN
                LET sqlString ,= temp_rec.whereList[i].column || " " || temp_rec.whereList[i].operator || " '" || temp_rec.whereList[i].value || "'"
            ELSE
                LET sqlString ,= temp_rec.whereList[i].column || " " || temp_rec.whereList[i].operator || " " || temp_rec.whereList[i].value
            END IF
            IF i < temp_rec.whereList.getLength() THEN
                LET sqlString ,= " AND "
            END IF
        END FOR
    END IF
    IF temp_rec.orderbyList.getLength() > 0 THEN
        LET sqlString ,= " ORDER BY "
        FOR i = 1 TO temp_rec.orderbyList.getLength()
            LET sqlString ,= temp_rec.orderbyList[i].column || " " || temp_rec.orderbyList[i].direction
            IF i < temp_rec.orderbyList.getLength() THEN
                LET sqlString ,= ", "
            END IF
        END FOR
    END IF
    IF temp_rec.limit > 0 THEN
        LET sqlString ,= " LIMIT "
        LET sqlString ,= util.JSON.stringify(temp_rec.limit)
    END IF
    RETURN sqlString
END FUNCTION