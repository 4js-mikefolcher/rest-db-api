##############################################################################################
# custdemoService.4gl provides web service interface for all the tables in the
#  custdemo database
##############################################################################################

IMPORT com
IMPORT FGL com.fourjs.restdblib.ServiceHelper
IMPORT FGL com.fourjs.restdblib.WriteDelegates
IMPORT FGL NorthwindWrites

MAIN
    DEFINE lMessage STRING
    CONNECT TO "northwind@localhost+driver='dbmpgs'" USER "nwuser" USING "fourjs123"

    CALL startlog("NorthwindService.log")

    VAR success = ServiceHelper.registerService("northwind")
    IF NOT success THEN
       EXIT PROGRAM -1
    END IF

    # Register the write delegates (delegate-only: the library has no generic
    # write SQL). Single-key table:
    CALL WriteDelegates.registerInsert(
        "categories", FUNCTION NorthwindWrites.insertCategory)
    CALL WriteDelegates.registerUpdate(
        "categories", FUNCTION NorthwindWrites.updateCategory)
    CALL WriteDelegates.registerDelete(
        "categories", FUNCTION NorthwindWrites.deleteCategory)
    # Composite-key table:
    CALL WriteDelegates.registerUpdate(
        "order_details", FUNCTION NorthwindWrites.updateOrderDetail)

    IF arg_val(1) == "--debug" THEN
        LET ServiceHelper.useScopes = FALSE
    END IF

    DISPLAY "Server started"
    LET lMessage = com.fourjs.restdblib.ServiceHelper.startService()
    DISPLAY lMessage

END MAIN