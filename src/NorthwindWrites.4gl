##############################################################################################
# NorthwindWrites.4gl
#
# Example write delegates for the Northwind (PostgreSQL) service. These are the
# customer-authored callbacks that restdblib's POST/PUT/DELETE endpoints dispatch
# to. They demonstrate:
#   - a single-key table  : categories     (key categoryid, sequence-assigned)
#   - a composite-key table: order_details (keys orderid + productid)
#
# Each function MUST match WriteDelegates.T_WriteHandler exactly, including the
# parameter name "request".
#
# Values are bound through typed FGL variables so PostgreSQL (strict typing)
# accepts them - the same reason SQLHelper uses setParameterType().
##############################################################################################
IMPORT util
IMPORT FGL com.fourjs.restdblib.WriteDelegates

##############################################################################################
#+ Insert a category. Body: { "categoryname": "...", "description": "..." }.
#+ categoryid is sequence-assigned and returned in the response body.
##############################################################################################
PUBLIC FUNCTION insertCategory(request WriteDelegates.T_WriteRequest)
    RETURNS WriteDelegates.T_WriteResult
    DEFINE sqlObj base.SqlHandle
    DEFINE name, descr STRING
    DEFINE newId INTEGER
    DEFINE response util.JSONObject

    LET name = request.body.get("categoryname")
    LET descr = request.body.get("description")
    IF name IS NULL OR name.getLength() == 0 THEN
        RETURN WriteDelegates.errorResult(400, "categoryname is required")
    END IF

    TRY
        BEGIN WORK
        LET sqlObj = base.SqlHandle.create()
        CALL sqlObj.prepare(
            "INSERT INTO categories (categoryname, description) VALUES (?, ?)")
        CALL sqlObj.setParameter(1, name)
        CALL sqlObj.setParameter(2, descr)
        CALL sqlObj.execute()
        CALL sqlObj.close()
        # dbmpgs does not surface INSERT ... RETURNING through SqlHandle, so read
        # the sequence value just assigned on this connection.
        LET sqlObj = base.SqlHandle.create()
        CALL sqlObj.prepare("SELECT lastval()")
        CALL sqlObj.open()
        CALL sqlObj.fetch()
        LET newId = sqlObj.getResultValue(1)
        CALL sqlObj.close()
        COMMIT WORK
    CATCH
        CALL safeRollback()
        RETURN WriteDelegates.errorResult(
            500, SFMT("Insert failed (SQLCODE %1): %2", sqlca.sqlcode, sqlerrmessage))
    END TRY

    LET response = util.JSONObject.create()
    CALL response.put("categoryid", newId)
    CALL response.put("rowsAffected", 1)
    RETURN WriteDelegates.okResult(1, response)

END FUNCTION #insertCategory

##############################################################################################
#+ Update a category by categoryid. Body may carry "categoryname" and/or
#+ "description"; only the supplied fields are changed.
##############################################################################################
PUBLIC FUNCTION updateCategory(request WriteDelegates.T_WriteRequest)
    RETURNS WriteDelegates.T_WriteResult
    DEFINE sqlObj base.SqlHandle
    DEFINE catId INTEGER
    DEFINE descr STRING
    DEFINE affected INTEGER

    LET catId = keyByName(request.keyParts, "categoryid")
    IF catId IS NULL THEN
        RETURN WriteDelegates.errorResult(400, "categoryid key is required")
    END IF
    LET descr = request.body.get("description")
    IF descr IS NULL THEN
        RETURN WriteDelegates.errorResult(400, "description is required")
    END IF

    TRY
        BEGIN WORK
        LET sqlObj = base.SqlHandle.create()
        CALL sqlObj.prepare(
            "UPDATE categories SET description = ? WHERE categoryid = ?")
        CALL sqlObj.setParameter(1, descr)
        CALL sqlObj.setParameter(2, catId)
        CALL sqlObj.execute()
        LET affected = sqlca.sqlerrd[3]
        CALL sqlObj.close()
        COMMIT WORK
    CATCH
        CALL safeRollback()
        RETURN WriteDelegates.errorResult(
            500, SFMT("Update failed (SQLCODE %1): %2", sqlca.sqlcode, sqlerrmessage))
    END TRY

    IF affected == 0 THEN
        RETURN WriteDelegates.errorResult(
            404, SFMT("No category with categoryid %1", catId))
    END IF
    RETURN WriteDelegates.okResult(affected, NULL)

END FUNCTION #updateCategory

##############################################################################################
#+ Delete a category by categoryid.
##############################################################################################
PUBLIC FUNCTION deleteCategory(request WriteDelegates.T_WriteRequest)
    RETURNS WriteDelegates.T_WriteResult
    DEFINE sqlObj base.SqlHandle
    DEFINE catId INTEGER
    DEFINE affected INTEGER

    LET catId = keyByName(request.keyParts, "categoryid")
    IF catId IS NULL THEN
        RETURN WriteDelegates.errorResult(400, "categoryid key is required")
    END IF

    TRY
        BEGIN WORK
        LET sqlObj = base.SqlHandle.create()
        CALL sqlObj.prepare("DELETE FROM categories WHERE categoryid = ?")
        CALL sqlObj.setParameter(1, catId)
        CALL sqlObj.execute()
        LET affected = sqlca.sqlerrd[3]
        CALL sqlObj.close()
        COMMIT WORK
    CATCH
        CALL safeRollback()
        RETURN WriteDelegates.errorResult(
            500, SFMT("Delete failed (SQLCODE %1): %2", sqlca.sqlcode, sqlerrmessage))
    END TRY

    IF affected == 0 THEN
        RETURN WriteDelegates.errorResult(
            404, SFMT("No category with categoryid %1", catId))
    END IF
    RETURN WriteDelegates.okResult(affected, NULL)

END FUNCTION #deleteCategory

##############################################################################################
#+ Update an order_details row identified by the composite key (orderid,
#+ productid). Body: { "quantity": <n> }. Demonstrates keyParts usage.
##############################################################################################
PUBLIC FUNCTION updateOrderDetail(request WriteDelegates.T_WriteRequest)
    RETURNS WriteDelegates.T_WriteResult
    DEFINE sqlObj base.SqlHandle
    DEFINE orderId, productId INTEGER
    DEFINE quantity SMALLINT
    DEFINE affected INTEGER

    LET orderId = keyByName(request.keyParts, "orderid")
    LET productId = keyByName(request.keyParts, "productid")
    IF orderId IS NULL OR productId IS NULL THEN
        RETURN WriteDelegates.errorResult(
            400, "composite key orderid and productid are required")
    END IF
    LET quantity = request.body.get("quantity")
    IF quantity IS NULL THEN
        RETURN WriteDelegates.errorResult(400, "quantity is required")
    END IF

    TRY
        BEGIN WORK
        LET sqlObj = base.SqlHandle.create()
        CALL sqlObj.prepare(
            "UPDATE order_details SET quantity = ?"
            || " WHERE orderid = ? AND productid = ?")
        CALL sqlObj.setParameter(1, quantity)
        CALL sqlObj.setParameter(2, orderId)
        CALL sqlObj.setParameter(3, productId)
        CALL sqlObj.execute()
        LET affected = sqlca.sqlerrd[3]
        CALL sqlObj.close()
        COMMIT WORK
    CATCH
        CALL safeRollback()
        RETURN WriteDelegates.errorResult(
            500, SFMT("Update failed (SQLCODE %1): %2", sqlca.sqlcode, sqlerrmessage))
    END TRY

    IF affected == 0 THEN
        RETURN WriteDelegates.errorResult(
            404, SFMT("No order_details row for orderid %1, productid %2",
                orderId, productId))
    END IF
    RETURN WriteDelegates.okResult(affected, NULL)

END FUNCTION #updateOrderDetail

##############################################################################################
#+ Find a key part's value by column name. Falls back to the sole value when a
#+ single unnamed key was supplied (e.g. /table/categories/5).
##############################################################################################
PRIVATE FUNCTION keyByName(
    parts DYNAMIC ARRAY OF WriteDelegates.T_WriteKeyPart, name STRING)
    RETURNS STRING
    DEFINE i INTEGER

    FOR i = 1 TO parts.getLength()
        IF parts[i].name IS NOT NULL
            AND parts[i].name.equalsIgnoreCase(name) THEN
            RETURN parts[i].value
        END IF
    END FOR

    # Unnamed single-key form: /table/{t}/{value}
    IF parts.getLength() == 1
        AND (parts[1].name IS NULL OR parts[1].name.getLength() == 0) THEN
        RETURN parts[1].value
    END IF

    RETURN NULL

END FUNCTION #keyByName

##############################################################################################
#+ Best-effort ROLLBACK WORK used from a CATCH block, so a failed rollback does
#+ not mask the original error.
##############################################################################################
PRIVATE FUNCTION safeRollback()
    TRY
        ROLLBACK WORK
    CATCH
    END TRY
END FUNCTION #safeRollback
