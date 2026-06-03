##############################################################################################
# custdemoService.4gl provides web service interface for all the tables in the
#  custdemo database
##############################################################################################

IMPORT com
IMPORT FGL com.fourjs.restdblib.ServiceHelper

MAIN
    DEFINE lMessage STRING
    CONNECT TO "northwind@localhost+driver='dbmpgs'" USER "nwuser" USING "fourjs123"

    CALL startlog("NorthwindService.log")

    VAR success = ServiceHelper.registerService("northwind")
    IF NOT success THEN
       EXIT PROGRAM -1
    END IF

    IF arg_val(1) == "--debug" THEN
        LET ServiceHelper.useScopes = FALSE
    END IF

    DISPLAY "Server started"
    LET lMessage = com.fourjs.restdblib.ServiceHelper.startService()
    DISPLAY lMessage

END MAIN